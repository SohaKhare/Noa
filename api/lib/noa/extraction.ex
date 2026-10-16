defmodule Noa.Extraction do
  @moduledoc """
  Chat in, proposals out (1.16, 1.17, 1.21). Contract: docs/extraction.md.

      lines
      |> Noa.Extraction.windows()
      |> Enum.flat_map(fn window ->
        {:ok, proposals} = Noa.Extraction.extract(window, vocabulary)
        proposals
      end)

  In the Phoenix app this runs in an Oban job per channel window, and each proposal
  becomes a `ProposalCreated` event. Nothing here touches a database.
  """

  alias Noa.Extraction.{Line, Model, Result, Routing, Vocabulary, Window}

  defmodule Proposal do
    @moduledoc """
    One extracted item, routed. `type` is the extraction type; `item` is its typed
    struct; `evidence` are the Episode ids it cites; `inbox` says whether it waits for
    a person (always true in Phase 1).
    """
    defstruct [:type, :item, :route, :confidence, evidence: [], inbox: true]

    @type t :: %__MODULE__{
            type: :task | :status_change | :deadline_change | :decision | :scope_change,
            item: struct(),
            route: Noa.Extraction.Routing.t(),
            confidence: float(),
            evidence: [term()],
            inbox: boolean()
          }
  end

  @type_names %{
    tasks: :task,
    status_changes: :status_change,
    deadline_changes: :deadline_change,
    decisions: :decision,
    scope_changes: :scope_change
  }

  # Below this the item is dropped and only logged for the eval set (2.17).
  @drop_below 0.5

  @doc "Groups lines into windows (see `Noa.Extraction.Window`)."
  @spec windows([Line.t()], keyword()) :: [Window.t()]
  defdelegate windows(lines, opts \\ []), to: Window, as: :build

  @doc """
  Runs the model on one window and routes what it finds.

  Options: `:model` (a `Noa.Extraction.Model` module) and anything that model accepts.
  """
  @spec extract(Window.t(), Vocabulary.t(), keyword()) :: {:ok, [Proposal.t()]} | {:error, term()}
  def extract(window, vocab, opts \\ []) do
    {model, opts} = Keyword.pop_lazy(opts, :model, &Model.impl/0)

    with {:ok, %Result{} = result} <- model.extract(window, vocab, opts) do
      {:ok, proposals(result, window, vocab)}
    end
  end

  @doc "Turns a validated result into routed proposals, dropping low-confidence items."
  @spec proposals(Result.t(), Window.t(), Vocabulary.t()) :: [Proposal.t()]
  def proposals(result, window, vocab) do
    by_seq = Map.new(window.context ++ window.lines, &{&1.seq, &1})

    for type <- Result.types(),
        item <- Map.fetch!(result, type),
        item.confidence >= @drop_below do
      evidence = item.evidence_sequences |> Enum.map(&Map.fetch!(by_seq, &1)) |> Enum.sort_by(& &1.seq)

      %Proposal{
        type: @type_names[type],
        item: item,
        route: Routing.route(evidence, item.project, item.confidence, vocab),
        confidence: item.confidence,
        evidence: Enum.map(evidence, & &1.id)
      }
    end
  end
end
