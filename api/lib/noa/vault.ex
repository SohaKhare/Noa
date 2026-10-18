defmodule Noa.Vault do
  @moduledoc """
  Encrypts the secrets companies give Noa (GitHub webhook secrets and tokens) before they
  are stored: AES-GCM with keys derived from the endpoint's `secret_key_base`, through
  `Plug.Crypto.MessageEncryptor`. Rotating `SECRET_KEY_BASE` makes stored secrets
  unreadable, so connectors would need reconnecting.
  """

  def encrypt(nil), do: nil

  def encrypt(plain) when is_binary(plain),
    do: Plug.Crypto.MessageEncryptor.encrypt(plain, key("noa vault"), key("noa vault sign"))

  def decrypt(nil), do: nil

  def decrypt(cipher) when is_binary(cipher) do
    case Plug.Crypto.MessageEncryptor.decrypt(cipher, key("noa vault"), key("noa vault sign")) do
      {:ok, plain} -> plain
      :error -> nil
    end
  end

  defp key(salt) do
    base = Application.fetch_env!(:noa, NoaWeb.Endpoint)[:secret_key_base]
    Plug.Crypto.KeyGenerator.generate(base, salt, length: 32, cache: Plug.Crypto.Keys)
  end
end
