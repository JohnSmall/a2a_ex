defmodule A2AEx.TaskStatusUpdateEvent do
  @moduledoc """
  Event sent by the agent to notify the client of a change in a task's status.
  """

  @type t :: %__MODULE__{
          task_id: String.t(),
          context_id: String.t(),
          status: A2AEx.TaskStatus.t(),
          final: boolean(),
          metadata: map() | nil
        }

  @enforce_keys [:task_id, :context_id, :status]
  defstruct [:task_id, :context_id, :status, :metadata, final: false]

  @doc "Create a new status update event."
  @spec new(String.t(), String.t(), A2AEx.TaskState.t(), A2AEx.Message.t() | nil) :: t()
  def new(task_id, context_id, state, message \\ nil) do
    %__MODULE__{
      task_id: task_id,
      context_id: context_id,
      status: %A2AEx.TaskStatus{
        state: state,
        message: message,
        timestamp: DateTime.utc_now()
      }
    }
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(map) when is_map(map) do
    with {:ok, status} <- A2AEx.TaskStatus.from_map(map["status"] || %{}) do
      {:ok,
       %__MODULE__{
         task_id: map["taskId"],
         context_id: map["contextId"],
         status: status,
         final: map["final"] || false,
         metadata: map["metadata"]
       }}
    end
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = event) do
    %{
      "kind" => "status-update",
      "taskId" => event.task_id,
      "contextId" => event.context_id,
      "status" => A2AEx.TaskStatus.to_map(event.status),
      "final" => event.final
    }
    |> maybe_put("metadata", event.metadata)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

defmodule A2AEx.TaskArtifactUpdateEvent do
  @moduledoc """
  Event sent by the agent to notify the client that an artifact has been generated or updated.
  """

  @type t :: %__MODULE__{
          task_id: String.t(),
          context_id: String.t(),
          artifact: A2AEx.Artifact.t(),
          append: boolean(),
          last_chunk: boolean(),
          metadata: map() | nil
        }

  @enforce_keys [:task_id, :context_id, :artifact]
  defstruct [:task_id, :context_id, :artifact, :metadata, append: false, last_chunk: false]

  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(map) when is_map(map) do
    with {:ok, artifact} <- A2AEx.Artifact.from_map(map["artifact"] || %{}) do
      {:ok,
       %__MODULE__{
         task_id: map["taskId"],
         context_id: map["contextId"],
         artifact: artifact,
         append: map["append"] || false,
         last_chunk: map["lastChunk"] || false,
         metadata: map["metadata"]
       }}
    end
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = event) do
    %{
      "kind" => "artifact-update",
      "taskId" => event.task_id,
      "contextId" => event.context_id,
      "artifact" => A2AEx.Artifact.to_map(event.artifact)
    }
    |> maybe_put_bool("append", event.append)
    |> maybe_put_bool("lastChunk", event.last_chunk)
    |> maybe_put("metadata", event.metadata)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_bool(map, _key, false), do: map
  defp maybe_put_bool(map, key, true), do: Map.put(map, key, true)
end

defmodule A2AEx.Event do
  @moduledoc """
  Union type for A2A events that can be sent over streaming connections.
  """

  @type t ::
          A2AEx.Message.t()
          | A2AEx.Task.t()
          | A2AEx.TaskStatusUpdateEvent.t()
          | A2AEx.TaskArtifactUpdateEvent.t()

  @doc "Decode an event from a JSON-decoded map, dispatching on the `kind` field."
  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(%{"kind" => "message"} = map), do: A2AEx.Message.from_map(map)
  def from_map(%{"kind" => "task"} = map), do: A2AEx.Task.from_map(map)
  def from_map(%{"kind" => "status-update"} = map), do: A2AEx.TaskStatusUpdateEvent.from_map(map)

  def from_map(%{"kind" => "artifact-update"} = map),
    do: A2AEx.TaskArtifactUpdateEvent.from_map(map)

  def from_map(%{"kind" => kind}), do: {:error, "unknown event kind: #{kind}"}
  def from_map(_), do: {:error, "missing event kind"}

  @doc "Encode any event to a JSON-ready map."
  @spec to_map(t()) :: map()
  def to_map(%A2AEx.Message{} = e), do: A2AEx.Message.to_map(e)
  def to_map(%A2AEx.Task{} = e), do: A2AEx.Task.to_map(e)
  def to_map(%A2AEx.TaskStatusUpdateEvent{} = e), do: A2AEx.TaskStatusUpdateEvent.to_map(e)
  def to_map(%A2AEx.TaskArtifactUpdateEvent{} = e), do: A2AEx.TaskArtifactUpdateEvent.to_map(e)
end

defimpl Jason.Encoder, for: A2AEx.TaskStatusUpdateEvent do
  def encode(event, opts) do
    A2AEx.TaskStatusUpdateEvent.to_map(event) |> Jason.Encode.map(opts)
  end
end

defimpl Jason.Encoder, for: A2AEx.TaskArtifactUpdateEvent do
  def encode(event, opts) do
    A2AEx.TaskArtifactUpdateEvent.to_map(event) |> Jason.Encode.map(opts)
  end
end
