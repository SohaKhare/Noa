defmodule Noa.Ingest.Discord.Consumer do
  @moduledoc """
  Small adapter between a Discord gateway client and `Noa.Ingest.Discord`.

  Keeping the event shape at this boundary means a gateway library can be added or
  swapped without allowing connector code to bypass the Work/event-log pipeline.
  `MESSAGE_CREATE` is the only event that reads content; DMs and bot messages are
  rejected by the normalizer before they reach the database.
  """

  alias Noa.Ingest.Discord

  @spec handle_event(String.t(), tuple() | map()) :: term()
  def handle_event(org_id, {:message_create, payload}), do: Discord.ingest(org_id, payload)
  def handle_event(org_id, {:MESSAGE_CREATE, payload, _state}), do: Discord.ingest(org_id, payload)

  def handle_event(org_id, %{"t" => "MESSAGE_CREATE", "d" => payload}),
    do: Discord.ingest(org_id, payload)

  def handle_event(_org_id, _event), do: {:ignore, :unsupported_event}
end
