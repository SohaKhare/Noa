defmodule Noa.Ingest.Gmail.IMAP do
  @moduledoc """
  Narrow IMAP4rev1 client: TLS-authenticated, EXAMINE (read-only), UID SEARCH,
  UID FETCH BODY.PEEK[] (no Seen flag). No SMTP and no inbox mutation.
  """
  @timeout 15_000
  @max_literal 1_000_000

  def connect(host, port, username, password) do
    opts = [
      :binary,
      active: false,
      packet: :line,
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(host),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    with {:ok, socket} <- :ssl.connect(String.to_charlist(host), port, opts, @timeout) do
      result =
        with {:ok, greeting} <- :ssl.recv(socket, 0, @timeout),
             true <- String.starts_with?(greeting, "* OK") do
          command(socket, "LOGIN #{quoted(username)} #{quoted(password)}")
        else
          false -> {:error, :bad_greeting}
          error -> error
        end

      case result do
        {:ok, _} ->
          {:ok, socket}

        error ->
          :ssl.close(socket)
          error
      end
    end
  end

  def examine(socket) do
    with {:ok, lines} <- command(socket, "EXAMINE INBOX"),
         [uidvalidity] <-
           for(
             line <- lines,
             captures = Regex.run(~r/\[UIDVALIDITY (\d+)\]/i, line),
             captures,
             do: Enum.at(captures, 1)
           ),
         [uidnext] <-
           for(line <- lines, captures = Regex.run(~r/\[UIDNEXT (\d+)\]/i, line), captures, do: Enum.at(captures, 1)) do
      {:ok, {uidvalidity, String.to_integer(uidnext)}}
    else
      _ -> {:error, :missing_uid_metadata}
    end
  end

  def search(socket, from_uid) when is_integer(from_uid) and from_uid > 0 do
    with {:ok, lines} <- command(socket, "UID SEARCH UID #{from_uid}:*") do
      {:ok,
       lines
       |> Enum.filter(&String.starts_with?(&1, "* SEARCH"))
       |> Enum.flat_map(fn line ->
         line
         |> String.trim()
         |> String.replace_prefix("* SEARCH", "")
         |> String.split()
         |> Enum.map(&String.to_integer/1)
       end)
       |> Enum.filter(&(&1 >= from_uid))
       |> Enum.uniq()
       |> Enum.sort()}
    end
  end

  def fetch(socket, uid) do
    with {:ok, lines} <- command(socket, "UID FETCH #{uid} (UID BODY.PEEK[])") do
      case Enum.find(lines, &match?({:literal, _}, &1)) do
        {:literal, raw} -> {:ok, raw}
        _ -> {:error, :missing_message}
      end
    end
  end

  def close(socket) do
    # A failed connection is simply closed; no sensitive commands are logged.
    :ssl.close(socket)
  end

  defp quoted(value) do
    value = value |> String.replace("\\", "\\\\") |> String.replace("\"", "\\\"") |> String.replace(~r/[\r\n]/, "")
    "\"" <> value <> "\""
  end

  defp command(socket, request) do
    tag = "N#{System.unique_integer([:positive])}"

    with :ok <- :ssl.send(socket, tag <> " " <> request <> "\r\n") do
      receive_response(socket, tag, [], 0)
    end
  end

  defp receive_response(_socket, _tag, _acc, count) when count > 500, do: {:error, :too_many_responses}

  defp receive_response(socket, tag, acc, count) do
    with {:ok, line} <- :ssl.recv(socket, 0, @timeout) do
      cond do
        String.starts_with?(line, tag <> " OK") ->
          {:ok, Enum.reverse([line | acc])}

        String.starts_with?(line, tag <> " ") ->
          {:error, :imap_rejected}

        true ->
          case Regex.run(~r/\{(\d+)\}\r\n$/, line) do
            [_, size] ->
              size = String.to_integer(size)

              if size > @max_literal do
                {:error, :message_too_large}
              else
                # packet :line cannot read arbitrary RFC822 bytes; switch just for the literal.
                with :ok <- :ssl.setopts(socket, packet: :raw),
                     {:ok, literal} <- :ssl.recv(socket, size, @timeout),
                     :ok <- :ssl.setopts(socket, packet: :line) do
                  receive_response(socket, tag, [{:literal, literal}, line | acc], count + 1)
                end
              end

            _ ->
              receive_response(socket, tag, [line | acc], count + 1)
          end
      end
    end
  end
end
