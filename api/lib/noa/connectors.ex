defmodule Noa.Connectors do
  @moduledoc """
  What each workspace has connected (1.18). The Noa admin runs the platform pieces (the
  Discord bot, Slack app, and the Kapso number); a company's org admin connects their own:

    * **Discord:** they add Noa's bot to their server, then connect the server's id here.
      A server belongs to one workspace; messages and members from it go to that
      workspace only.
    * **Slack:** they install Noa through OAuth. Each workspace receives its own bot
      token, encrypted at rest, and a Slack workspace belongs to one Noa workspace.
    * **GitHub:** they install Noa's GitHub App on their organization (one click; Noa
      gets webhooks and short-lived tokens for the repos they pick), or, without the app,
      generate a webhook secret here and add the webhook by hand, with an optional token
      (encrypted) for private history. Each delivery is checked against its installation
      or the secret of the workspace that owns the repo.

  Org admins only; reads of a workspace's own status are open to its members.
  """
  import Ecto.Query

  alias Noa.{Orgs, Repo, Vault}

  @doc "One workspace's connector rows by kind: `%{\"discord\" => row, \"github\" => row}`."
  def all(org_id) do
    from(c in "org_connectors",
      where: c.org_id == type(^org_id, :binary_id),
      select: %{
        kind: c.kind,
        external_id: c.external_id,
        secret_enc: c.secret_enc,
        token_enc: c.token_enc,
        updated_at: c.updated_at
      }
    )
    |> Repo.all()
    |> Map.new(&{&1.kind, &1})
  end

  ## Discord

  @doc "The link that adds Noa's bot to a server (view channels, read history, send messages)."
  def discord_invite_url do
    case System.get_env("DISCORD_CLIENT_ID") do
      id when is_binary(id) and id != "" ->
        "https://discord.com/oauth2/authorize?client_id=#{id}&scope=bot%20applications.commands&permissions=1117184"

      _ ->
        nil
    end
  end

  def connect_discord(org_id, guild_id, actor) do
    guild_id = guild_id |> to_string() |> String.trim()

    with :ok <- admin(org_id, actor),
         true <- Regex.match?(~r/^\d{15,22}$/, guild_id) || {:error, :invalid_guild},
         :ok <- guild_free(guild_id, org_id) do
      upsert(org_id, "discord", %{external_id: guild_id}, actor)
    end
  end

  @doc "The workspace a Discord server is connected to, or nil."
  def org_for_guild(guild_id) when is_binary(guild_id) or is_integer(guild_id) do
    Repo.one(
      from(c in "org_connectors",
        where: c.kind == "discord" and c.external_id == ^to_string(guild_id),
        select: c.org_id
      )
    )
    |> then(&(&1 && Ecto.UUID.load!(&1)))
  end

  def org_for_guild(_), do: nil

  @doc "The Discord server a workspace is connected to, or nil."
  def guild_for(org_id), do: get_in(all(org_id), ["discord", :external_id])

  defp guild_free(guild_id, org_id) do
    case org_for_guild(guild_id) do
      nil -> :ok
      ^org_id -> :ok
      _other -> {:error, :guild_taken}
    end
  end

  ## Slack

  @slack_scopes ~w(channels:read channels:history groups:read groups:history users:read chat:write im:write)

  @doc "Slack OAuth v2 install link for this workspace, signed for the current org admin."
  def slack_install_url(org_id, actor) do
    with :ok <- admin(org_id, actor), true <- Noa.Ingest.Slack.Client.oauth_configured?() do
      state = Phoenix.Token.sign(NoaWeb.Endpoint, "slack-install", %{org: org_id, user: actor.id})

      query =
        URI.encode_query(%{
          client_id: Application.get_env(:noa, Noa.Ingest.Slack.Client, [])[:client_id],
          scope: Enum.join(@slack_scopes, ","),
          state: state,
          redirect_uri: Application.fetch_env!(:noa, :api_base_url) <> "/slack/oauth/callback"
        })

      "https://slack.com/oauth/v2/authorize?" <> query
    else
      _ -> nil
    end
  end

  @doc "Exchanges Slack's OAuth code and binds the returned workspace to the signed Noa workspace."
  def complete_slack_install(state, code) do
    with {:ok, %{org: org_id, user: user_id}} <-
           Phoenix.Token.verify(NoaWeb.Endpoint, "slack-install", state, max_age: 3600),
         true <- Orgs.admin?(user_id, org_id) || {:error, :not_admin},
         true <- (is_binary(code) and String.trim(code) != "") || {:error, :install_invalid},
         {:ok, response} <- Noa.Ingest.Slack.Client.oauth_exchange(code),
         team_id when is_binary(team_id) <- get_in(response, ["team", "id"]),
         token when is_binary(token) <- response["access_token"],
         :ok <- slack_team_free(team_id, org_id),
         :ok <- upsert(org_id, "slack", %{external_id: team_id, token_enc: Vault.encrypt(token)}, %{id: user_id}) do
      %{org_id: org_id} |> Noa.Ingest.Slack.SyncUsers.new() |> Oban.insert()
      {:ok, org_id}
    else
      {:error, :expired} -> {:error, :install_expired}
      {:error, :invalid} -> {:error, :install_invalid}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :install_invalid}
    end
  end

  @doc "The Noa workspace that installed this Slack workspace, or nil."
  def org_for_slack_team(team_id) when is_binary(team_id) do
    Repo.one(
      from(c in "org_connectors",
        where: c.kind == "slack" and c.external_id == ^team_id,
        select: c.org_id
      )
    )
    |> then(&(&1 && Ecto.UUID.load!(&1)))
  end

  def org_for_slack_team(_), do: nil

  def slack_team_for(org_id), do: get_in(all(org_id), ["slack", :external_id])
  def slack_token(org_id), do: org_id |> all() |> get_in(["slack", :token_enc]) |> Vault.decrypt()

  @doc "Slack removed the app: discard the workspace token immediately."
  def remove_slack_installation(team_id) do
    from(c in "org_connectors", where: c.kind == "slack" and c.external_id == ^to_string(team_id))
    |> Repo.delete_all()

    :ok
  end

  defp slack_team_free(team_id, org_id) do
    case org_for_slack_team(team_id) do
      nil -> :ok
      ^org_id -> :ok
      _other -> {:error, :slack_workspace_taken}
    end
  end

  ## GitHub

  @doc "Makes a new webhook secret for the workspace and returns it (it is shown once)."
  def rotate_github_secret(org_id, actor) do
    secret = 24 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

    with :ok <- admin(org_id, actor),
         :ok <- upsert(org_id, "github", %{secret_enc: Vault.encrypt(secret)}, actor) do
      {:ok, secret}
    end
  end

  def set_github_token(org_id, token, actor) do
    token = token |> to_string() |> String.trim()

    with :ok <- admin(org_id, actor),
         true <- token != "" || {:error, :invalid_token} do
      upsert(org_id, "github", %{token_enc: Vault.encrypt(token)}, actor)
    end
  end

  def github_secret(org_id), do: org_id |> all() |> get_in(["github", :secret_enc]) |> Vault.decrypt()
  def github_token(org_id), do: org_id |> all() |> get_in(["github", :token_enc]) |> Vault.decrypt()

  ## GitHub App (one click for org admins)

  @doc "The GitHub App install link for this workspace, or nil when the app isn't set up. Org admins."
  def github_install_url(org_id, actor) do
    with :ok <- admin(org_id, actor), true <- Noa.GitHub.App.configured?() do
      Noa.GitHub.App.install_url(Phoenix.Token.sign(NoaWeb.Endpoint, "github-install", %{org: org_id, user: actor.id}))
    else
      _ -> nil
    end
  end

  @doc """
  GitHub sends the org admin back with the installation id and our state: ties the
  installation to their workspace. `{:ok, org_id}`, or `{:error, reason}`.
  """
  def complete_github_install(state, installation_id) do
    with {:ok, %{org: org_id, user: user_id}} <-
           Phoenix.Token.verify(NoaWeb.Endpoint, "github-install", state, max_age: 3600),
         true <- Orgs.admin?(user_id, org_id) || {:error, :not_admin},
         id when id != "" <- to_string(installation_id),
         :ok <- installation_free(id, org_id) do
      :ok = upsert(org_id, "github_app", %{external_id: id}, %{id: user_id})
      {:ok, org_id}
    else
      {:error, :expired} -> {:error, :install_expired}
      {:error, :invalid} -> {:error, :install_invalid}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :install_invalid}
    end
  end

  @doc "The workspace a GitHub App installation belongs to, or nil."
  def org_for_installation(installation_id) do
    Repo.one(
      from(c in "org_connectors",
        where: c.kind == "github_app" and c.external_id == ^to_string(installation_id),
        select: c.org_id
      )
    )
    |> then(&(&1 && Ecto.UUID.load!(&1)))
  end

  def installation_for(org_id), do: get_in(all(org_id), ["github_app", :external_id])

  @doc "GitHub uninstalled the app: forget it."
  def remove_installation(installation_id) do
    from(c in "org_connectors", where: c.kind == "github_app" and c.external_id == ^to_string(installation_id))
    |> Repo.delete_all()

    :ok
  end

  defp installation_free(id, org_id) do
    case org_for_installation(id) do
      nil -> :ok
      ^org_id -> :ok
      _ -> {:error, :installation_taken}
    end
  end

  ## Either

  def disconnect(org_id, "slack", actor) do
    with :ok <- admin(org_id, actor),
         :ok <- revoke_slack(org_id) do
      delete(org_id, "slack")
    end
  end

  def disconnect(org_id, kind, actor) when kind in ["discord", "github", "github_app"] do
    with :ok <- admin(org_id, actor) do
      delete(org_id, kind)
    end
  end

  defp revoke_slack(org_id) do
    case slack_token(org_id) do
      nil ->
        :ok

      token ->
        case Noa.Ingest.Slack.Client.revoke(token) do
          {:ok, _} -> :ok
          {:error, {:slack_api, reason, _}} when reason in ["invalid_auth", "token_revoked"] -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp delete(org_id, kind) do
    from(c in "org_connectors", where: c.org_id == type(^org_id, :binary_id) and c.kind == ^kind) |> Repo.delete_all()
    :ok
  end

  defp upsert(org_id, kind, fields, actor) do
    now = DateTime.utc_now()

    Repo.insert_all(
      "org_connectors",
      [
        Map.merge(
          %{
            id: Ecto.UUID.bingenerate(),
            org_id: Ecto.UUID.dump!(org_id),
            kind: kind,
            connected_by_id: Ecto.UUID.dump!(actor.id),
            inserted_at: now,
            updated_at: now
          },
          fields
        )
      ],
      on_conflict: {:replace, Map.keys(fields) ++ [:connected_by_id, :updated_at]},
      conflict_target: [:org_id, :kind]
    )

    :ok
  rescue
    e in Postgrex.Error ->
      if e.postgres[:code] == :unique_violation do
        case kind do
          "discord" -> {:error, :guild_taken}
          "slack" -> {:error, :slack_workspace_taken}
          _ -> {:error, :connector_taken}
        end
      else
        reraise(e, __STACKTRACE__)
      end
  end

  defp admin(org_id, actor) do
    if Map.get(actor, :is_superadmin) or Orgs.admin?(actor.id, org_id), do: :ok, else: {:error, %Ash.Error.Forbidden{}}
  end
end
