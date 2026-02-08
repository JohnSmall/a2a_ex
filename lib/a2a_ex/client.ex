defmodule A2AEx.Client do
  @moduledoc """
  HTTP client for consuming remote A2A agents.

  Sends JSON-RPC requests over HTTP and parses responses. Supports both
  synchronous methods (message/send, tasks/get, etc.) and streaming methods
  (message/stream, tasks/resubscribe) via SSE.

  ## Usage

      client = A2AEx.Client.new("http://localhost:4000")

      # Get agent card
      {:ok, card} = A2AEx.Client.get_agent_card(client)

      # Send a message
      params = %A2AEx.MessageSendParams{
        message: A2AEx.Message.new(:user, [%A2AEx.TextPart{text: "Hello!"}])
      }
      {:ok, task} = A2AEx.Client.send_message(client, params)

      # Stream a message (returns lazy event stream)
      {:ok, stream} = A2AEx.Client.stream_message(client, params)
      Enum.each(stream, fn event -> IO.inspect(event) end)
  """

  alias A2AEx.Client.SSE

  @type t :: %__MODULE__{
          base_url: String.t(),
          req_options: keyword()
        }

  @enforce_keys [:base_url]
  defstruct [:base_url, req_options: []]

  @agent_card_path "/.well-known/agent.json"
  @content_type_json {"content-type", "application/json"}
  @accept_sse {"accept", "text/event-stream"}

  @doc "Create a new client for the given base URL."
  @spec new(String.t(), keyword()) :: t()
  def new(base_url, opts \\ []) do
    %__MODULE__{
      base_url: String.trim_trailing(base_url, "/"),
      req_options: opts
    }
  end

  # --- Agent Card ---

  @doc "Fetch the agent card from the well-known URL."
  @spec get_agent_card(t()) :: {:ok, A2AEx.AgentCard.t()} | {:error, term()}
  def get_agent_card(%__MODULE__{} = client) do
    url = client.base_url <> @agent_card_path

    case Req.get(url, client.req_options) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        A2AEx.AgentCard.from_map(body)

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        with {:ok, decoded} <- Jason.decode(body) do
          A2AEx.AgentCard.from_map(decoded)
        end

      {:ok, %{status: status}} ->
        {:error, "unexpected status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- Synchronous Methods ---

  @doc "Send a message and wait for the result (message/send)."
  @spec send_message(t(), map() | A2AEx.MessageSendParams.t()) ::
          {:ok, map()} | {:error, term()}
  def send_message(client, params) do
    rpc_call(client, "message/send", to_params_map(params))
  end

  @doc "Get a task by ID (tasks/get)."
  @spec get_task(t(), map() | A2AEx.TaskQueryParams.t()) ::
          {:ok, map()} | {:error, term()}
  def get_task(client, params) do
    rpc_call(client, "tasks/get", to_params_map(params))
  end

  @doc "Cancel a task (tasks/cancel)."
  @spec cancel_task(t(), map() | A2AEx.TaskIDParams.t()) ::
          {:ok, map()} | {:error, term()}
  def cancel_task(client, params) do
    rpc_call(client, "tasks/cancel", to_params_map(params))
  end

  @doc "Set push notification config (tasks/pushNotificationConfig/set)."
  @spec set_push_config(t(), map()) :: {:ok, map()} | {:error, term()}
  def set_push_config(client, params) do
    rpc_call(client, "tasks/pushNotificationConfig/set", to_params_map(params))
  end

  @doc "Get push notification config (tasks/pushNotificationConfig/get)."
  @spec get_push_config(t(), map()) :: {:ok, map()} | {:error, term()}
  def get_push_config(client, params) do
    rpc_call(client, "tasks/pushNotificationConfig/get", to_params_map(params))
  end

  @doc "Delete push notification config (tasks/pushNotificationConfig/delete)."
  @spec delete_push_config(t(), map()) :: {:ok, map()} | {:error, term()}
  def delete_push_config(client, params) do
    rpc_call(client, "tasks/pushNotificationConfig/delete", to_params_map(params))
  end

  @doc "List push notification configs (tasks/pushNotificationConfig/list)."
  @spec list_push_configs(t(), map()) :: {:ok, map()} | {:error, term()}
  def list_push_configs(client, params) do
    rpc_call(client, "tasks/pushNotificationConfig/list", to_params_map(params))
  end

  @doc "Get authenticated extended card (agent/getAuthenticatedExtendedCard)."
  @spec get_extended_card(t()) :: {:ok, map()} | {:error, term()}
  def get_extended_card(client) do
    rpc_call(client, "agent/getAuthenticatedExtendedCard", %{})
  end

  # --- Streaming Methods ---

  @doc """
  Send a message and stream events (message/stream).

  Returns `{:ok, stream}` where `stream` is a lazy `Enumerable` of
  `A2AEx.Event.t()` structs (TaskStatusUpdateEvent, TaskArtifactUpdateEvent, etc.).
  """
  @spec stream_message(t(), map() | A2AEx.MessageSendParams.t()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def stream_message(client, params) do
    rpc_stream(client, "message/stream", to_params_map(params))
  end

  @doc """
  Re-subscribe to a task's event stream (tasks/resubscribe).

  Returns `{:ok, stream}` where `stream` is a lazy `Enumerable` of events.
  """
  @spec resubscribe(t(), map() | A2AEx.TaskIDParams.t()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def resubscribe(client, params) do
    rpc_stream(client, "tasks/resubscribe", to_params_map(params))
  end

  # --- Private: JSON-RPC sync ---

  defp rpc_call(client, method, params) do
    body = encode_request(method, params)

    case post_json(client, body) do
      {:ok, %{status: 200, body: resp_body}} ->
        parse_rpc_response(resp_body)

      {:ok, %{status: status}} ->
        {:error, "unexpected HTTP status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp post_json(client, body) do
    opts =
      Keyword.merge(client.req_options,
        url: client.base_url,
        headers: [@content_type_json],
        body: body
      )

    Req.post(opts)
  end

  defp parse_rpc_response(body) when is_binary(body) do
    with {:ok, decoded} <- Jason.decode(body) do
      parse_rpc_response(decoded)
    end
  end

  defp parse_rpc_response(%{"error" => error}) when is_map(error) do
    {:error, error}
  end

  defp parse_rpc_response(%{"result" => result}) do
    {:ok, result}
  end

  defp parse_rpc_response(other) do
    {:error, "unexpected response: #{inspect(other)}"}
  end

  # --- Private: JSON-RPC streaming ---

  defp rpc_stream(client, method, params) do
    body = encode_request(method, params)
    caller = self()
    ref = make_ref()

    pid =
      spawn_link(fn ->
        stream_request(client, body, caller, ref)
      end)

    stream =
      Stream.resource(
        fn -> {pid, ref, ""} end,
        &stream_next/1,
        fn _ -> :ok end
      )

    {:ok, stream}
  end

  defp stream_request(client, body, caller, ref) do
    opts =
      Keyword.merge(client.req_options,
        url: client.base_url,
        headers: [@content_type_json, @accept_sse],
        body: body,
        into: fn {:data, data}, {req, resp} ->
          send(caller, {:sse_chunk, ref, data})
          {:cont, {req, resp}}
        end
      )

    Req.post(opts)
    send(caller, {:sse_done, ref})
  end

  defp stream_next({pid, ref, buffer}) do
    receive do
      {:sse_chunk, ^ref, data} ->
        {events, remaining} = SSE.parse_chunk(data, buffer)
        decoded = decode_sse_events(events)
        {decoded, {pid, ref, remaining}}

      {:sse_done, ^ref} ->
        {:halt, {pid, ref, buffer}}
    after
      60_000 ->
        {:halt, {pid, ref, buffer}}
    end
  end

  defp decode_sse_events(raw_events) do
    Enum.flat_map(raw_events, fn raw ->
      case extract_result(raw) do
        {:ok, result} -> decode_event_result(result)
        :skip -> []
      end
    end)
  end

  defp extract_result(%{"result" => result}), do: {:ok, result}
  defp extract_result(%{"error" => _}), do: :skip
  defp extract_result(_), do: :skip

  defp decode_event_result(result) when is_map(result) do
    case A2AEx.Event.from_map(result) do
      {:ok, event} -> [event]
      {:error, _} -> []
    end
  end

  defp decode_event_result(_), do: []

  # --- Private: JSON-RPC encoding ---

  defp encode_request(method, params) do
    %{
      "jsonrpc" => "2.0",
      "method" => method,
      "params" => params,
      "id" => A2AEx.ID.new()
    }
    |> Jason.encode!()
  end

  defp to_params_map(%{__struct__: module} = struct) do
    if function_exported?(module, :to_map, 1) do
      module.to_map(struct)
    else
      Map.from_struct(struct)
    end
  end

  defp to_params_map(map) when is_map(map), do: map
end
