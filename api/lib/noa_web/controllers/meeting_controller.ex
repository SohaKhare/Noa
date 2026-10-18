defmodule NoaWeb.MeetingController do
  use NoaWeb, :controller
  alias Noa.Meetings

  def index(conn, %{"org_id" => org_id}) do
    with {:ok, meetings} <- Meetings.for_org(org_id, conn.assigns.current_user),
         do: json(conn, %{meetings: Enum.map(meetings, &payload(&1, false))})
  end

  def show(conn, %{"org_id" => org_id, "id" => id}) do
    with {:ok, meeting} <- Meetings.fetch(id, conn.assigns.current_user),
         true <- meeting.org_id == org_id do
      json(conn, %{meeting: payload(meeting, true)})
    else
      _ -> {:error, :not_found}
    end
  end

  def create(conn, %{"org_id" => org_id} = params) do
    attrs = %{
      project_id: params["project_id"],
      title: params["title"],
      external_id: params["external_id"],
      consent_confirmed: params["consent_confirmed"],
      source: %{"channel_id" => params["channel_id"], "provider" => "google_meet"}
    }

    with {:ok, meeting} <- Meetings.import_transcript(org_id, attrs, params["utterances"], conn.assigns.current_user),
         do: conn |> put_status(201) |> json(%{meeting: payload(meeting, true)})
  end

  defp payload(meeting, transcript?) do
    data =
      Map.take(meeting, [
        :id,
        :org_id,
        :project_id,
        :title,
        :platform,
        :external_id,
        :status,
        :source,
        :minutes,
        :error_code,
        :inserted_at,
        :updated_at
      ])

    if transcript?, do: Map.put(data, :transcript, meeting.transcript), else: data
  end
end
