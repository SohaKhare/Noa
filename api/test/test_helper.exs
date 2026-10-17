ExUnit.start(exclude: [:load | if(match?({:ok, _}, Redix.command(Noa.Graph.Redix, ["PING"])), do: [], else: [:graph])])
Ecto.Adapters.SQL.Sandbox.mode(Noa.Repo, :manual)
