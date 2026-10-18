defmodule Noa.GitHub do
  @moduledoc """
  GitHub (3.7): pushes, pull requests and CI runs from a project's repo become part of
  the company graph, so agent packs, `@noa` and who-knows-what see what is being built.

  A webhook (`POST /webhooks/github`, signed with the owning workspace's secret from
  Settings → Connectors, or the platform's `GITHUB_WEBHOOK_SECRET`) or a backfill
  (`backfill/2`, with the workspace's token or `GITHUB_TOKEN` for private repos) hands
  events to `handle/2`. Each
  is matched to the project whose `repo` is the repository (`Owner/name`), and its author
  to a person by git handle, name or email, then appended to the event log once:

    * `commit.pushed`: one per commit pushed to any branch (`github:commit:<sha>`)
    * `pr.saved`: a pull request opened, updated, merged or closed (its state each time)
    * `ci.completed`: a finished workflow run

  When a pull request is merged and an open task on the project has the same title, or
  its branch carries the task's words, Noa proposes moving that task to done (an Inbox
  proposal, approved like any other).
  """
  require Ash.Query

  alias Noa.{Events, Work}
  alias Noa.Work.{Person, Project, Proposal, Task}

  @doc """
  Whether `signature` (`sha256=<hex>`) is the HMAC of `raw` with the webhook secret of
  the workspace that owns `repo` (set by its org admin in Settings → Connectors), or the
  platform's `GITHUB_WEBHOOK_SECRET` as a fallback.
  """
  def valid_signature?(raw, signature, repo) do
    project = repo && project_for(repo)

    secrets =
      [project && Noa.Connectors.github_secret(project.org_id), secret()]
      |> Enum.filter(&(is_binary(&1) and &1 != ""))

    case signature do
      "sha256=" <> hex ->
        Enum.any?(secrets, fn s ->
          expected = :crypto.mac(:hmac, :sha256, s, raw) |> Base.encode16(case: :lower)
          Plug.Crypto.secure_compare(expected, String.downcase(hex))
        end)

      _ ->
        false
    end
  end

  @doc "Whether webhooks can be checked at all: a platform secret, or any workspace's."
  def configured?(org_id \\ nil) do
    cond do
      is_binary(secret()) and secret() != "" -> true
      org_id -> Noa.Connectors.github_secret(org_id) != nil
      true -> true
    end
  end

  defp secret, do: Application.get_env(:noa, __MODULE__, [])[:webhook_secret]
  # The app installation's short-lived token, then a token the org admin saved, then the platform's.
  defp token(org_id) do
    installation = Noa.Connectors.installation_for(org_id)

    app_token =
      with id when is_binary(id) <- installation,
           true <- Noa.GitHub.App.configured?(),
           {:ok, token} <- Noa.GitHub.App.installation_token(id) do
        token
      else
        _ -> nil
      end

    app_token || Noa.Connectors.github_token(org_id) || Application.get_env(:noa, __MODULE__, [])[:token]
  end

  @doc "Whether an app delivery's signature matches the app's webhook secret."
  def valid_app_signature?(raw, signature) do
    case {Noa.GitHub.App.webhook_secret(), signature} do
      {secret, "sha256=" <> hex} when is_binary(secret) and secret != "" ->
        expected = :crypto.mac(:hmac, :sha256, secret, raw) |> Base.encode16(case: :lower)
        Plug.Crypto.secure_compare(expected, String.downcase(hex))

      _ ->
        false
    end
  end

  @doc """
  Handles one GitHub event (`"push"`, `"pull_request"`, `"workflow_run"`; others are
  ignored). Returns `{:ok, n}` with how many new events were recorded, or `{:ignore, reason}`.
  """
  def handle(type, payload, org_id \\ nil)

  # The app was uninstalled on GitHub: the workspace is no longer connected.
  def handle("installation", %{"action" => "deleted", "installation" => %{"id" => id}}, _org_id) do
    Noa.Connectors.remove_installation(id)
    {:ok, 0}
  end

  def handle(type, %{"repository" => %{"full_name" => repo}} = payload, org_id) do
    case project_for(repo, org_id) do
      nil -> {:ignore, :unknown_repo}
      project -> {:ok, record(type, payload, project)}
    end
  end

  def handle(_type, _payload, _org_id), do: {:ignore, :no_repository}

  defp record("push", payload, project) do
    branch = payload["ref"] |> to_string() |> String.replace_prefix("refs/heads/", "")

    for c <- payload["commits"] || [], c["distinct"] != false, reduce: 0 do
      n ->
        author = c["author"] || %{}

        data = %{
          sha: c["id"],
          message: c["message"] |> to_string() |> String.split("\n") |> hd() |> String.slice(0, 200),
          url: c["url"],
          branch: branch,
          repo: payload["repository"]["full_name"],
          project_id: project.id,
          author: author["username"] || author["name"],
          person_id: person_id(project.org_id, [author["username"], author["name"], author["email"]]),
          at: c["timestamp"]
        }

        n + append(project.org_id, "commit.pushed", data, "github:commit:#{c["id"]}", c["timestamp"])
    end
  end

  defp record("pull_request", %{"pull_request" => pr} = payload, project) do
    state = if pr["merged"] || pr["merged_at"], do: "merged", else: pr["state"]
    user = pr["user"] || %{}
    repo = payload["repository"]["full_name"]

    data = %{
      id: "#{repo}##{pr["number"]}",
      number: pr["number"],
      title: pr["title"] |> to_string() |> String.slice(0, 200),
      state: state,
      url: pr["html_url"],
      branch: get_in(pr, ["head", "ref"]),
      repo: repo,
      project_id: project.id,
      author: user["login"],
      person_id: person_id(project.org_id, [user["login"]]),
      merged_at: pr["merged_at"],
      at: pr["updated_at"]
    }

    n =
      append(
        project.org_id,
        "pr.saved",
        data,
        "github:pr:#{repo}##{pr["number"]}:#{state}:#{pr["updated_at"]}",
        pr["updated_at"]
      )

    if n == 1 and state == "merged", do: propose_done(project, data)
    n
  end

  defp record("workflow_run", %{"workflow_run" => run} = payload, project) do
    if run["status"] == "completed" do
      data = %{
        id: "#{run["id"]}:#{run["run_attempt"] || 1}",
        name: run["name"],
        conclusion: run["conclusion"],
        branch: run["head_branch"],
        sha: run["head_sha"],
        url: run["html_url"],
        repo: payload["repository"]["full_name"],
        project_id: project.id,
        at: run["updated_at"]
      }

      append(project.org_id, "ci.completed", data, "github:run:#{data.id}", run["updated_at"])
    else
      0
    end
  end

  defp record(_type, _payload, _project), do: 0

  defp append(org_id, type, data, key, at) do
    case Events.append(org_id, type, data, key: key, occurred_at: at(at)) do
      {:ok, _} -> 1
      _ -> 0
    end
  end

  defp at(nil), do: nil

  defp at(iso) do
    case DateTime.from_iso8601(to_string(iso)) do
      {:ok, at, _} -> at
      _ -> nil
    end
  end

  ## Matching

  @doc "The project whose repo is `Owner/name` (case-insensitive), in `org_id` or, when nil, any workspace."
  def project_for(repo, org_id \\ nil) do
    repo = String.downcase(to_string(repo))

    Project
    |> Ash.Query.filter(not is_nil(repo))
    |> then(fn q -> if org_id, do: Ash.Query.filter(q, org_id == ^org_id), else: q end)
    |> Ash.read!(authorize?: false)
    |> Enum.find(fn p ->
      r = p.repo |> String.downcase() |> String.replace_prefix("https://github.com/", "") |> String.trim_trailing("/")
      r == repo
    end)
  end

  # A person whose handles (git names, usernames) or email match the author.
  defp person_id(org_id, candidates) do
    wanted = candidates |> Enum.reject(&(&1 in [nil, ""])) |> Enum.map(&String.downcase(to_string(&1)))

    Person
    |> Ash.Query.filter(org_id == ^org_id)
    |> Ash.read!(authorize?: false)
    |> Enum.find(fn p ->
      names = [p.name, p.email | p.handles] |> Enum.reject(&is_nil/1) |> Enum.map(&String.downcase(to_string(&1)))
      Enum.any?(wanted, &(&1 in names))
    end)
    |> then(&(&1 && &1.id))
  end

  ## A merged PR closes its task (as a proposal)

  defp propose_done(project, pr) do
    branch_words = (pr.branch || "") |> String.downcase() |> String.split(~r/[^a-z0-9]+/, trim: true) |> MapSet.new()

    task =
      Task
      |> Ash.Query.filter(project_id == ^project.id and status != :done)
      |> Ash.read!(authorize?: false)
      |> Enum.find(fn t ->
        words =
          t.title
          |> String.downcase()
          |> String.split(~r/[^a-z0-9]+/, trim: true)
          |> Enum.filter(&(String.length(&1) > 2))

        Work.Similar.same?(t.title, pr.title) or
          (length(words) >= 2 and Enum.all?(words, &MapSet.member?(branch_words, &1)))
      end)

    if task do
      Proposal
      |> Ash.Changeset.for_create(:create, %{
        kind: :status_change,
        summary: "“#{task.title}” is done: #{pr.repo} ##{pr.number} was merged",
        data: %{"status" => "done", "pr" => pr.id, "pr_url" => pr.url},
        confidence: 0.75,
        source: %{
          "author" => pr.author,
          "quote" => "Merged: #{pr.title}",
          "channel" => "GitHub",
          "at" => pr.merged_at,
          "url" => pr.url
        },
        org_id: project.org_id,
        project_id: project.id,
        owner_id: task.owner_id,
        task_id: task.id
      })
      |> Ash.create(authorize?: false)
    end
  end

  ## Backfill

  @doc """
  Loads a project's recent history from GitHub's API: the last `:commits` commits on
  the default branch (50) and the last `:prs` pull requests (30). Needs `GITHUB_TOKEN`
  for private repos. Returns `{:ok, recorded}`.
  """
  def backfill(%Project{repo: repo} = project, opts \\ []) when is_binary(repo) do
    token = token(project.org_id)
    auth = if token, do: [{"authorization", "Bearer #{token}"}], else: []
    headers = [{"accept", "application/vnd.github+json"} | auth]

    base = Keyword.get(opts, :base_url, "https://api.github.com")
    req = Keyword.get(opts, :req_options, [])
    repo_payload = %{"full_name" => repo}

    with {:ok, %{status: 200, body: commits}} <-
           Req.get("#{base}/repos/#{repo}/commits", [headers: headers, params: [per_page: opts[:commits] || 50]] ++ req),
         {:ok, %{status: 200, body: prs}} <-
           Req.get(
             "#{base}/repos/#{repo}/pulls",
             [headers: headers, params: [state: "all", per_page: opts[:prs] || 30]] ++ req
           ) do
      pushed =
        commits
        |> Enum.reverse()
        |> Enum.map(fn c ->
          %{
            "id" => c["sha"],
            "message" => get_in(c, ["commit", "message"]),
            "url" => c["html_url"],
            "timestamp" => get_in(c, ["commit", "author", "date"]),
            "author" => %{
              "username" => get_in(c, ["author", "login"]),
              "name" => get_in(c, ["commit", "author", "name"]),
              "email" => get_in(c, ["commit", "author", "email"])
            }
          }
        end)

      n = record("push", %{"ref" => "refs/heads/main", "commits" => pushed, "repository" => repo_payload}, project)

      n =
        prs
        |> Enum.reverse()
        |> Enum.reduce(n, fn pr, n ->
          n + record("pull_request", %{"pull_request" => pr, "repository" => repo_payload}, project)
        end)

      {:ok, n}
    else
      {:ok, %{status: status, body: body}} -> {:error, {:github, status, body["message"]}}
      error -> error
    end
  end
end
