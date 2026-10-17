defmodule Noa.MCP.Tokens do
  @moduledoc """
  Personal MCP tokens (3.22). A token belongs to one person in one workspace and acts
  exactly as they would in the web app. It is shown once when created; only its
  SHA-256 hash is stored. Revoking, or the person leaving the workspace, stops it.
  """
  import Ecto.Query

  alias Noa.Repo

  @prefix "noa_"

  @doc "Creates a token. Returns `{:ok, plain_token, row}`; the plain token is never stored."
  def create(org_id, %{id: user_id}, name) do
    plain = @prefix <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    id = Ecto.UUID.generate()

    row = %{
      id: Ecto.UUID.dump!(id),
      org_id: Ecto.UUID.dump!(org_id),
      user_id: Ecto.UUID.dump!(user_id),
      name: String.slice(name || "My agent", 0, 80),
      token_hash: hash(plain),
      inserted_at: DateTime.utc_now()
    }

    {1, _} = Repo.insert_all("mcp_tokens", [row])
    {:ok, plain, %{id: id, name: row.name, inserted_at: row.inserted_at, last_used_at: nil}}
  end

  @doc "The person's live tokens in the workspace (never the token itself)."
  def list(org_id, %{id: user_id}) do
    from(t in "mcp_tokens",
      where: t.org_id == type(^org_id, :binary_id) and t.user_id == type(^user_id, :binary_id) and is_nil(t.revoked_at),
      order_by: [desc: t.inserted_at],
      select: %{
        id: type(t.id, :binary_id),
        name: t.name,
        inserted_at: type(t.inserted_at, :utc_datetime_usec),
        last_used_at: type(t.last_used_at, :utc_datetime_usec)
      }
    )
    |> Repo.all()
  end

  @doc "Revokes one of the person's own tokens."
  def revoke(org_id, %{id: user_id}, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        from(t in "mcp_tokens",
          where:
            t.id == type(^id, :binary_id) and t.org_id == type(^org_id, :binary_id) and
              t.user_id == type(^user_id, :binary_id) and is_nil(t.revoked_at)
        )
        |> Repo.update_all(set: [revoked_at: DateTime.utc_now()])
        |> case do
          {1, _} -> :ok
          _ -> {:error, :not_found}
        end

      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  The person and workspace behind a bearer token: `{:ok, user, org_id}`, or
  `{:error, :unauthorized}` when it is unknown, revoked, or they left the workspace.
  """
  def authenticate(@prefix <> _ = plain) do
    row =
      from(t in "mcp_tokens",
        where: t.token_hash == ^hash(plain) and is_nil(t.revoked_at),
        select: %{id: t.id, org_id: type(t.org_id, :binary_id), user_id: type(t.user_id, :binary_id)}
      )
      |> Repo.one()

    with %{} <- row,
         {:ok, user} <- Ash.get(Noa.Accounts.User, row.user_id, authorize?: false),
         role when not is_nil(role) <- Noa.Orgs.role(user.id, row.org_id) do
      from(t in "mcp_tokens", where: t.id == ^row.id) |> Repo.update_all(set: [last_used_at: DateTime.utc_now()])
      {:ok, user, row.org_id}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def authenticate(_), do: {:error, :unauthorized}

  defp hash(plain), do: :crypto.hash(:sha256, plain)
end
