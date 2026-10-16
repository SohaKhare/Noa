defmodule Noa.Accounts.Pbkdf2HashProvider do
  @moduledoc "PBKDF2 password hashing (copied from Tulpa v1; bcrypt's NIF does not build here)."
  @behaviour AshAuthentication.HashProvider

  @impl true
  def hash(input) when is_binary(input), do: {:ok, Pbkdf2.hash_pwd_salt(input)}
  def hash(_), do: :error

  @impl true
  def valid?(nil, _hash), do: simulate()
  def valid?(input, hash) when is_binary(input) and is_binary(hash), do: Pbkdf2.verify_pass(input, hash)

  @impl true
  def simulate, do: Pbkdf2.no_user_verify()
end
