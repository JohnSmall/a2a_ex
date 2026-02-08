defmodule A2AEx.TaskState do
  @moduledoc """
  Possible states of an A2A task.
  """

  @type t ::
          :submitted
          | :working
          | :input_required
          | :completed
          | :failed
          | :canceled
          | :rejected
          | :auth_required
          | :unknown

  @terminal_states [:completed, :canceled, :failed, :rejected]

  @doc "Returns true if the state is terminal (task is immutable)."
  @spec terminal?(t()) :: boolean()
  def terminal?(state), do: state in @terminal_states

  @doc "Decode a task state from a JSON string."
  @spec from_string(String.t()) :: t()
  def from_string("submitted"), do: :submitted
  def from_string("working"), do: :working
  def from_string("input-required"), do: :input_required
  def from_string("completed"), do: :completed
  def from_string("failed"), do: :failed
  def from_string("canceled"), do: :canceled
  def from_string("rejected"), do: :rejected
  def from_string("auth-required"), do: :auth_required
  def from_string(_), do: :unknown

  @doc "Encode a task state to a JSON string."
  @spec to_string(t()) :: String.t()
  def to_string(:submitted), do: "submitted"
  def to_string(:working), do: "working"
  def to_string(:input_required), do: "input-required"
  def to_string(:completed), do: "completed"
  def to_string(:failed), do: "failed"
  def to_string(:canceled), do: "canceled"
  def to_string(:rejected), do: "rejected"
  def to_string(:auth_required), do: "auth-required"
  def to_string(:unknown), do: "unknown"
end

defmodule A2AEx.TaskStatus do
  @moduledoc """
  The status of a task at a specific point in time.
  """

  @type t :: %__MODULE__{
          state: A2AEx.TaskState.t(),
          message: A2AEx.Message.t() | nil,
          timestamp: DateTime.t() | nil
        }

  @enforce_keys [:state]
  defstruct [:state, :message, :timestamp]

  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(map) when is_map(map) do
    message =
      case map["message"] do
        nil -> nil
        msg_map -> elem(A2AEx.Message.from_map(msg_map), 1)
      end

    {:ok,
     %__MODULE__{
       state: A2AEx.TaskState.from_string(map["state"] || ""),
       message: message,
       timestamp: parse_timestamp(map["timestamp"])
     }}
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = status) do
    %{"state" => A2AEx.TaskState.to_string(status.state)}
    |> maybe_put("message", status.message && A2AEx.Message.to_map(status.message))
    |> maybe_put("timestamp", status.timestamp && DateTime.to_iso8601(status.timestamp))
  end

  defp parse_timestamp(nil), do: nil

  defp parse_timestamp(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp parse_timestamp(_), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

defmodule A2AEx.Task do
  @moduledoc """
  A single, stateful operation or conversation between a client and an agent.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          context_id: String.t(),
          status: A2AEx.TaskStatus.t(),
          artifacts: [A2AEx.Artifact.t()] | nil,
          history: [A2AEx.Message.t()] | nil,
          metadata: map() | nil
        }

  @enforce_keys [:id, :context_id, :status]
  defstruct [:id, :context_id, :status, :artifacts, :history, :metadata]

  @doc "Create a new task in submitted state."
  @spec new_submitted(A2AEx.Message.t(), keyword()) :: t()
  def new_submitted(%A2AEx.Message{} = message, opts \\ []) do
    task_id = Keyword.get(opts, :task_id) || A2AEx.ID.new()
    context_id = Keyword.get(opts, :context_id) || message.context_id || A2AEx.ID.new()

    %__MODULE__{
      id: task_id,
      context_id: context_id,
      status: %A2AEx.TaskStatus{state: :submitted},
      history: [message]
    }
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(map) when is_map(map) do
    with {:ok, status} <- A2AEx.TaskStatus.from_map(map["status"] || %{}),
         {:ok, artifacts} <- decode_artifacts(map["artifacts"]),
         {:ok, history} <- decode_history(map["history"]) do
      {:ok,
       %__MODULE__{
         id: map["id"] || A2AEx.ID.new(),
         context_id: map["contextId"] || A2AEx.ID.new(),
         status: status,
         artifacts: artifacts,
         history: history,
         metadata: map["metadata"]
       }}
    end
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = task) do
    %{
      "kind" => "task",
      "id" => task.id,
      "contextId" => task.context_id,
      "status" => A2AEx.TaskStatus.to_map(task.status)
    }
    |> maybe_put_list("artifacts", task.artifacts, &A2AEx.Artifact.to_map/1)
    |> maybe_put_list("history", task.history, &A2AEx.Message.to_map/1)
    |> maybe_put("metadata", task.metadata)
  end

  defp decode_artifacts(nil), do: {:ok, nil}

  defp decode_artifacts(list) when is_list(list) do
    list
    |> Enum.reduce_while({:ok, []}, fn map, {:ok, acc} ->
      case A2AEx.Artifact.from_map(map) do
        {:ok, artifact} -> {:cont, {:ok, [artifact | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, artifacts} -> {:ok, Enum.reverse(artifacts)}
      error -> error
    end
  end

  defp decode_history(nil), do: {:ok, nil}

  defp decode_history(list) when is_list(list) do
    list
    |> Enum.reduce_while({:ok, []}, fn map, {:ok, acc} ->
      case A2AEx.Message.from_map(map) do
        {:ok, msg} -> {:cont, {:ok, [msg | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, msgs} -> {:ok, Enum.reverse(msgs)}
      error -> error
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_list(map, _key, nil, _fun), do: map
  defp maybe_put_list(map, key, list, fun), do: Map.put(map, key, Enum.map(list, fun))
end

defimpl Jason.Encoder, for: A2AEx.TaskStatus do
  def encode(status, opts) do
    A2AEx.TaskStatus.to_map(status) |> Jason.Encode.map(opts)
  end
end

defimpl Jason.Encoder, for: A2AEx.Task do
  def encode(task, opts) do
    A2AEx.Task.to_map(task) |> Jason.Encode.map(opts)
  end
end
