defmodule Noa.Extraction.Vocabulary do
  @moduledoc """
  What the model may answer with, per org: projects (with aliases), people (with
  handles), channel mappings and open tasks. Built from the graph in production;
  from `docs/seeds/nyi.json` in development and tests.
  """

  defstruct projects: [], people: [], channels: %{}, works_on: %{}, open_tasks: []

  @type project :: %{id: String.t(), name: String.t(), about: String.t() | nil, aliases: [String.t()]}
  @type person :: %{id: String.t(), name: String.t(), title: String.t() | nil, handles: [String.t()]}
  @type channel_route :: String.t() | :split | nil
  @type task :: %{id: String.t(), project: String.t(), title: String.t(), owner: String.t() | nil}
  @type t :: %__MODULE__{
          projects: [project()],
          people: [person()],
          channels: %{String.t() => channel_route()},
          works_on: %{String.t() => [String.t()]},
          open_tasks: [task()]
        }

  @doc "Builds a vocabulary from the seed format in docs/seeds/nyi.json."
  @spec from_seed(map()) :: t()
  def from_seed(seed) do
    aliases = Enum.group_by(seed["aliases"] || [], & &1["project"], & &1["alias"])

    %__MODULE__{
      projects:
        Enum.map(seed["projects"], fn p ->
          %{id: p["id"], name: p["name"], about: p["about"], aliases: Map.get(aliases, p["id"], [])}
        end),
      people:
        Enum.map(seed["people"], fn p ->
          %{id: p["id"], name: p["name"], title: p["title"], handles: p["handles"] || p["git"] || []}
        end),
      channels:
        Map.new(seed["channels"] || [], fn c ->
          route =
            case c["project"] do
              "split" -> :split
              other -> other
            end

          {c["name"], route}
        end),
      works_on: Enum.group_by(seed["allocations"] || [], & &1["person"], & &1["project"]),
      open_tasks: seed["open_tasks"] || []
    }
  end

  @doc "Loads the repo's NYI seed file."
  @spec nyi_seed() :: t()
  def nyi_seed do
    Path.expand("../../../../docs/seeds/nyi.json", __DIR__) |> File.read!() |> Jason.decode!() |> from_seed()
  end

  @spec project_ids(t()) :: MapSet.t(String.t())
  def project_ids(%__MODULE__{projects: projects}), do: MapSet.new(projects, & &1.id)

  @doc "Resolves a name or handle as written by the model or in chat to a person, case-insensitively."
  @spec person(t(), String.t() | nil) :: person() | nil
  def person(_vocab, nil), do: nil

  def person(%__MODULE__{people: people}, name) do
    key = name |> String.trim() |> String.trim_leading("@") |> String.downcase()

    Enum.find(people, fn p ->
      Enum.any?([p.name | p.handles], &(String.downcase(&1) == key))
    end)
  end

  @doc "Project ids the person currently works on."
  @spec projects_of(t(), person() | nil) :: [String.t()]
  def projects_of(_vocab, nil), do: []
  def projects_of(%__MODULE__{works_on: works_on}, person), do: Map.get(works_on, person.id, [])

  @doc "How a channel is mapped: a project id, `:split` (route each message), or `nil` (not read)."
  @spec channel_route(t(), String.t()) :: channel_route()
  def channel_route(%__MODULE__{channels: channels}, channel), do: Map.get(channels, channel)

  @doc "Projects whose name or alias appears as a whole word in `text`."
  @spec projects_named_in(t(), String.t()) :: [String.t()]
  def projects_named_in(%__MODULE__{projects: projects}, text) do
    for p <- projects,
        Enum.any?([p.name | p.aliases], &word_in?(text, &1)),
        do: p.id
  end

  defp word_in?(text, phrase) do
    Regex.match?(~r/(^|[^\p{L}\p{N}])#{Regex.escape(phrase)}($|[^\p{L}\p{N}])/iu, text)
  end
end
