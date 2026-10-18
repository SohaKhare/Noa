defmodule Noa.Ingest.Gmail.Poller do
  @moduledoc """
  Poll one explicitly enabled Workspace mailbox. On the first successful EXAMINE,
  checkpoints UIDNEXT-1 without reading old mail. Subsequent polls fetch only new UIDs;
  the UIDVALIDITY-scoped checkpoint survives restarts and handles mailbox resets.
  """
  use GenServer
  require Logger
  require Ash.Query

  alias Noa.Ingest.Gmail.{IMAP, Message}
  alias Noa.{Events, Repo, Work}

  @interval 60_000
  @batch 100

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    send(self(), :poll)
    {:ok, Application.fetch_env!(:noa, Noa.Ingest.Gmail)}
  end

  @impl true
  def handle_info(:poll, config) do
    case sync(config) do
      {:ok, count} when count > 0 -> Logger.info("Gmail imported #{count} messages")
      {:error, reason} -> Logger.warning("Gmail poll failed: #{inspect(reason)}")
      _ -> :ok
    end

    Process.send_after(self(), :poll, @interval)
    {:noreply, config}
  end

  @doc "Sync once; safe to retry after network errors or a restart."
  def sync(config) do
    with {:ok, channel} <- channel(config[:org_id], config[:username]),
         {:ok, socket} <- IMAP.connect(config[:host], config[:port], config[:username], config[:password]) do
      try do
        with {:ok, {validity, uidnext}} <- IMAP.examine(socket) do
          name = "gmail:#{config[:org_id]}:#{config[:username]}:#{validity}"

          if not initialized?(name) do
            Events.put_position(name, uidnext - 1)
            {:ok, 0}
          else
            import_new(socket, name, channel, config[:org_id])
          end
        end
      after
        IMAP.close(socket)
      end
    end
  end

  defp channel(org_id, mailbox) do
    with {:ok, %Noa.Orgs.Org{}} <- Ash.get(Noa.Orgs.Org, org_id, authorize?: false) do
      existing =
        Work.Channel
        |> Ash.Query.filter(org_id == ^org_id and platform == :email and name == "INBOX")
        |> Ash.read_one!(authorize?: false)

      if existing do
        if existing.external_id == mailbox and existing.read, do: {:ok, existing}, else: {:error, :inbox_not_enabled}
      else
        Work.Channel
        |> Ash.Changeset.for_create(:create, %{
          org_id: org_id,
          platform: :email,
          name: "INBOX",
          external_id: mailbox,
          split: true,
          read: true
        })
        |> Ash.create(authorize?: false, upsert?: true, upsert_identity: :unique_name)
      end
    else
      _ -> {:error, :workspace_not_found}
    end
  end

  defp initialized?(name) do
    %Postgrex.Result{num_rows: count} = Repo.query!("SELECT position FROM projections WHERE name = $1", [name])
    count > 0
  end

  defp import_new(socket, name, channel, org_id) do
    position = Events.position(name)

    with {:ok, uids} <- IMAP.search(socket, max(position + 1, 1)) do
      uids
      |> Enum.take(@batch)
      |> Enum.reduce_while({:ok, 0}, fn uid, {:ok, count} ->
        case IMAP.fetch(socket, uid) do
          {:ok, raw} ->
            case record(Message.parse(raw), org_id, channel, name, uid) do
              {:ok, :imported} ->
                Events.put_position(name, uid)
                {:cont, {:ok, count + 1}}

              {:ok, :skipped} ->
                Events.put_position(name, uid)
                {:cont, {:ok, count}}

              {:duplicate, _} ->
                Events.put_position(name, uid)
                {:cont, {:ok, count}}

              error ->
                {:halt, error}
            end

          {:error, :message_too_large} ->
            Logger.warning("Gmail skipped oversized message UID #{uid} (over 1 MB)")
            Events.put_position(name, uid)
            {:cont, {:ok, count}}

          error ->
            {:halt, error}
        end
      end)
    end
  end

  defp record({:ok, email}, org_id, channel, name, uid) do
    case Work.record_message(
           org_id,
           Map.merge(email, %{
             platform: :email,
             channel: channel.name,
             channel_id: channel.external_id,
             message_id: "#{name}:#{uid}",
             at: DateTime.utc_now()
           })
         ) do
      {:ok, _event} -> {:ok, :imported}
      other -> other
    end
  end

  # Unsupported or malformed messages are explicitly skipped rather than blocking
  # the entire inbox forever. No attachment or HTML contents enter the event log.
  defp record({:error, reason}, _org_id, _channel, _name, _uid) do
    Logger.warning("Gmail skipped a message: #{inspect(reason)}")
    {:ok, :skipped}
  end
end
