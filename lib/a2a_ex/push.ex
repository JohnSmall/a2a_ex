defmodule A2AEx.PushAuthInfo do
  @moduledoc "Authentication details for a push notification endpoint."

  @type t :: %__MODULE__{
          schemes: [String.t()],
          credentials: String.t() | nil
        }

  @enforce_keys [:schemes]
  defstruct [:schemes, :credentials]

  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      schemes: map["schemes"] || [],
      credentials: map["credentials"]
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = info) do
    %{"schemes" => info.schemes}
    |> maybe_put("credentials", info.credentials)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

defmodule A2AEx.PushConfig do
  @moduledoc "Configuration for push notifications for task updates."

  @type t :: %__MODULE__{
          url: String.t(),
          id: String.t() | nil,
          token: String.t() | nil,
          authentication: A2AEx.PushAuthInfo.t() | nil
        }

  @enforce_keys [:url]
  defstruct [:url, :id, :token, :authentication]

  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    auth =
      case map["authentication"] do
        nil -> nil
        a -> A2AEx.PushAuthInfo.from_map(a)
      end

    %__MODULE__{
      url: map["url"],
      id: map["id"],
      token: map["token"],
      authentication: auth
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = config) do
    %{"url" => config.url}
    |> maybe_put("id", config.id)
    |> maybe_put("token", config.token)
    |> maybe_put("authentication", config.authentication && A2AEx.PushAuthInfo.to_map(config.authentication))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

defmodule A2AEx.TaskPushConfig do
  @moduledoc "Associates a push notification configuration with a specific task."

  @type t :: %__MODULE__{
          task_id: String.t(),
          push_notification_config: A2AEx.PushConfig.t()
        }

  @enforce_keys [:task_id, :push_notification_config]
  defstruct [:task_id, :push_notification_config]

  @spec from_map(map()) :: {:ok, t()}
  def from_map(map) when is_map(map) do
    {:ok,
     %__MODULE__{
       task_id: map["taskId"],
       push_notification_config: A2AEx.PushConfig.from_map(map["pushNotificationConfig"] || %{})
     }}
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = tpc) do
    %{
      "taskId" => tpc.task_id,
      "pushNotificationConfig" => A2AEx.PushConfig.to_map(tpc.push_notification_config)
    }
  end
end

defmodule A2AEx.GetTaskPushConfigParams do
  @moduledoc "Parameters for fetching a specific push notification config."

  @type t :: %__MODULE__{
          task_id: String.t(),
          config_id: String.t() | nil,
          metadata: map() | nil
        }

  @enforce_keys [:task_id]
  defstruct [:task_id, :config_id, :metadata]

  @spec from_map(map()) :: {:ok, t()}
  def from_map(map) when is_map(map) do
    {:ok,
     %__MODULE__{
       task_id: map["id"],
       config_id: map["pushNotificationConfigId"],
       metadata: map["metadata"]
     }}
  end
end

defmodule A2AEx.ListTaskPushConfigParams do
  @moduledoc "Parameters for listing push notification configs for a task."

  @type t :: %__MODULE__{
          task_id: String.t(),
          metadata: map() | nil
        }

  @enforce_keys [:task_id]
  defstruct [:task_id, :metadata]

  @spec from_map(map()) :: {:ok, t()}
  def from_map(map) when is_map(map) do
    {:ok, %__MODULE__{task_id: map["id"], metadata: map["metadata"]}}
  end
end

defmodule A2AEx.DeleteTaskPushConfigParams do
  @moduledoc "Parameters for deleting a push notification config."

  @type t :: %__MODULE__{
          task_id: String.t(),
          config_id: String.t(),
          metadata: map() | nil
        }

  @enforce_keys [:task_id, :config_id]
  defstruct [:task_id, :config_id, :metadata]

  @spec from_map(map()) :: {:ok, t()}
  def from_map(map) when is_map(map) do
    {:ok,
     %__MODULE__{
       task_id: map["id"],
       config_id: map["pushNotificationConfigId"],
       metadata: map["metadata"]
     }}
  end
end
