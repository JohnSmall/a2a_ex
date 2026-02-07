defmodule A2AEx.Server do
  @moduledoc """
  Plug-based HTTP server for the A2A protocol.

  Provides two endpoints:
  - `GET /.well-known/agent.json` — Serves the agent card
  - `POST /` — JSON-RPC dispatch (sync and streaming)

  ## Usage

      # Create a handler config
      handler = %A2AEx.RequestHandler{
        executor: MyExecutor,
        task_store: {A2AEx.TaskStore.InMemory, store_pid},
        agent_card: %A2AEx.AgentCard{...}
      }

      # Use as a Plug in your application
      plug A2AEx.Server, handler: handler

  ## With Plug.Cowboy

      Plug.Cowboy.http(A2AEx.Server, [handler: handler], port: 4000)
  """

  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{} = conn, opts) do
    handler = Keyword.fetch!(opts, :handler)

    case {conn.method, conn.path_info} do
      {"GET", [".well-known", "agent.json"]} ->
        handle_agent_card(conn, handler)

      {"POST", []} ->
        handle_jsonrpc(conn, handler)

      {"POST", _} ->
        handle_jsonrpc(conn, handler)

      _ ->
        send_resp(conn, 404, "not found")
    end
  end

  # --- Agent card ---

  defp handle_agent_card(conn, handler) do
    case handler.agent_card do
      nil ->
        send_json(conn, 404, %{"error" => "agent card not configured"})

      card ->
        send_json(conn, 200, A2AEx.AgentCard.to_map(card))
    end
  end

  # --- JSON-RPC dispatch ---

  defp handle_jsonrpc(conn, handler) do
    {:ok, body, conn} = read_body(conn)

    case A2AEx.JSONRPC.decode_request(body) do
      {:ok, request} ->
        if A2AEx.JSONRPC.streaming_method?(request.method) do
          handle_streaming(conn, handler, request)
        else
          handle_sync(conn, handler, request)
        end

      {:error, error} ->
        send_jsonrpc_error(conn, error, nil)
    end
  end

  # --- Sync handling ---

  defp handle_sync(conn, handler, request) do
    case A2AEx.RequestHandler.handle(handler, request) do
      {:ok, result} ->
        send_jsonrpc_response(conn, result, request.id)

      {:error, error} ->
        send_jsonrpc_error(conn, error, request.id)

      {:stream, _task_id} ->
        error = A2AEx.Error.new(:internal_error, "unexpected stream response")
        send_jsonrpc_error(conn, error, request.id)
    end
  end

  # --- Streaming handling (SSE) ---

  defp handle_streaming(conn, handler, request) do
    case A2AEx.RequestHandler.handle(handler, request) do
      {:stream, task_id} ->
        conn = start_sse(conn)
        stream_events(conn, task_id, request.id)

      {:error, error} ->
        send_jsonrpc_error(conn, error, request.id)

      {:ok, result} ->
        send_jsonrpc_response(conn, result, request.id)
    end
  end

  defp start_sse(conn) do
    conn
    |> put_resp_header("content-type", "text/event-stream")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header("connection", "keep-alive")
    |> send_chunked(200)
  end

  defp stream_events(conn, task_id, request_id) do
    receive do
      {:a2a_event, ^task_id, event} ->
        event_map = A2AEx.Event.to_map(event)
        resp = A2AEx.JSONRPC.response_map(event_map, request_id)

        case send_sse_event(conn, resp) do
          {:ok, conn} -> stream_events(conn, task_id, request_id)
          {:error, _} -> conn
        end

      {:a2a_done, ^task_id} ->
        conn
    after
      60_000 ->
        error = A2AEx.Error.new(:internal_error, "stream timeout")
        error_resp = A2AEx.JSONRPC.error_map(error, request_id)
        send_sse_event(conn, error_resp)
        conn
    end
  end

  defp send_sse_event(conn, data) do
    json = Jason.encode!(data)
    chunk(conn, "data: #{json}\n\n")
  end

  # --- Response helpers ---

  defp send_jsonrpc_response(conn, result, id) do
    resp = A2AEx.JSONRPC.response_map(result, id)
    send_json(conn, 200, resp)
  end

  defp send_jsonrpc_error(conn, %A2AEx.Error{} = error, id) do
    resp = A2AEx.JSONRPC.error_map(error, id)
    send_json(conn, 200, resp)
  end

  defp send_json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end
end
