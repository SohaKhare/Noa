defmodule Noa.Extraction.Types.TaskProposal do
  @moduledoc "New work someone agreed to or was asked to do."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field(:title, :string)
    field(:owner, :string)
    field(:due, :date)
    field(:detail, :string)
    field(:project, :string)
    field(:evidence_sequences, {:array, :integer})
    field(:confidence, :float)
  end
end
