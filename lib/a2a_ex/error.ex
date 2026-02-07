defmodule A2AEx.Error do
  @moduledoc """
  A2A protocol error definitions.

  Each error has a corresponding JSON-RPC error code used in the `A2AEx.JSONRPC` module.
  """

  @type error_type ::
          :parse_error
          | :invalid_request
          | :method_not_found
          | :invalid_params
          | :internal_error
          | :server_error
          | :task_not_found
          | :task_not_cancelable
          | :push_notification_not_supported
          | :unsupported_operation
          | :unsupported_content_type
          | :invalid_agent_response
          | :extended_card_not_configured
          | :unauthenticated
          | :unauthorized

  @type t :: %__MODULE__{
          type: error_type(),
          message: String.t(),
          details: map() | nil
        }

  @enforce_keys [:type, :message]
  defstruct [:type, :message, :details]

  @doc "Create a new A2A error."
  @spec new(error_type(), String.t()) :: t()
  def new(type, message) do
    %__MODULE__{type: type, message: message}
  end

  @doc "Create a new A2A error with additional details."
  @spec new(error_type(), String.t(), map()) :: t()
  def new(type, message, details) do
    %__MODULE__{type: type, message: message, details: details}
  end

  @doc "Default error message for a given error type."
  @spec default_message(error_type()) :: String.t()
  def default_message(:parse_error), do: "parse error"
  def default_message(:invalid_request), do: "invalid request"
  def default_message(:method_not_found), do: "method not found"
  def default_message(:invalid_params), do: "invalid params"
  def default_message(:internal_error), do: "internal error"
  def default_message(:server_error), do: "server error"
  def default_message(:task_not_found), do: "task not found"
  def default_message(:task_not_cancelable), do: "task cannot be canceled"
  def default_message(:push_notification_not_supported), do: "push notification not supported"
  def default_message(:unsupported_operation), do: "this operation is not supported"
  def default_message(:unsupported_content_type), do: "incompatible content types"
  def default_message(:invalid_agent_response), do: "invalid agent response"
  def default_message(:extended_card_not_configured), do: "extended card not configured"
  def default_message(:unauthenticated), do: "unauthenticated"
  def default_message(:unauthorized), do: "permission denied"
end
