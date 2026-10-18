defmodule Noa.Meetings.Transcriber do
  @moduledoc "Temporary WAV → ASR text only. Audio never enters the database, event log or logs."
  use Ecto.Schema
  import Ecto.Changeset
  @primary_key false
  embedded_schema do
    field(:text, :string)
  end

  def transcribe(<<"RIFF", _size::binary-size(4), "WAVE", _::binary>> = wav) when byte_size(wav) <= 1_000_000 do
    if Noa.LLM.configured?() do
      config = Application.get_env(:noa, __MODULE__, [])

      case Req.post(
             config[:url] || "https://api.openai.com/v1/audio/transcriptions",
             [
               auth: {:bearer, System.fetch_env!("OPENAI_API_KEY")},
               form_multipart: [
                 model: config[:model] || "gpt-4o-mini-transcribe",
                 response_format: "json",
                 file: {wav, filename: "segment.wav", content_type: "audio/wav"}
               ],
               retry: false,
               receive_timeout: 60_000
             ] ++ (config[:req_options] || [])
           ) do
        {:ok, %{status: 200, body: body}} -> decode(body)
        _ -> {:error, :transcription_failed}
      end
    else
      {:error, :llm_not_configured}
    end
  end

  def transcribe(_), do: {:error, :invalid_audio}

  def decode(%{"text" => raw} = body) when is_binary(raw) do
    %__MODULE__{}
    |> cast(body, [:text])
    |> validate_length(:text, max: 2000)
    |> apply_action(:transcribe)
    |> case do
      {:ok, %{text: text}} -> {:ok, String.trim(text || "")}
      _ -> {:error, :invalid_transcription}
    end
  end

  def decode(_), do: {:error, :invalid_transcription}
end
