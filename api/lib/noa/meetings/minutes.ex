defmodule Noa.Meetings.Note do
  @moduledoc false
  use Ecto.Schema
  @primary_key false
  embedded_schema do
    field(:text, :string)
    field(:evidence_sequences, {:array, :integer})
  end
end

defmodule Noa.Meetings.Minutes do
  @moduledoc "Strict, cited minutes. Existing task/decision types remain unchanged. Small talk is represented by no items, not invented work."
  use Ecto.Schema
  use InstructorLite.Instruction
  import Ecto.Changeset
  alias Noa.Extraction.{Result, Window}

  @primary_key false
  embedded_schema do
    embeds_many(:discussion, Noa.Meetings.Note)
    embeds_many(:blockers, Noa.Meetings.Note)
    embeds_many(:open_questions, Noa.Meetings.Note)
    embeds_many(:tasks, Noa.Extraction.Types.TaskProposal)
    embeds_many(:decisions, Noa.Extraction.Types.Decision)
  end

  @notes [:discussion, :blockers, :open_questions]
  @fields @notes ++ [:tasks, :decisions]

  @impl true
  def json_schema do
    note = %{
      "type" => "array",
      "items" => %{
        "type" => "object",
        "additionalProperties" => false,
        "required" => ["text", "evidence_sequences"],
        "properties" => %{
          "text" => %{"type" => "string"},
          "evidence_sequences" => %{"type" => "array", "items" => %{"type" => "integer"}}
        }
      }
    }

    props =
      Map.new(@notes, &{to_string(&1), note})
      |> Map.merge(Map.take(Result.json_schema()["properties"], ["tasks", "decisions"]))

    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => Enum.map(@fields, &to_string/1),
      "properties" => props
    }
  end

  @impl true
  def validate_changeset(cs, opts) do
    extra = Keyword.fetch!(opts, :extra)
    allowed = Window.citable(extra.window)

    cs =
      Enum.reduce(@notes, cs, fn field, cs ->
        checked =
          Enum.map(get_change(cs, field, []), fn note ->
            note
            |> validate_required([:text, :evidence_sequences])
            |> validate_length(:text, max: 1000)
            |> validate_change(:evidence_sequences, fn key, seqs ->
              if seqs != [] and Enum.all?(seqs, &MapSet.member?(allowed, &1)),
                do: [],
                else: [{key, "must cite actual transcript utterances"}]
            end)
          end)

        put_change(cs, field, checked)
      end)

    if cs.valid? do
      facts = Map.new([:tasks, :decisions], &{to_string(&1), get_field(cs, &1) |> Noa.Events.json()})

      case Result.from_map(facts, extra) do
        {:ok, _} ->
          cs

        {:error, _} ->
          add_error(cs, :tasks, "tasks and decisions must have valid evidence, dates and project references")
      end
    else
      cs
    end
  end

  def from_map(raw, extra) do
    %__MODULE__{} |> InstructorLite.cast(raw) |> validate_changeset(extra: extra) |> apply_action(:minutes)
  end
end
