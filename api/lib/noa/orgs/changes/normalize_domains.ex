defmodule Noa.Orgs.Changes.NormalizeDomains do
  @moduledoc "Lowercases allowed domains and strips a leading @ or whitespace."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.fetch_change(changeset, :allowed_domains) do
      {:ok, domains} when is_list(domains) ->
        clean =
          domains
          |> Enum.map(&(&1 |> String.trim() |> String.trim_leading("@") |> String.downcase()))
          |> Enum.reject(&(&1 == ""))
          |> Enum.uniq()

        Ash.Changeset.force_change_attribute(changeset, :allowed_domains, clean)

      _ ->
        changeset
    end
  end
end
