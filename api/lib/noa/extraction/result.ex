defmodule Noa.Extraction.Result do
  @moduledoc """
  Everything the model found in one window: one list per extraction type (1.21).

  The JSON schema is written by hand, not generated, so nullable fields and enums
  are exact under OpenAI strict mode. `validate_changeset/2` enforces the rules in
  docs/extraction.md ("Validation"); InstructorLite sends the errors back to the
  model and retries.
  """

  use Ecto.Schema
  use InstructorLite.Instruction

  import Ecto.Changeset

  alias Noa.Extraction.{Vocabulary, Window}
  alias Noa.Extraction.Types.{DeadlineChange, Decision, ScopeChange, StatusChange, TaskProposal}

  @primary_key false
  embedded_schema do
    embeds_many(:tasks, TaskProposal)
    embeds_many(:status_changes, StatusChange)
    embeds_many(:deadline_changes, DeadlineChange)
    embeds_many(:decisions, Decision)
    embeds_many(:scope_changes, ScopeChange)
  end

  @type t :: %__MODULE__{
          tasks: [TaskProposal.t()],
          status_changes: [StatusChange.t()],
          deadline_changes: [DeadlineChange.t()],
          decisions: [Decision.t()],
          scope_changes: [ScopeChange.t()]
        }

  @types [:tasks, :status_changes, :deadline_changes, :decisions, :scope_changes]
  @required %{
    tasks: [:title],
    status_changes: [:task_ref, :status],
    deadline_changes: [:task_ref, :new_due],
    decisions: [:statement, :kind],
    scope_changes: [:target_ref, :change, :summary]
  }

  @doc "The extraction types, in the order they are reported."
  def types, do: @types

  @impl InstructorLite.Instruction
  def json_schema do
    nullable = %{"type" => ["string", "null"]}
    date = %{"type" => ["string", "null"], "description" => "ISO date, YYYY-MM-DD"}

    list = fn props ->
      props =
        Map.merge(props, %{
          "project" => %{"type" => ["string", "null"], "description" => "A project id from the Projects list, or null"},
          "evidence_sequences" => %{"type" => "array", "items" => %{"type" => "integer"}},
          "confidence" => %{"type" => "number"}
        })

      %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => props |> Map.keys() |> Enum.sort(),
          "properties" => props
        }
      }
    end

    enum = fn values -> %{"type" => "string", "enum" => values} end

    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => Enum.map(@types, &Atom.to_string/1),
      "properties" => %{
        "tasks" => list.(%{"title" => %{"type" => "string"}, "owner" => nullable, "due" => date, "detail" => nullable}),
        "status_changes" =>
          list.(%{
            "task_ref" => %{"type" => "string"},
            "status" => enum.(["todo", "in_progress", "blocked", "done"]),
            "blocker" => nullable
          }),
        "deadline_changes" =>
          list.(%{
            "task_ref" => %{"type" => "string"},
            "new_due" => %{"type" => "string", "description" => "ISO date"},
            "reason" => nullable
          }),
        "decisions" =>
          list.(%{
            "statement" => %{"type" => "string"},
            "kind" => enum.(["decision", "conclusion"]),
            "affects" => %{"type" => "array", "items" => %{"type" => "string"}},
            "supersedes_ref" => nullable
          }),
        "scope_changes" =>
          list.(%{
            "target_ref" => %{"type" => "string"},
            "change" => enum.(["add", "remove", "change"]),
            "summary" => %{"type" => "string"}
          })
      }
    }
  end

  @doc """
  Checks every item against the window and the vocabulary.

  Expects `opts[:extra]` to be `%{window: Window.t(), vocabulary: Vocabulary.t()}`.
  """
  @impl InstructorLite.Instruction
  def validate_changeset(changeset, opts) do
    %{window: window, vocabulary: vocab} = Keyword.fetch!(opts, :extra)

    ctx = %{
      citable: Window.citable(window),
      own: Window.own(window),
      earliest_due: Date.add(window.date, -1),
      projects: Vocabulary.project_ids(vocab),
      vocab: vocab
    }

    Enum.reduce(@types, changeset, fn type, cs ->
      case get_change(cs, type) do
        nil ->
          cs

        items ->
          checked = Enum.map(items, &check(&1, type, ctx))
          cs = put_change(cs, type, checked)
          %{cs | valid?: cs.valid? and Enum.all?(checked, & &1.valid?)}
      end
    end)
  end

  @doc "Casts a decoded model response and validates it, without calling a model. Used by stubs and replays."
  @spec from_map(map(), map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def from_map(params, extra) do
    %__MODULE__{}
    |> InstructorLite.cast(params)
    |> validate_changeset(extra: extra)
    |> apply_action(:extract)
  end

  defp check(item, type, ctx) do
    item
    |> validate_required(@required[type], message: "must be filled in")
    |> validate_required([:evidence_sequences, :confidence], message: "must be filled in")
    |> validate_number(:confidence, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_change(:evidence_sequences, &evidence(&1, &2, ctx))
    |> validate_change(:project, fn :project, id ->
      if MapSet.member?(ctx.projects, id),
        do: [],
        else: [project: "#{id} is not a project id; use one from the Projects list or null"]
    end)
    |> check_type(type, ctx)
  end

  defp check_type(item, :tasks, ctx) do
    item
    |> validate_change(:owner, fn :owner, name ->
      if Vocabulary.person(ctx.vocab, name),
        do: [],
        else: [owner: "#{name} is not in the People list; use a listed name or null"]
    end)
    |> validate_change(:due, &not_past(&1, &2, ctx))
  end

  defp check_type(item, :status_changes, _ctx) do
    if get_field(item, :status) == :blocked,
      do: validate_required(item, [:blocker], message: "is required when status is blocked"),
      else: item
  end

  defp check_type(item, :deadline_changes, ctx), do: validate_change(item, :new_due, &not_past(&1, &2, ctx))
  defp check_type(item, _type, _ctx), do: item

  defp evidence(:evidence_sequences, [], _ctx), do: [evidence_sequences: "must cite at least one message"]

  defp evidence(:evidence_sequences, seqs, ctx) do
    cond do
      not Enum.all?(seqs, &MapSet.member?(ctx.citable, &1)) ->
        [evidence_sequences: "cites a message that is not in the transcript"]

      not Enum.any?(seqs, &MapSet.member?(ctx.own, &1)) ->
        [evidence_sequences: "must cite at least one message after the Earlier context"]

      true ->
        []
    end
  end

  defp not_past(field, date, ctx) do
    if Date.compare(date, ctx.earliest_due) == :lt,
      do: [{field, "#{date} is in the past; resolve relative dates against the window date"}],
      else: []
  end
end
