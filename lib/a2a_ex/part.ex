defmodule A2AEx.FileBytes do
  @moduledoc """
  File content provided as a base64-encoded string.
  """

  @type t :: %__MODULE__{
          bytes: String.t(),
          name: String.t() | nil,
          mime_type: String.t() | nil
        }

  @enforce_keys [:bytes]
  defstruct [:bytes, :name, :mime_type]
end

defmodule A2AEx.FileURI do
  @moduledoc """
  File content located at a URI.
  """

  @type t :: %__MODULE__{
          uri: String.t(),
          name: String.t() | nil,
          mime_type: String.t() | nil
        }

  @enforce_keys [:uri]
  defstruct [:uri, :name, :mime_type]
end

defmodule A2AEx.TextPart do
  @moduledoc """
  A text segment within a message or artifact.
  """

  @type t :: %__MODULE__{
          text: String.t(),
          metadata: map() | nil
        }

  @enforce_keys [:text]
  defstruct [:text, :metadata]
end

defmodule A2AEx.FilePart do
  @moduledoc """
  A file segment within a message or artifact.
  The file content can be provided either as base64 bytes or as a URI.
  """

  @type t :: %__MODULE__{
          file: A2AEx.FileBytes.t() | A2AEx.FileURI.t(),
          metadata: map() | nil
        }

  @enforce_keys [:file]
  defstruct [:file, :metadata]
end

defmodule A2AEx.DataPart do
  @moduledoc """
  A structured data segment (e.g., JSON) within a message or artifact.
  """

  @type t :: %__MODULE__{
          data: map(),
          metadata: map() | nil
        }

  @enforce_keys [:data]
  defstruct [:data, :metadata]
end

defmodule A2AEx.Part do
  @moduledoc """
  Union type for message/artifact content parts.

  A part can be one of:
  - `A2AEx.TextPart` — text content
  - `A2AEx.FilePart` — file content (bytes or URI)
  - `A2AEx.DataPart` — structured data
  """

  @type t :: A2AEx.TextPart.t() | A2AEx.FilePart.t() | A2AEx.DataPart.t()

  @doc """
  Decode a part from a JSON-decoded map (string keys, camelCase).
  Dispatches on the `"kind"` field.
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(%{"kind" => "text", "text" => text} = map) do
    {:ok, %A2AEx.TextPart{text: text, metadata: map["metadata"]}}
  end

  def from_map(%{"kind" => "file", "file" => file_map} = map) do
    case decode_file_content(file_map) do
      {:ok, file} -> {:ok, %A2AEx.FilePart{file: file, metadata: map["metadata"]}}
      error -> error
    end
  end

  def from_map(%{"kind" => "data", "data" => data} = map) when is_map(data) do
    {:ok, %A2AEx.DataPart{data: data, metadata: map["metadata"]}}
  end

  def from_map(%{"kind" => kind}) do
    {:error, "unknown part kind: #{kind}"}
  end

  def from_map(_) do
    {:error, "missing or invalid part kind"}
  end

  @doc """
  Decode a list of parts from JSON-decoded maps.
  """
  @spec from_map_list([map()]) :: {:ok, [t()]} | {:error, String.t()}
  def from_map_list(parts) when is_list(parts) do
    parts
    |> Enum.reduce_while({:ok, []}, fn part_map, {:ok, acc} ->
      case from_map(part_map) do
        {:ok, part} -> {:cont, {:ok, [part | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, parts} -> {:ok, Enum.reverse(parts)}
      error -> error
    end
  end

  @doc """
  Encode a part to a JSON-ready map (string keys, camelCase).
  """
  @spec to_map(t()) :: map()
  def to_map(%A2AEx.TextPart{} = part) do
    %{"kind" => "text", "text" => part.text}
    |> maybe_put("metadata", part.metadata)
  end

  def to_map(%A2AEx.FilePart{} = part) do
    %{"kind" => "file", "file" => encode_file_content(part.file)}
    |> maybe_put("metadata", part.metadata)
  end

  def to_map(%A2AEx.DataPart{} = part) do
    %{"kind" => "data", "data" => part.data}
    |> maybe_put("metadata", part.metadata)
  end

  defp decode_file_content(%{"bytes" => bytes} = map) do
    {:ok,
     %A2AEx.FileBytes{
       bytes: bytes,
       name: map["name"],
       mime_type: map["mimeType"]
     }}
  end

  defp decode_file_content(%{"uri" => uri} = map) do
    {:ok,
     %A2AEx.FileURI{
       uri: uri,
       name: map["name"],
       mime_type: map["mimeType"]
     }}
  end

  defp decode_file_content(_) do
    {:error, "invalid file part: either bytes or uri must be set"}
  end

  defp encode_file_content(%A2AEx.FileBytes{} = f) do
    %{"bytes" => f.bytes}
    |> maybe_put("name", f.name)
    |> maybe_put("mimeType", f.mime_type)
  end

  defp encode_file_content(%A2AEx.FileURI{} = f) do
    %{"uri" => f.uri}
    |> maybe_put("name", f.name)
    |> maybe_put("mimeType", f.mime_type)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

# Jason.Encoder implementations

defimpl Jason.Encoder, for: A2AEx.TextPart do
  def encode(part, opts) do
    A2AEx.Part.to_map(part) |> Jason.Encode.map(opts)
  end
end

defimpl Jason.Encoder, for: A2AEx.FilePart do
  def encode(part, opts) do
    A2AEx.Part.to_map(part) |> Jason.Encode.map(opts)
  end
end

defimpl Jason.Encoder, for: A2AEx.DataPart do
  def encode(part, opts) do
    A2AEx.Part.to_map(part) |> Jason.Encode.map(opts)
  end
end
