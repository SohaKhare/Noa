defmodule NoaWeb.MeetController do
  @moduledoc "Attendee bot lifecycle; imported transcript minutes use the established MeetingController workflow."
  use NoaWeb, :controller
  alias Noa.Meet

  def index(conn, %{"org_id" => org_id}) do
    actor = conn.assigns.current_user

    with {:ok, sessions} <- Meet.sessions(org_id, actor),
         {:ok, projects} <- Noa.Work.projects(org_id, actor),
         {:ok, channels} <- Noa.Work.channels(org_id, actor) do
      json(conn, %{meetings: Enum.map(sessions, &payload(&1, projects, channels))})
    end
  end

  def create(conn, %{"org_id" => org_id} = params) do
    with {:ok, session} <- Meet.start(org_id, params["meeting_url"], params["consent"], conn.assigns.current_user) do
      conn |> put_status(201) |> json(%{meeting: payload(session, [], [])})
    end
  end

  def stop(conn, %{"org_id" => org_id, "id" => id}) do
    with {:ok, session} <- Meet.stop(org_id, id, conn.assigns.current_user) do
      json(conn, %{meeting: payload(session, [], [])})
    end
  end

  def sync(conn, %{"org_id" => org_id, "id" => id}) do
    with {:ok, session} <- Meet.sync(org_id, id, conn.assigns.current_user) do
      json(conn, %{meeting: payload(session, [], [])})
    end
  end

  def import(conn, %{"org_id" => org_id, "id" => id} = params) do
    with {:ok, session, meeting} <-
           Meet.import(
             org_id,
             id,
             params["project_id"],
             params["channel_id"],
             params["title"],
             conn.assigns.current_user
           ) do
      conn
      |> put_status(201)
      |> json(%{meeting: payload(session, [], []), imported_meeting_id: meeting.id, pipeline_status: meeting.status})
    end
  end

  defp payload(s, projects, channels) do
    lines = s.transcript["lines"] || []
    text = Enum.map_join(lines, " ", & &1["text"]) |> String.downcase()

    suggested =
      projects
      |> Enum.map(fn p ->
        labels = [p.name | Enum.map(p.aliases, &to_string(&1.alias))]
        {p.id, Enum.count(labels, &(String.length(&1) >= 3 and String.contains?(text, String.downcase(&1))))}
      end)
      |> Enum.sort_by(fn {_, n} -> -n end)
      |> case do
        [{id, n}, {_, next} | _] when n > next and n > 0 -> id
        [{id, n}] when n > 0 -> id
        _ -> nil
      end

    %{
      id: s.id,
      status: s.status,
      meeting_url: s.meeting_url,
      consent_at: s.consent_at,
      transcript: lines,
      suggested_project_id: suggested,
      imported_meeting_id: s.imported_meeting_id,
      channels: Enum.map(channels, &%{id: &1.id, name: &1.name, project_id: &1.project_id, read: &1.read})
    }
  end
end
