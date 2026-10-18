defmodule Mix.Tasks.Noa.Demo do
  @shortdoc "Loads the public demo workspace (Lumen Labs) through the real pipeline"
  @moduledoc """
      mix noa.demo --password "a shared demo password"

  See `Noa.Demo`. Safe to run again.
  """
  use Mix.Task

  @requirements ["app.start"]

  @impl true
  def run(argv) do
    {opts, _} = OptionParser.parse!(argv, strict: [password: :string])
    password = opts[:password] || Mix.raise("Pass --password (at least 10 characters).")
    Mix.shell().info(inspect(Noa.Demo.load(password: password)))
  end
end
