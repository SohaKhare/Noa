defmodule Noa.Orgs.WorkEmail do
  @moduledoc "Work-email rule: an invite's email must be on one of the org's allowed domains."

  @doc "The lowercased domain of an email, or nil if it is not an email."
  def domain(email) do
    case email |> to_string() |> String.trim() |> String.downcase() |> String.split("@") do
      [local, domain] when local != "" and domain != "" -> domain
      _ -> nil
    end
  end

  @doc "Whether `email` may join `org`."
  def allowed?(%{allowed_domains: domains}, email) do
    case domain(email) do
      nil -> false
      d -> d in domains
    end
  end
end
