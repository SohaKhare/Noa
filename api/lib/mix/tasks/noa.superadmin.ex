defmodule Mix.Tasks.Noa.Superadmin do
  @shortdoc "Creates the platform superadmin (the one account that is not invited)"
  @moduledoc """
      mix noa.superadmin you@company.com [--name "Your Name"]

  Generates a password and writes it to `api/.superadmin` (gitignored) instead of
  printing it. Sign in at the web app's /login, then create workspaces at /admin.
  Change the password later with "Forgot password".
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, [email], _} = OptionParser.parse(args, strict: [name: :string])
    Mix.Task.run("app.start")

    password = 18 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

    Noa.Accounts.User
    |> Ash.Changeset.for_create(:create_with_password, %{
      email: email,
      name: opts[:name],
      is_superadmin: true,
      password: password
    })
    |> Ash.create(authorize?: false)
    |> case do
      {:ok, user} ->
        path = Path.expand(".superadmin")
        File.write!(path, "email=#{user.email}\npassword=#{password}\n")
        File.chmod!(path, 0o600)
        Mix.shell().info("Superadmin #{user.email} created. Password saved to #{path}")

      {:error, error} ->
        Mix.raise("Could not create superadmin: #{Exception.message(error)}")
    end
  end
end
