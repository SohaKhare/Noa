defmodule NoaWeb.FallbackController do
  @moduledoc "Turns `{:error, reason}` from controllers into JSON errors the web app can show."
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn

  @messages %{
    not_work_email: {422, "Use a work email on one of this workspace's domains."},
    already_member: {409, "That person is already in this workspace."},
    last_admin: {409, "This is the workspace's only admin. Make someone else an admin first."},
    invalid: {404, "This invite link isn't valid. Ask your admin for a new one."},
    expired: {410, "This invite has expired. Ask your admin to send a new one."},
    used: {410, "This invite was already used. Sign in instead."},
    needs_project: {422, "Pick a project before approving this."},
    already_decided: {409, "Someone already approved or dismissed this."},
    not_a_lead: {403, "Only workspace admins and PMs can move people."},
    same_project: {422, "They're already on that project."},
    changed_since: {409, "This was changed again since. Change it back by hand."},
    not_a_project_lead: {403, "Only workspace admins, PMs and project leads can run triage."},
    invalid_org_map: {422, "Send the org map as JSON under \"seed\" (the shape of docs/seeds/nyi.json)."},
    invalid_join: {422, "Give your name and your work email."},
    invalid_guild:
      {422,
       "That isn't a Discord server id. In Discord, turn on Developer Mode, right-click the server and Copy Server ID."},
    guild_taken: {409, "That Discord server is already connected to another workspace."},
    invalid_token: {422, "Paste a GitHub token."},
    not_found: {404, "Not found."}
  }

  def call(conn, {:error, reason}) when is_atom(reason) and is_map_key(@messages, reason) do
    {status, message} = @messages[reason]
    error(conn, status, reason, message)
  end

  def call(conn, {:error, %Ash.Error.Forbidden{}}), do: error(conn, 403, :forbidden, "You don't have access to that.")

  def call(conn, {:error, %Ash.Error.Invalid{errors: errors} = invalid}) do
    if Enum.any?(errors, &match?(%Ash.Error.Query.NotFound{}, &1)) do
      call(conn, {:error, :not_found})
    else
      fields =
        for e <- errors, field = Map.get(e, :field) || List.first(Map.get(e, :fields) || []), field != nil, into: %{} do
          {field, Exception.message(e) |> String.replace(~r/^.*?: /, "")}
        end

      conn
      |> put_status(422)
      |> json(%{error: "invalid", message: first_message(invalid, fields), fields: fields})
    end
  end

  def call(conn, {:error, other}) do
    require Logger
    Logger.error("Unhandled API error: #{inspect(other)}")
    error(conn, 500, :server_error, "Something went wrong.")
  end

  defp first_message(_invalid, fields) when map_size(fields) > 0 do
    {field, msg} = Enum.at(fields, 0)
    "#{Phoenix.Naming.humanize(field)} #{msg}"
  end

  defp first_message(invalid, _), do: Exception.message(invalid)

  defp error(conn, status, code, message), do: conn |> put_status(status) |> json(%{error: code, message: message})
end
