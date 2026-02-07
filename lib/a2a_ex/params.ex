defmodule A2AEx.TaskIDParams do
  @moduledoc "Parameters containing a task ID, used for simple task operations."

  @type t :: %__MODULE__{
          id: String.t(),
          metadata: map() | nil
        }

  @enforce_keys [:id]
  defstruct [:id, :metadata]

  @spec from_map(map()) :: {:ok, t()}
  def from_map(map) when is_map(map) do
    {:ok, %__MODULE__{id: map["id"], metadata: map["metadata"]}}
  end
end

defmodule A2AEx.TaskQueryParams do
  @moduledoc "Parameters for querying a task, with an option to limit history length."

  @type t :: %__MODULE__{
          id: String.t(),
          history_length: non_neg_integer() | nil,
          metadata: map() | nil
        }

  @enforce_keys [:id]
  defstruct [:id, :history_length, :metadata]

  @spec from_map(map()) :: {:ok, t()}
  def from_map(map) when is_map(map) do
    {:ok,
     %__MODULE__{
       id: map["id"],
       history_length: map["historyLength"],
       metadata: map["metadata"]
     }}
  end
end

defmodule A2AEx.MessageSendConfig do
  @moduledoc "Configuration options for a message/send or message/stream request."

  @type t :: %__MODULE__{
          accepted_output_modes: [String.t()] | nil,
          blocking: boolean() | nil,
          history_length: non_neg_integer() | nil,
          push_notification_config: A2AEx.PushConfig.t() | nil
        }

  defstruct [:accepted_output_modes, :blocking, :history_length, :push_notification_config]

  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    push_config =
      case map["pushNotificationConfig"] do
        nil -> nil
        pc -> A2AEx.PushConfig.from_map(pc)
      end

    %__MODULE__{
      accepted_output_modes: map["acceptedOutputModes"],
      blocking: map["blocking"],
      history_length: map["historyLength"],
      push_notification_config: push_config
    }
  end
end

defmodule A2AEx.MessageSendParams do
  @moduledoc "Parameters for a request to send a message to an agent."

  @type t :: %__MODULE__{
          message: A2AEx.Message.t(),
          config: A2AEx.MessageSendConfig.t() | nil,
          metadata: map() | nil
        }

  @enforce_keys [:message]
  defstruct [:message, :config, :metadata]

  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(map) when is_map(map) do
    with {:ok, message} <- A2AEx.Message.from_map(map["message"] || %{}) do
      config =
        case map["configuration"] do
          nil -> nil
          c -> A2AEx.MessageSendConfig.from_map(c)
        end

      {:ok,
       %__MODULE__{
         message: message,
         config: config,
         metadata: map["metadata"]
       }}
    end
  end
end
