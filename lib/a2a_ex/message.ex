defmodule A2AEx.Message do
  @moduledoc """
  A single message in the conversation between a user and an agent.
  """

  @type role :: :user | :agent
  @type t :: %__MODULE__{
          id: String.t(),
          role: role(),
          parts: [A2AEx.Part.t()],
          context_id: String.t() | nil,
          task_id: String.t() | nil,
          reference_task_ids: [String.t()] | nil,
          extensions: [String.t()] | nil,
          metadata: map() | nil
        }

  @enforce_keys [:id, :role, :parts]
  defstruct [
    :id,
    :role,
    :parts,
    :context_id,
    :task_id,
    :reference_task_ids,
    :extensions,
    :metadata
  ]

  @doc """
  Create a new message with a random UUID.
  """
  @spec new(role(), [A2AEx.Part.t()]) :: t()
  def new(role, parts) do
    %__MODULE__{
      id: A2AEx.ID.new(),
      role: role,
      parts: parts
    }
  end

  @doc """
  Decode a message from a JSON-decoded map (string keys, camelCase).
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(map) when is_map(map) do
    with {:ok, parts} <- decode_parts(map["parts"]) do
      {:ok,
       %__MODULE__{
         id: map["messageId"] || A2AEx.ID.new(),
         role: decode_role(map["role"]),
         parts: parts,
         context_id: map["contextId"],
         task_id: map["taskId"],
         reference_task_ids: map["referenceTaskIds"],
         extensions: map["extensions"],
         metadata: map["metadata"]
       }}
    end
  end

  @doc """
  Encode a message to a JSON-ready map (string keys, camelCase).
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = msg) do
    %{
      "kind" => "message",
      "messageId" => msg.id,
      "role" => Atom.to_string(msg.role),
      "parts" => Enum.map(msg.parts, &A2AEx.Part.to_map/1)
    }
    |> maybe_put("contextId", msg.context_id)
    |> maybe_put("taskId", msg.task_id)
    |> maybe_put("referenceTaskIds", msg.reference_task_ids)
    |> maybe_put("extensions", msg.extensions)
    |> maybe_put("metadata", msg.metadata)
  end

  defp decode_parts(nil), do: {:ok, []}
  defp decode_parts(parts) when is_list(parts), do: A2AEx.Part.from_map_list(parts)
  defp decode_parts(_), do: {:error, "invalid parts"}

  defp decode_role("user"), do: :user
  defp decode_role("agent"), do: :agent
  defp decode_role(_), do: :user

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

defimpl Jason.Encoder, for: A2AEx.Message do
  def encode(msg, opts) do
    A2AEx.Message.to_map(msg) |> Jason.Encode.map(opts)
  end
end
