defmodule Noa.MixProject do
  use Mix.Project

  def project do
    [
      app: :noa,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  def application do
    [mod: {Noa.Application, []}, extra_applications: [:logger, :runtime_tools]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.8.13"},
      {:bandit, "~> 1.5"},
      {:ash, "~> 3.32"},
      {:ash_postgres, "~> 2.12"},
      {:ash_authentication, "~> 4.14"},
      # bcrypt_elixir's NIF does not build on this OTP; passwords use PBKDF2 (Noa.Accounts.Pbkdf2HashProvider).
      {:bcrypt_elixir, path: "vendor/bcrypt_elixir_stub", override: true},
      {:pbkdf2_elixir, "~> 2.0"},
      {:simple_sat, "~> 0.1"},
      {:ecto_sql, "~> 3.14"},
      {:postgrex, ">= 0.0.0"},
      {:swoosh, "~> 1.16"},
      {:cors_plug, "~> 3.0"},
      {:ecto, "~> 3.12"},
      {:instructor_lite, "~> 1.0"},
      {:req, "~> 0.5"},
      {:nostrum, "~> 0.10"},
      {:falkordb, "~> 0.8.2"},
      {:oban, "~> 2.24"},
      {:jason, "~> 1.4"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ash.setup", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ash.setup", "run priv/repo/seeds.exs"],
      test: ["ash.setup --quiet", "test"]
    ]
  end
end
