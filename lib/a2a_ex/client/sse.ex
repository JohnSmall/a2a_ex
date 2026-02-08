defmodule A2AEx.Client.SSE do
  @moduledoc """
  Server-Sent Events (SSE) line parser.

  Parses chunked HTTP response data in SSE format (`data: {json}\\n\\n`)
  into individual JSON-decoded event maps.
  """

  @doc """
  Parse a chunk of SSE data, returning decoded events and remaining buffer.

  Handles buffering across chunks — pass the returned remainder as the
  buffer for the next call.

  ## Examples

      iex> A2AEx.Client.SSE.parse_chunk("data: {\\"a\\":1}\\n\\n", "")
      {[%{"a" => 1}], ""}

      iex> A2AEx.Client.SSE.parse_chunk("data: {\\"a\\":1}\\n\\ndata: {\\"b", "")
      {[%{"a" => 1}], "data: {\\"b"}
  """
  @spec parse_chunk(binary(), binary()) :: {[map()], binary()}
  def parse_chunk(data, buffer) do
    combined = buffer <> data
    parse_events(combined, [])
  end

  defp parse_events(data, acc) do
    case :binary.split(data, "\n\n") do
      [event_text, rest] ->
        case parse_event_line(event_text) do
          {:ok, decoded} -> parse_events(rest, acc ++ [decoded])
          :skip -> parse_events(rest, acc)
        end

      [_incomplete] ->
        {acc, data}
    end
  end

  defp parse_event_line("data: " <> json) do
    case Jason.decode(json) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> :skip
    end
  end

  defp parse_event_line("data:" <> json) do
    parse_event_line("data: " <> String.trim_leading(json))
  end

  defp parse_event_line(_), do: :skip
end
