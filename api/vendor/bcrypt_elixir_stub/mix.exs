defmodule BcryptElixirStub.MixProject do
  use Mix.Project

  def project do
    [
      app: :bcrypt_elixir,
      version: "0.0.0-stub",
      elixir: "~> 1.17",
      package: []
    ]
  end

  def application do
    [mod: {BcryptElixirStub.Application, []}]
  end
end
