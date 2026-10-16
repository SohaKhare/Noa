defmodule BcryptElixirStub.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args), do: Supervisor.start_link([], strategy: :one_for_one)
end

defmodule Bcrypt do
  @moduledoc false

  def hash_pwd_salt(_password), do: "stub"
  def verify_pass(_password, _hash), do: false
  def no_user_verify, do: false
end
