defmodule Noa.Agent.Answer do
  @moduledoc """
  The model's answer (2.5, ported from Tulpa v1's grounded generator): text with `[n]`
  markers and the source numbers it cites. Validation rejects any number that was not
  in the sources, and InstructorLite retries.
  """
  use Ecto.Schema
  use InstructorLite.Instruction

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:answer, :string)
    field(:cited, {:array, :integer}, default: [])
  end

  @instructions """
  You are Noa, the team's project assistant. Answer the question using ONLY the numbered sources.
  - Every factual claim ends with the number of a source that supports it, like [2]. Cite only numbers you were given.
  - Lead with the answer for the person asking. No preamble, no restating the question.
  - One to three short sentences; use short bullets only when the question asks for a list.
  - Name people, tasks and dates plainly. Say "late" for anything past due.
  - Never call a task done, decided or approved unless a source says so.
  - If the sources do not answer the question, say what you could not find in one sentence and cite nothing.
  Return `answer` (the text) and `cited` (the source numbers you used).
  """

  @impl InstructorLite.Instruction
  def json_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["answer", "cited"],
      "properties" => %{
        "answer" => %{"type" => "string"},
        "cited" => %{"type" => "array", "items" => %{"type" => "integer"}}
      }
    }
  end

  @impl InstructorLite.Instruction
  def validate_changeset(changeset, opts) do
    count = opts |> Keyword.fetch!(:extra) |> Map.fetch!(:count)

    changeset
    |> validate_required([:answer])
    |> validate_change(:cited, fn :cited, cited ->
      if Enum.all?(cited, &(&1 in 1..count//1)), do: [], else: [cited: "cites a source that was not given"]
    end)
  end

  @doc "Asks the model. `sources` are numbered from 1 in the order given."
  def answer(question, sources, opts \\ []) do
    numbered = sources |> Enum.with_index(1) |> Enum.map_join("\n", fn {s, i} -> "[#{i}] #{s.text}" end)

    InstructorLite.instruct(
      %{
        model: System.get_env("NOA_MODEL", "gpt-5.6-luna"),
        reasoning: %{effort: System.get_env("NOA_EFFORT", "low")},
        instructions: @instructions <> "\nToday is #{Date.utc_today()}.",
        input: [%{role: "user", content: "Question: #{question}\n\nSources:\n#{numbered}"}]
      },
      response_model: __MODULE__,
      max_retries: 2,
      adapter: Keyword.get(opts, :adapter, InstructorLite.Adapters.OpenAI),
      adapter_context:
        Keyword.get_lazy(opts, :adapter_context, fn -> [api_key: System.fetch_env!("OPENAI_API_KEY")] end),
      extra: %{count: length(sources)}
    )
    |> case do
      {:ok, %__MODULE__{answer: answer, cited: cited}} -> {:ok, %{answer: answer, cited: cited}}
      error -> error
    end
  end
end
