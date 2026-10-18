defmodule Noa.Connectors do
  @moduledoc """
  What each workspace has connected (1.18). The Noa admin runs the platform pieces (the
  Discord bot, the Kapso number); a company's org admin connects their own:

    * **Discord:** they add Noa's bot to their server, then connect the server's id here.
      A server belongs to one workspace; messages and members from it go to that
      workspace only.
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

  def disconnect(org_id, kind, actor) when kind in ["discord", "github", "github_app"] do
    with :ok <- admin(org_id, actor) do
      from(c in "org_connectors", where: c.org_id == type(^org_id, :binary_id) and c.kind == ^kind) |> Repo.delete_all()
      :ok
    end
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
      if e.postgres[:code] == :unique_violation, do: {:error, :guild_taken}, else: reraise(e, __STACKTRACE__)
  end

  defp admin(org_id, actor) do
    if Map.get(actor, :is_superadmin) or Orgs.admin?(actor.id, org_id), do: :ok, else: {:error, %Ash.Error.Forbidden{}}
  end
end
