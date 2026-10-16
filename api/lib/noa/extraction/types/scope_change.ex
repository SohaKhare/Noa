defmodule Noa.Extraction.Types.ScopeChange do
  @moduledoc "Work added to, removed from or changed in a task or project. Always needs the lead to approve (2.20)."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field(:target_ref, :string)
    field(:change, Ecto.Enum, values: [:add, :remove, :change])
    field(:summary, :string)
    field(:project, :string)
    field(:evidence_sequences, {:array, :integer})
    field(:confidence, :float)
  end
end
