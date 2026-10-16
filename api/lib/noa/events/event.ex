defmodule Noa.Events.Event do
  @moduledoc "One row of the event log. `id` is the log position."
  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: true}
  schema "events" do
    field(:org_id, Ecto.UUID)
    field(:type, :string)
    field(:subject_id, Ecto.UUID)
    field(:data, :map, default: %{})
    field(:actor_id, Ecto.UUID)
    field(:key, :string)
    field(:occurred_at, :utc_datetime_usec)
    field(:inserted_at, :utc_datetime_usec, read_after_writes: true)
  end
end
