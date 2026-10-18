defmodule Noa.Meetings.Utterance do
  @moduledoc "Shared transcript contract for the Discord receiver and Soha's Google Meet bot."
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key false
  embedded_schema do
    field(:seq, :integer)
    field(:speaker, :string)
    field(:text, :string)
    field(:start_ms, :integer)
    field(:end_ms, :integer)
  end

  def cast(raw) when is_map(raw) do
    %__MODULE__{}
    |> cast(raw, [:seq, :speaker, :text, :start_ms, :end_ms])
    |> validate_required([:seq, :speaker, :text, :start_ms, :end_ms])
    |> validate_number(:seq, greater_than: 0, less_than_or_equal_to: 1000)
    |> validate_number(:start_ms, greater_than_or_equal_to: 0, less_than_or_equal_to: 3_600_000)
    |> validate_number(:end_ms, greater_than_or_equal_to: 0, less_than_or_equal_to: 3_600_000)
    |> validate_length(:speaker, min: 1, max: 100)
    |> validate_length(:text, min: 1, max: 2000)
    |> then(fn cs ->
      if is_integer(get_field(cs, :start_ms)) and is_integer(get_field(cs, :end_ms)) and
           get_field(cs, :end_ms) < get_field(cs, :start_ms),
         do: add_error(cs, :end_ms, "must not precede start_ms"),
         else: cs
    end)
    |> apply_action(:transcript)
    |> case do
      {:ok, item} -> {:ok, Noa.Events.json(item)}
      _ -> {:error, :invalid_transcript}
    end
  end

  def cast(_), do: {:error, :invalid_transcript}
end
