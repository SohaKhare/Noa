defmodule Noa.ReleaseTest do
  @moduledoc "The seeds shipped in the release (priv/seeds) stay the same as docs/seeds."
  use ExUnit.Case, async: true

  for file <- ~w(nyi.json nyi-sample-work.json) do
    test "priv/seeds/#{file} matches docs/seeds/#{file}" do
      assert File.read!(Path.expand("../../priv/seeds/#{unquote(file)}", __DIR__)) ==
               File.read!(Path.expand("../../../docs/seeds/#{unquote(file)}", __DIR__))
    end
  end
end
