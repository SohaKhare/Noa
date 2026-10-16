defmodule Noa.Extraction.Types.StatusChange do
  @moduledoc "An existing task moved to another status. `blocker` says what a blocked task waits on."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field(:task_ref, :string)
    field(:status, Ecto.Enum, values: [:todo, :in_progress, :blocked, :done])
    field(:blocker, :string)
    field(:project, :string)
    field(:evidence_sequences, {:array, :integer})
    field(:confidence, :float)
  end
end
