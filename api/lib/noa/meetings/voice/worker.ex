defmodule Noa.Meetings.Voice.Worker do
  @moduledoc "Bounded NDJSON pipe to the DAVE-capable receiver. No public worker socket or audio files."
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def enabled?,
    do:
      Application.get_env(:noa, __MODULE__, [])[:enabled] != false and System.get_env("DISCORD_VOICE_ENABLED") == "true"

  def request(payload), do: GenServer.call(__MODULE__, {:request, payload}, 65_000)

  @impl true
  def init(_) do
    node = System.find_executable("node")

    port =
      if enabled?() and node do
        Port.open({:spawn_executable, node}, [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          {:line, 1_500_000},
          args: ["--max-old-space-size=128", Application.app_dir(:noa, "priv/voice/worker.mjs")]
        ])
      end

    {:ok, %{port: port, pending: %{}}}
  end

  @impl true
  def handle_call({:request, _}, _from, %{port: nil} = state), do: {:reply, {:error, :voice_disabled}, state}

  def handle_call({:request, payload}, from, state) do
    id = Ecto.UUID.generate()
    Process.send_after(self(), {:timeout, id}, 60_000)
    Port.command(state.port, Jason.encode!(Map.put(payload, :id, id)) <> "\n")
    {:noreply, put_in(state, [:pending, id], from)}
  end

  @impl true
  def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state) do
    case Jason.decode(line) do
      {:ok, %{"id" => id} = response} when is_binary(id) ->
        {from, pending} = Map.pop(state.pending, id)

        if from,
          do:
            GenServer.reply(from, if(response["ok"], do: {:ok, response["data"]}, else: {:error, :voice_worker_failed}))

        {:noreply, %{state | pending: pending}}

      {:ok, event} ->
        if pid = Process.whereis(Noa.Meetings.Voice), do: send(pid, {:voice_event, event})
        {:noreply, state}

      _ ->
        Port.close(port)
        {:noreply, down(state)}
    end
  end

  def handle_info({port, {:data, {:noeol, _}}}, %{port: port} = state) do
    Port.close(port)
    {:noreply, down(state)}
  end

  def handle_info({port, {:exit_status, _}}, %{port: port} = state), do: {:noreply, down(state)}

  def handle_info({:timeout, id}, state) do
    if Map.has_key?(state.pending, id) do
      Port.close(state.port)
      {:noreply, down(state)}
    else
      {:noreply, state}
    end
  end

  def handle_info(_, state), do: {:noreply, state}

  defp down(state) do
    Enum.each(state.pending, fn {_, from} -> GenServer.reply(from, {:error, :voice_worker_failed}) end)
    if pid = Process.whereis(Noa.Meetings.Voice), do: send(pid, {:voice_event, %{"type" => "worker_error"}})
    %{state | port: nil, pending: %{}}
  end
end
