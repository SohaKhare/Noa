defmodule Noa.Orgs do
  @moduledoc """
  Workspaces, memberships and invites (1.5, 1.6, 1.22).

  The flow: a superadmin creates the org with its work-email domains and invites the
  first org admin; org admins invite everyone else; an invitee sets a password on the
  invite page and lands in the app. Every function that acts for a person takes the
  `actor` and goes through Ash policies. Only `get_invite/1` and `accept_invite/2` run
  without an actor: holding the emailed token is the permission.
  """
  use Ash.Domain, otp_app: :noa

  require Ash.Query

  alias Noa.Accounts.User
  alias Noa.Orgs.{Invite, Membership, Org, WorkEmail}
  alias Noa.Repo

  @invite_days 7

  resources do
    resource(Org)
    resource(Membership)
    resource(Invite)
  end

  ## Orgs

  @doc "Creates a workspace. Superadmin only (enforced by policy)."
  def create_org(%{name: name} = attrs, actor) do
    Org
    |> Ash.Changeset.for_create(
      :create,
      %{name: name, slug: unique_slug(name), allowed_domains: Map.get(attrs, :allowed_domains, [])},
      actor: actor
    )
    |> Ash.create()
  end

  def list_orgs(actor), do: Org |> Ash.Query.sort(:name) |> Ash.read(actor: actor)

  def get_org(id, actor), do: Ash.get(Org, id, actor: actor)

  @doc "Whether the user is an org admin of the org. Used by policy checks."
  def admin?(user_id, org_id) do
    Membership
    |> Ash.Query.filter(user_id == ^user_id and org_id == ^org_id and role == :org_admin)
    |> Ash.exists?(authorize?: false)
  end

  @doc "A user's memberships with their orgs, for the signed-in payload."
  def memberships_for(%User{id: user_id}) do
    Membership
    |> Ash.Query.filter(user_id == ^user_id)
    |> Ash.Query.load(:org)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!(authorize?: false)
  end

  ## Members

  def members(org_id, actor) do
    Membership
    |> Ash.Query.filter(org_id == ^org_id)
    |> Ash.Query.load([:user, reports_to: :user])
    |> Ash.Query.sort(role: :asc, inserted_at: :asc)
    |> Ash.read(actor: actor)
  end

  @doc "Changes a member's role, title or reports-to. Refuses `:last_admin` when it would leave the org with no admin (1.26)."
  def update_member(membership_id, attrs, actor) do
    with {:ok, membership} <- Ash.get(Membership, membership_id, actor: actor) do
      keeping_an_admin(membership.org_id, fn ->
        membership |> Ash.Changeset.for_update(:update, attrs, actor: actor) |> Ash.update()
      end)
    end
  end

  @doc "Removes a member. Refuses `:last_admin` for the org's only admin."
  def remove_member(membership_id, actor) do
    with {:ok, membership} <- Ash.get(Membership, membership_id, actor: actor) do
      keeping_an_admin(membership.org_id, fn -> Ash.destroy(membership, actor: actor) end)
    end
  end

  ## Invites

  @doc """
  Invites `email` to the org with a role. Returns `{:ok, invite, url}`; the email is sent,
  and the url is returned so it can also be shared by hand.

  Errors: `:not_work_email`, `:already_member`, or a forbidden error when the actor may not invite.
  Inviting someone who already has a pending invite replaces it.
  """
  def invite(%Org{} = org, email, role, actor, opts \\ []) do
    email = email |> to_string() |> String.trim() |> String.downcase()

    cond do
      not WorkEmail.allowed?(org, email) ->
        {:error, :not_work_email}

      member_email?(org.id, email) ->
        {:error, :already_member}

      true ->
        token = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

        Repo.transaction(fn ->
          revoke_pending(org.id, email)

          Invite
          |> Ash.Changeset.for_create(
            :create,
            %{
              email: email,
              role: role,
              title: Keyword.get(opts, :title),
              token_hash: hash(token),
              expires_at: DateTime.add(DateTime.utc_now(), @invite_days, :day),
              org_id: org.id,
              invited_by_id: actor && actor.id
            },
            actor: actor
          )
          |> Ash.create()
          |> case do
            {:ok, invite} -> invite
            {:error, error} -> Repo.rollback(error)
          end
        end)
        |> case do
          {:ok, invite} ->
            url = Noa.Mailer.web_url("/invite/" <> token)
            Noa.Orgs.Senders.Invite.send(invite, org, url, actor)
            {:ok, invite, url}

          {:error, error} ->
            {:error, error}
        end
    end
  end

  def pending_invites(org_id, actor) do
    Invite
    |> Ash.Query.filter(org_id == ^org_id and status == :pending)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read(actor: actor)
  end

  def revoke_invite(invite_id, actor) do
    with {:ok, invite} <- Ash.get(Invite, invite_id, actor: actor) do
      invite |> Ash.Changeset.for_update(:revoke, %{}, actor: actor) |> Ash.update()
    end
  end

  @doc "Looks up a usable invite by its emailed token: `{:ok, invite}` with the org loaded, or `{:error, :invalid | :expired | :used}`."
  def get_invite(token) when is_binary(token) do
    Invite
    |> Ash.Query.filter(token_hash == ^hash(token))
    |> Ash.Query.load(:org)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :invalid}
      {:ok, %{status: :pending} = invite} -> if expired?(invite), do: {:error, :expired}, else: {:ok, invite}
      {:ok, %{status: :accepted}} -> {:error, :used}
      {:ok, _revoked} -> {:error, :invalid}
      {:error, _} -> {:error, :invalid}
    end
  end

  def get_invite(_), do: {:error, :invalid}

  @doc """
  Accepts an invite: creates the account (name and password) and the membership, and
  marks the invite used. Someone who already has an account just gains the membership;
  their password is unchanged. Returns `{:ok, user}`.
  """
  def accept_invite(token, params) do
    with {:ok, invite} <- get_invite(token),
         true <- WorkEmail.allowed?(invite.org, invite.email) || {:error, :not_work_email} do
      Repo.transaction(fn ->
        user = existing_user(invite.email) || create_user!(invite, params)

        Membership
        |> Ash.Changeset.for_create(:create, %{
          role: invite.role,
          title: invite.title,
          org_id: invite.org_id,
          user_id: user.id
        })
        |> Ash.create!(authorize?: false)

        invite
        |> Ash.Changeset.for_update(:accept, %{accepted_by_id: user.id})
        |> Ash.update!(authorize?: false)

        user
      end)
    end
  end

  ## Helpers

  # Runs the write, then rolls it back if the org has no admin left. Writing first keeps
  # the policy check ahead of this rule, so people who can't edit members learn nothing.
  defp keeping_an_admin(org_id, write) do
    Repo.transaction(fn ->
      result =
        case write.() do
          :ok -> {:ok, :ok}
          other -> other
        end

      with {:ok, value} <- result,
           true <-
             Membership |> Ash.Query.filter(org_id == ^org_id and role == :org_admin) |> Ash.exists?(authorize?: false) do
        value
      else
        false -> Repo.rollback(:last_admin)
        {:error, error} -> Repo.rollback(error)
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      other -> other
    end
  end

  defp create_user!(invite, params) do
    User
    |> Ash.Changeset.for_create(:create_with_password, %{
      email: invite.email,
      name: params |> Map.get("name", "") |> String.trim() |> blank_to_nil(),
      password: Map.get(params, "password")
    })
    |> Ash.create(authorize?: false)
    |> case do
      {:ok, user} -> user
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp existing_user(email) do
    User |> Ash.Query.filter(email == ^email) |> Ash.read_one!(authorize?: false)
  end

  defp member_email?(org_id, email) do
    Membership
    |> Ash.Query.filter(org_id == ^org_id and user.email == ^email)
    |> Ash.exists?(authorize?: false)
  end

  defp revoke_pending(org_id, email) do
    Invite
    |> Ash.Query.filter(org_id == ^org_id and email == ^email and status == :pending)
    |> Ash.read!(authorize?: false)
    |> Enum.each(&(&1 |> Ash.Changeset.for_update(:revoke, %{}) |> Ash.update!(authorize?: false)))
  end

  defp expired?(invite), do: DateTime.compare(invite.expires_at, DateTime.utc_now()) != :gt

  defp hash(token), do: :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp unique_slug(name) do
    base = name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")
    base = if base == "", do: "org", else: base

    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(fn
      1 -> base
      n -> "#{base}-#{n}"
    end)
    |> Enum.find(fn slug -> not (Org |> Ash.Query.filter(slug == ^slug) |> Ash.exists?(authorize?: false)) end)
  end
end
