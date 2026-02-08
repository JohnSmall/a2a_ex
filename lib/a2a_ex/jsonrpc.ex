defmodule A2AEx.JSONRPC do
  @moduledoc """
  JSON-RPC 2.0 encode/decode layer for the A2A protocol.

  Provides request parsing, response encoding, and error code mapping
  per the A2A specification.
  """

  @version "2.0"

  # JSON-RPC method names per A2A spec
  @method_message_send "message/send"
  @method_message_stream "message/stream"
  @method_tasks_get "tasks/get"
  @method_tasks_cancel "tasks/cancel"
  @method_tasks_resubscribe "tasks/resubscribe"
  @method_push_config_get "tasks/pushNotificationConfig/get"
  @method_push_config_set "tasks/pushNotificationConfig/set"
  @method_push_config_list "tasks/pushNotificationConfig/list"
  @method_push_config_delete "tasks/pushNotificationConfig/delete"
  @method_get_extended_card "agent/getAuthenticatedExtendedCard"

  @doc "All A2A method names."
  @spec methods() :: [String.t()]
  def methods do
    [
      @method_message_send,
      @method_message_stream,
      @method_tasks_get,
      @method_tasks_cancel,
      @method_tasks_resubscribe,
      @method_push_config_get,
      @method_push_config_set,
      @method_push_config_list,
      @method_push_config_delete,
      @method_get_extended_card
    ]
  end

  @doc "Streaming methods that use SSE."
  @spec streaming_methods() :: [String.t()]
  def streaming_methods, do: [@method_message_stream, @method_tasks_resubscribe]

  @doc "Check if a method uses SSE streaming."
  @spec streaming_method?(String.t()) :: boolean()
  def streaming_method?(method), do: method in streaming_methods()

  # Error code ↔ error type mapping
  @error_codes %{
    -32_700 => :parse_error,
    -32_600 => :invalid_request,
    -32_601 => :method_not_found,
    -32_602 => :invalid_params,
    -32_603 => :internal_error,
    -32_000 => :server_error,
    -32_001 => :task_not_found,
    -32_002 => :task_not_cancelable,
    -32_003 => :push_notification_not_supported,
    -32_004 => :unsupported_operation,
    -32_005 => :unsupported_content_type,
    -32_006 => :invalid_agent_response,
    -32_007 => :extended_card_not_configured,
    -31_401 => :unauthenticated,
    -31_403 => :unauthorized
  }

  @error_types_to_codes Map.new(@error_codes, fn {code, type} -> {type, code} end)

  @doc "Get the JSON-RPC error code for an error type."
  @spec error_code(A2AEx.Error.error_type()) :: integer()
  def error_code(type), do: Map.fetch!(@error_types_to_codes, type)

  @doc "Get the error type for a JSON-RPC error code."
  @spec error_type(integer()) :: A2AEx.Error.error_type()
  def error_type(code), do: Map.get(@error_codes, code, :internal_error)

  # --- Request ---

  @type request :: %{
          jsonrpc: String.t(),
          method: String.t(),
          params: map() | nil,
          id: term()
        }

  @doc """
  Decode a JSON-RPC request from a JSON string.
  Returns `{:ok, request_map}` or `{:error, A2AEx.Error.t()}`.
  """
  @spec decode_request(String.t()) ::
          {:ok, request()} | {:error, A2AEx.Error.t(), term()}
  def decode_request(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} -> validate_request(map)
      {:error, _} -> {:error, A2AEx.Error.new(:parse_error, "malformed JSON"), nil}
    end
  end

  @doc """
  Decode a JSON-RPC request from an already-decoded map.
  """
  @spec decode_request_map(map()) ::
          {:ok, request()} | {:error, A2AEx.Error.t(), term()}
  def decode_request_map(map) when is_map(map), do: validate_request(map)

  defp validate_request(map) do
    raw_id = map["id"]
    safe_id = if valid_id?(raw_id), do: raw_id, else: nil

    cond do
      map["jsonrpc"] != @version ->
        {:error, A2AEx.Error.new(:invalid_request, "invalid jsonrpc version"), safe_id}

      !is_binary(map["method"]) || map["method"] == "" ->
        {:error, A2AEx.Error.new(:invalid_request, "missing or invalid method"), safe_id}

      !valid_id?(raw_id) ->
        {:error, A2AEx.Error.new(:invalid_request, "invalid request id"), nil}

      true ->
        {:ok,
         %{
           jsonrpc: @version,
           method: map["method"],
           params: map["params"],
           id: raw_id
         }}
    end
  end

  defp valid_id?(nil), do: true
  defp valid_id?(id) when is_binary(id), do: true
  defp valid_id?(id) when is_number(id), do: true
  defp valid_id?(_), do: false

  # --- Response ---

  @doc """
  Encode a successful JSON-RPC response to a JSON string.
  """
  @spec encode_response(term(), term()) :: String.t()
  def encode_response(result, id) do
    %{"jsonrpc" => @version, "id" => id, "result" => result}
    |> Jason.encode!()
  end

  @doc """
  Encode a JSON-RPC response map (for use with Plug or other transports).
  """
  @spec response_map(term(), term()) :: map()
  def response_map(result, id) do
    %{"jsonrpc" => @version, "id" => id, "result" => result}
  end

  # --- Error Response ---

  @doc """
  Encode a JSON-RPC error response from an A2AEx.Error.
  """
  @spec encode_error(A2AEx.Error.t(), term()) :: String.t()
  def encode_error(%A2AEx.Error{} = error, id) do
    error_map(error, id) |> Jason.encode!()
  end

  @doc """
  Encode a JSON-RPC error response from an error type atom.
  """
  @spec encode_error(A2AEx.Error.error_type(), String.t(), term()) :: String.t()
  def encode_error(type, message, id) when is_atom(type) do
    A2AEx.Error.new(type, message) |> encode_error(id)
  end

  @doc """
  Build a JSON-RPC error response map.
  """
  @spec error_map(A2AEx.Error.t(), term()) :: map()
  def error_map(%A2AEx.Error{} = error, id) do
    err = %{"code" => error_code(error.type), "message" => error.message}
    err = if error.details, do: Map.put(err, "data", error.details), else: err
    %{"jsonrpc" => @version, "id" => id, "error" => err}
  end

  @doc """
  Convert any error to a JSON-RPC error map. Wraps unknown errors as internal_error.
  """
  @spec to_error_map(term(), term()) :: map()
  def to_error_map(%A2AEx.Error{} = error, id), do: error_map(error, id)

  def to_error_map(error, id) when is_atom(error) do
    msg = A2AEx.Error.default_message(error)
    error_map(A2AEx.Error.new(error, msg), id)
  rescue
    _ -> error_map(A2AEx.Error.new(:internal_error, "internal error"), id)
  end

  def to_error_map(_error, id) do
    error_map(A2AEx.Error.new(:internal_error, "internal error"), id)
  end

  @doc """
  Parse a JSON-RPC error from a response map (for client-side use).
  """
  @spec parse_error(map()) :: A2AEx.Error.t()
  def parse_error(%{"code" => code, "message" => message} = err) do
    type = error_type(code)
    A2AEx.Error.new(type, message, err["data"])
  end
end
