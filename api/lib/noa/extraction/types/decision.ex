defmodule Noa.Extraction.Types.Decision do
  @moduledoc "A choice the team made, or a conclusion it reached."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field(:statement, :string)
    field(:kind, Ecto.Enum, values: [:decision, :conclusion])
    field(:affects, {:array, :string}, default: [])
    field(:supersedes_ref, :string)
    field(:project, :string)
    field(:evidence_sequences, {:array, :integer})
    field(:confidence, :float)
  end
end
