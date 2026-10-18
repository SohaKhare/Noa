defmodule Noa.Orgs.Join do
  @moduledoc """
  Joining from a shared link (1.5). A workspace has a public join page, `/join/<slug>`.
  Anyone with an email on one of its allowed domains can ask to join; the org admins are
  told, and one of them approves (with a role) or declines. Approving sends the ordinary
  invite email, so the person still proves they own the address by clicking the link in
  their inbox; asking with someone else's email gets the asker nothing.
  """
  import Ecto.Query

  alias Noa.{Orgs, Repo}
  alias Noa.Orgs.{Org, WorkEmail}

  @fields [:id, :org_id, :email, :name, :note, :status, :role, :decided_at, :inserted_at]

  @doc "What the join page shows: the workspace's name and the email domains it accepts."
  def info(slug) do
    case org(slug) do
      nil -> {:error, :not_found}
      org -> {:ok, %{name: org.name, slug: org.slug, domains: org.allowed_domains}}
    end
  end

  @doc """
  Asks to join. `{:ok, :requested}` (also when a request is already waiting, or the
  person is already a member: the page never says who is in a workspace), or
  `{:error, :not_work_email}` / `{:error, :invalid_join}`.
  """
  def request(slug, params) do
    email = params["email"] |> to_string() |> String.trim() |> String.downcase()
    name = params["name"] |> to_string() |> String.trim() |> String.slice(0, 120)

    with %Org{} = org <- org(slug) || {:error, :not_found},
         true <- (name != "" and WorkEmail.domain(email) != nil) || {:error, :invalid_join},
         true <- WorkEmail.allowed?(org, email) || {:error, :not_work_email} do
      cond do
        member?(org.id, email) ->
          {:ok, :requested}

        Repo.exists?(
          from(j in "join_requests",
            where: j.org_id == type(^org.id, :binary_id) and j.email == ^email and j.status == "pending"
          )
        ) ->
          {:ok, :requested}

        true ->
          Repo.insert_all("join_requests", [
            %{
              id: Ecto.UUID.bingenerate(),
              org_id: Ecto.UUID.dump!(org.id),
              email: email,
              name: name,
              note: params["note"] |> to_string() |> String.trim() |> String.slice(0, 500) |> blank(),
              status: "pending"
            }
          ])

          tell_admins(org, name, email)
          {:ok, :requested}
      end
    end
  end

  @doc "Requests waiting on the org's admins, newest first. Anyone else sees none."
  def pending(org_id, actor) do
    if admin(org_id, actor) != :ok do
      {:ok, []}
    else
      {:ok,
       from(j in "join_requests",
         where: j.org_id == type(^org_id, :binary_id) and j.status == "pending",
         order_by: [desc: j.inserted_at],
         select: map(j, ^@fields)
       )
       |> Repo.all()
       |> Enum.map(&load/1)}
    end
  end

  @doc "Approves with a role: sends the invite email. Returns `{:ok, invite_url}`."
  def approve(org_id, id, role, actor) do
    with :ok <- admin(org_id, actor),
         {:ok, req} <- pending_request(org_id, id),
         {:ok, org} <- Orgs.get_org(org_id, actor),
         {:ok, _invite, url} <- Orgs.invite(org, req.email, role, actor) do
      decide(id, "approved", role, actor)
      {:ok, url}
    end
  end

  def reject(org_id, id, actor) do
    with :ok <- admin(org_id, actor),
         {:ok, _req} <- pending_request(org_id, id) do
      decide(id, "rejected", nil, actor)
      :ok
    end
  end

  defp pending_request(org_id, id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %{} = req <-
           Repo.one(
             from(j in "join_requests",
               where: j.id == type(^uuid, :binary_id) and j.org_id == type(^org_id, :binary_id),
               select: map(j, ^@fields)
             )
           ) do
      req = load(req)
      if req.status == "pending", do: {:ok, req}, else: {:error, :already_decided}
    else
      _ -> {:error, :not_found}
    end
  end

  defp decide(id, status, role, actor) do
    from(j in "join_requests", where: j.id == type(^id, :binary_id))
    |> Repo.update_all(
      set: [
        status: status,
        role: role && to_string(role),
        decided_by_id: Ecto.UUID.dump!(actor.id),
        decided_at: DateTime.utc_now()
      ]
    )
  end

  defp load(row), do: %{row | id: Ecto.UUID.load!(row.id), org_id: Ecto.UUID.load!(row.org_id)}

  defp admin(org_id, actor) do
    if Map.get(actor, :is_superadmin) or Orgs.admin?(actor.id, org_id), do: :ok, else: {:error, %Ash.Error.Forbidden{}}
  end

  defp org(slug) when is_binary(slug) do
    require Ash.Query
    Org |> Ash.Query.filter(slug == ^slug) |> Ash.read_one!(authorize?: false)
  end

  defp org(_), do: nil

  defp member?(org_id, email) do
    require Ash.Query

    Noa.Orgs.Membership
    |> Ash.Query.filter(org_id == ^org_id and user.email == ^email)
    |> Ash.exists?(authorize?: false)
  end

  # Admins hear about it on their channel; the bell in the app shows it too.
  defp tell_admins(org, name, email) do
    require Ash.Query

    Noa.Work.Person
    |> Ash.Query.filter(org_id == ^org.id and membership.role == :org_admin)
    |> Ash.read!(authorize?: false)
    |> Enum.each(&Noa.Notify.deliver(&1, "#{name} (#{email}) asked to join #{org.name} on Noa.", link: "/settings"))
  end

  defp blank(""), do: nil
  defp blank(v), do: v
end
