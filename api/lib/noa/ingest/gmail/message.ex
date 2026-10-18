defmodule Noa.Ingest.Gmail.Message do
  @moduledoc "Parse subject, sender and text/plain MIME parts; never ingest attachments or HTML."

  @max_text 30_000

  def parse(raw) when is_binary(raw) do
    with {:ok, headers, body} <- split(raw),
         from when is_binary(from) <- address(headers["from"]),
         {:ok, text} <- plain(headers, body) do
      subject = decode_header(headers["subject"] || "(no subject)")
      text = String.trim("Subject: #{subject}\n\n#{text}") |> String.slice(0, @max_text)
      if String.trim(text) == "", do: {:error, :no_text}, else: {:ok, %{author_id: from, author: from, text: text}}
    else
      nil -> {:error, :missing_sender}
      error -> error
    end
  end

  defp split(raw) do
    case :binary.split(raw, "\r\n\r\n") do
      [headers, body] ->
        {:ok, headers(headers), body}

      _ ->
        case :binary.split(raw, "\n\n") do
          [headers, body] -> {:ok, headers(headers), body}
          _ -> {:error, :invalid_message}
        end
    end
  end

  defp headers(raw) do
    raw
    |> String.replace_invalid()
    |> String.replace(~r/\r?\n[\t ]+/, " ")
    |> String.split(~r/\r?\n/)
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, ":", parts: 2) do
        [key, value] -> Map.put_new(acc, String.downcase(String.trim(key)), String.trim(value))
        _ -> acc
      end
    end)
  end

  defp address(nil), do: nil

  defp address(from) do
    case Regex.run(~r/[\w.!#$%&'*+\/=?^_`{|}~-]+@[\w.-]+\.[A-Za-z]{2,}/, from) do
      [email] -> String.downcase(email)
      _ -> nil
    end
  end

  defp plain(headers, body) do
    raw_type = headers["content-type"] || "text/plain"
    type = String.downcase(raw_type)
    disposition = String.downcase(headers["content-disposition"] || "")

    cond do
      String.contains?(disposition, "attachment") ->
        {:error, :attachment}

      String.starts_with?(type, "multipart/") ->
        case Regex.run(~r/boundary\s*=\s*(?:"([^"]+)"|([^;\s]+))/i, raw_type) do
          [_, quoted] -> parts(body, quoted)
          [_, "", unquoted] -> parts(body, unquoted)
          _ -> {:error, :invalid_boundary}
        end

      String.starts_with?(type, "text/plain") ->
        decode(body, headers["content-transfer-encoding"])

      true ->
        {:error, :no_plain_text}
    end
  end

  defp parts(body, boundary) do
    body
    |> :binary.split("--" <> boundary, [:global])
    |> Enum.drop(1)
    |> Enum.take_while(&(not String.starts_with?(&1, "--")))
    |> Enum.map(fn part ->
      part
      |> String.trim_leading("\r\n")
      |> split()
      |> case do
        {:ok, h, b} -> plain(h, b)
        error -> error
      end
    end)
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.map_join("\n\n", fn {:ok, text} -> text end)
    |> case do
      "" -> {:error, :no_plain_text}
      text -> {:ok, text}
    end
  end

  defp decode(body, encoding) do
    case String.downcase(encoding || "") do
      "base64" ->
        case Base.decode64(String.replace(body, ~r/\s+/, "")) do
          {:ok, value} -> {:ok, String.replace_invalid(value)}
          :error -> {:error, :invalid_base64}
        end

      "quoted-printable" ->
        {:ok,
         body
         |> String.replace(~r/=\r?\n/, "")
         |> String.replace(~r/=([0-9A-Fa-f]{2})/, fn hex ->
           <<String.to_integer(String.slice(hex, 1, 2), 16)>>
         end)
         |> String.replace_invalid()}

      _ ->
        {:ok, String.replace_invalid(body)}
    end
  end

  defp decode_header(value) do
    Regex.replace(~r/=\?[^?]+\?(B|Q)\?([^?]+)\?=/i, value, fn _, encoding, encoded ->
      case String.upcase(encoding) do
        "B" ->
          case Base.decode64(encoded) do
            {:ok, result} -> String.replace_invalid(result)
            _ -> encoded
          end

        "Q" ->
          encoded |> String.replace("_", " ") |> then(fn text -> elem(decode(text, "quoted-printable"), 1) end)
      end
    end)
  end
end
