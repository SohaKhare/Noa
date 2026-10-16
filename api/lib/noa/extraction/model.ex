defmodule Noa.Extraction.Model do
  @moduledoc """
  The model seam. `Noa.Extraction.Model.OpenAI` calls OpenAI through InstructorLite;
  `Noa.Extraction.Model.Stub` returns canned output for tests. Pick one with
  `config :noa, Noa.Extraction, model: ...`.
  """

  alias Noa.Extraction.{Result, Vocabulary, Window}

  @callback extract(Window.t(), Vocabulary.t(), keyword()) :: {:ok, Result.t()} | {:error, term()}

  @doc "The configured model module."
  def impl, do: Application.get_env(:noa, Noa.Extraction, [])[:model] || Noa.Extraction.Model.OpenAI
end

defmodule Noa.Extraction.Model.OpenAI do
  @moduledoc """
  One strict-schema call per window (OpenAI Responses API via InstructorLite), with up
  to two retries when validation fails. Reads `OPENAI_API_KEY`; `NOA_MODEL` and
  `NOA_EFFORT` override the model (default `gpt-5.6-luna` at low effort, as in Tulpa v1).
  """

  @behaviour Noa.Extraction.Model

  alias Noa.Extraction.{Prompt, Result}

  @impl true
  def extract(window, vocab, opts \\ []) do
    InstructorLite.instruct(
      request(window, vocab),
      response_model: Result,
      max_retries: Keyword.get(opts, :max_retries, 2),
      adapter: Keyword.get(opts, :adapter, InstructorLite.Adapters.OpenAI),
      adapter_context:
        Keyword.get_lazy(opts, :adapter_context, fn -> [api_key: System.fetch_env!("OPENAI_API_KEY")] end),
      extra: %{window: window, vocabulary: vocab}
    )
  end

  @doc "The request body sent for a window. Useful for dry runs."
  def request(window, vocab) do
    %{
      model: System.get_env("NOA_MODEL", "gpt-5.6-luna"),
      reasoning: %{effort: System.get_env("NOA_EFFORT", "low")},
      instructions: Prompt.instructions(window, vocab),
      input: [%{role: "user", content: Prompt.transcript(window)}]
    }
  end
end

defmodule Noa.Extraction.Model.Stub do
  @moduledoc """
  Returns canned model output so tests never call a model. Pass the decoded response
  as `opts[:response]`, or a function of the window as `opts[:respond]` or as
  `config :noa, Noa.Extraction, respond: fun`.
  """

  @behaviour Noa.Extraction.Model

  alias Noa.Extraction.Result

  @impl true
  def extract(window, vocab, opts) do
    raw =
      case Keyword.fetch(opts, :respond) do
        {:ok, fun} -> fun.(window)
        :error -> Keyword.get_lazy(opts, :response, fn -> configured(window) end)
      end

    Result.from_map(raw, %{window: window, vocabulary: vocab})
  end

  # Tests of the extraction job set `config :noa, Noa.Extraction, respond: fun`.
  defp configured(window) do
    case Application.get_env(:noa, Noa.Extraction, [])[:respond] do
      nil -> %{}
      fun -> fun.(window)
    end
  end
end
