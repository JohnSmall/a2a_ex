defmodule A2AEx.ServerTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias A2AEx.{Server, RequestHandler, TaskStore, EventQueue}
  alias A2AEx.{Message, TextPart, Task, TaskStatus, TaskStatusUpdateEvent, AgentCard}

  # --- Test executor ---

  defmodule ServerEchoExecutor do
    @behaviour A2AEx.AgentExecutor

    @impl true
    def execute(%A2AEx.RequestContext{} = ctx, task_id) do
      working = TaskStatusUpdateEvent.new(task_id, ctx.context_id, :working)
      EventQueue.enqueue(task_id, working)

      reply = Message.new(:agent, [%TextPart{text: "echo: #{hd(ctx.message.parts).text}"}])
      completed = TaskStatusUpdateEvent.new(task_id, ctx.context_id, :completed, reply)
      EventQueue.enqueue(task_id, %{completed | final: true})
      :ok
    end

    @impl true
    def cancel(_ctx, _task_id), do: :ok
  end

  setup do
    {:ok, store} = TaskStore.InMemory.start_link()

    card = %AgentCard{
      name: "Test Agent",
      description: "A test agent",
      url: "https://agent.test",
      version: "1.0"
    }

    handler = %RequestHandler{
      executor: ServerEchoExecutor,
      task_store: {TaskStore.InMemory, store},
      agent_card: card
    }

    %{handler: handler, store: store}
  end

  defp call_server(conn, handler) do
    Server.call(conn, handler: handler)
  end

  defp post_jsonrpc(handler, method, params, id \\ 1) do
    body =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "method" => method,
        "params" => params,
        "id" => id
      })

    conn(:post, "/", body)
    |> put_req_header("content-type", "application/json")
    |> call_server(handler)
  end

  # --- Agent card tests ---

  test "GET /.well-known/agent.json returns agent card", %{handler: handler} do
    conn = conn(:get, "/.well-known/agent.json") |> call_server(handler)

    assert conn.status == 200
    assert {"content-type", "application/json; charset=utf-8"} in conn.resp_headers
    body = Jason.decode!(conn.resp_body)
    assert body["name"] == "Test Agent"
    assert body["version"] == "1.0"
  end

  test "GET /.well-known/agent.json returns 404 when no card configured", %{store: store} do
    handler = %RequestHandler{
      executor: ServerEchoExecutor,
      task_store: {TaskStore.InMemory, store}
    }

    conn = conn(:get, "/.well-known/agent.json") |> call_server(handler)
    assert conn.status == 404
  end

  # --- JSON-RPC dispatch tests ---

  test "POST / with tasks/get returns task", %{handler: handler, store: store} do
    task = Task.new_submitted(Message.new(:user, [%TextPart{text: "hi"}]), task_id: "srv-t1")
    TaskStore.InMemory.save(store, task)

    conn = post_jsonrpc(handler, "tasks/get", %{"id" => "srv-t1"})

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["jsonrpc"] == "2.0"
    assert body["id"] == 1
    assert body["result"]["id"] == "srv-t1"
    assert body["result"]["kind"] == "task"
  end

  test "POST / with unknown method returns error", %{handler: handler} do
    conn = post_jsonrpc(handler, "unknown/method", %{})

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["error"]["code"] == -32_601
    assert body["error"]["message"] == "unknown method"
  end

  test "POST / with malformed JSON returns parse error", %{handler: handler} do
    conn =
      conn(:post, "/", "not json")
      |> put_req_header("content-type", "application/json")
      |> call_server(handler)

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["error"]["code"] == -32_700
  end

  test "POST / with invalid jsonrpc version returns error", %{handler: handler} do
    body = Jason.encode!(%{"jsonrpc" => "1.0", "method" => "tasks/get", "params" => %{}, "id" => 1})

    conn =
      conn(:post, "/", body)
      |> put_req_header("content-type", "application/json")
      |> call_server(handler)

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["error"] != nil
  end

  test "POST / message/send returns task result", %{handler: handler} do
    params = %{
      "message" => %{
        "role" => "user",
        "parts" => [%{"kind" => "text", "text" => "hello"}],
        "messageId" => "msg-srv-1"
      }
    }

    conn = post_jsonrpc(handler, "message/send", params)

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["result"]["kind"] == "task"
    assert body["result"]["status"]["state"] == "completed"
  end

  test "POST / tasks/cancel returns canceled task", %{handler: handler, store: store} do
    task = %Task{
      id: "cancel-srv-1",
      context_id: "ctx-1",
      status: %TaskStatus{state: :working},
      history: [Message.new(:user, [%TextPart{text: "work"}])]
    }

    TaskStore.InMemory.save(store, task)

    conn = post_jsonrpc(handler, "tasks/cancel", %{"id" => "cancel-srv-1"})

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["result"]["status"]["state"] == "canceled"
  end

  # --- SSE streaming tests ---

  test "POST / message/stream returns SSE response", %{handler: handler} do
    params = %{
      "message" => %{
        "role" => "user",
        "parts" => [%{"kind" => "text", "text" => "stream test"}],
        "messageId" => "msg-sse-1"
      }
    }

    conn = post_jsonrpc(handler, "message/stream", params)

    assert conn.status == 200

    # Check SSE headers
    assert {"content-type", "text/event-stream"} in conn.resp_headers

    # Check SSE body has data events
    body = collect_chunked_body(conn)
    assert body =~ "data:"
    events = parse_sse_events(body)
    assert events != []
  end

  test "POST / unknown route returns 404", %{handler: handler} do
    conn = conn(:get, "/unknown") |> call_server(handler)
    assert conn.status == 404
  end

  # --- Helpers ---

  defp collect_chunked_body(conn) do
    # For Plug.Test, chunked body is available in resp_body or chunks
    case conn.resp_body do
      nil ->
        conn
        |> Map.get(:chunks, [])
        |> Enum.join()

      body ->
        body
    end
  end

  defp parse_sse_events(body) do
    body
    |> String.split("\n\n", trim: true)
    |> Enum.filter(&String.starts_with?(&1, "data:"))
    |> Enum.map(fn line ->
      line
      |> String.trim_leading("data: ")
      |> String.trim_leading("data:")
      |> Jason.decode!()
    end)
  end
end
