defmodule Noa.Extraction.Routing do
  @moduledoc """
  Picks the project for an extracted item (1.16). The first rule with an answer wins;
  see docs/extraction.md, "Routing".

  | Order | Rule                                              | Confidence |
  | 1     | the channel maps to one project                   | 1.0        |
  | 2     | a reply in a thread whose root was routed         | 0.95       |
  | 3     | the evidence names a project or alias (split only)| 0.9        |
  | 4     | the model picked a project id                     | model's    |
  | 5     | the author works on exactly one project           | 0.7        |
  | 6     | otherwise ask "Which project?"                    | -          |

  A mapped channel is never silently overridden: when the model is at least 0.8 sure
  an item belongs elsewhere, the route keeps the mapped project and carries
  `suggest: other_id` so the Inbox can offer "Move to…".
  """

  alias Noa.Extraction.{Line, Vocabulary}

  defstruct [:project, :confidence, :rule, suggest: nil, candidates: []]

  @type rule :: :channel | :thread | :named | :model | :author | :ask
  @type t :: %__MODULE__{
          project: String.t() | nil,
          confidence: float() | nil,
          rule: rule(),
          suggest: String.t() | nil,
          candidates: [String.t()]
        }

  @suggest_at 0.8

  @doc """
  Routes one item. `evidence` are the window lines the item cites; `model_project` and
  `model_confidence` are what the model returned for it.
  """
  @spec route([Line.t()], String.t() | nil, float() | nil, Vocabulary.t()) :: t()
  def route([first | _] = evidence, model_project, model_confidence, vocab) do
    case Vocabulary.channel_route(vocab, first.channel) do
      mapped when is_binary(mapped) ->
        suggest =
          if model_project && model_project != mapped && (model_confidence || 0) >= @suggest_at, do: model_project

        %__MODULE__{project: mapped, confidence: 1.0, rule: :channel, suggest: suggest}

      _split_or_unmapped ->
        route_split(evidence, model_project, model_confidence, vocab)
    end
  end

  defp route_split(evidence, model_project, model_confidence, vocab) do
    thread = Enum.find_value(evidence, & &1.thread_project)
    named = evidence |> Enum.flat_map(&Vocabulary.projects_named_in(vocab, &1.body)) |> Enum.uniq()

    author_projects =
      evidence |> Enum.flat_map(&Vocabulary.projects_of(vocab, Vocabulary.person(vocab, &1.author))) |> Enum.uniq()

    cond do
      thread -> %__MODULE__{project: thread, confidence: 0.95, rule: :thread}
      match?([_], named) -> %__MODULE__{project: hd(named), confidence: 0.9, rule: :named}
      model_project -> %__MODULE__{project: model_project, confidence: model_confidence, rule: :model}
      match?([_], author_projects) -> %__MODULE__{project: hd(author_projects), confidence: 0.7, rule: :author}
      true -> %__MODULE__{project: nil, rule: :ask, candidates: Enum.uniq(named ++ author_projects)}
    end
  end
end
