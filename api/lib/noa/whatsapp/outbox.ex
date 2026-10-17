defmodule Noa.WhatsApp.Outbox do
  @moduledoc "Without Kapso credentials: nothing leaves the machine; the message is kept in the outbox as `simulated`."
  require Logger

  def send(phone, text, buttons) do
    Logger.info("WhatsApp (simulated) to #{phone}: #{text} #{inspect(Enum.map(buttons, &elem(&1, 1)))}")
    :simulated
  end
end
