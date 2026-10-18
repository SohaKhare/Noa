defmodule Noa.Meet.Provider do
  @moduledoc """
  The replaceable boundary for a visible meeting participant.

  Provider IDs and transport payloads stay outside Noa's work/event-log layer.
  The caller must authorize the organizer and obtain consent before calling join/2.
  """

  @callback join(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  @callback leave(String.t(), keyword()) :: :ok | {:error, term()}
  @callback status(String.t(), keyword()) :: {:ok, %{state: String.t(), transcription: String.t()}} | {:error, term()}
  @callback transcript(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
end
