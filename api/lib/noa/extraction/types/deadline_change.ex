defmodule Noa.Extraction.Types.DeadlineChange do
  @moduledoc "An existing task's due date moved. Always needs the editor's lead to approve (2.20)."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field(:task_ref, :string)
    field(:new_due, :date)
    field(:reason, :string)
    field(:project, :string)
    field(:evidence_sequences, {:array, :integer})
    field(:confidence, :float)
  end
end
