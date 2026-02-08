defmodule A2AEx.ClientTest do
  use ExUnit.Case, async: false

  alias A2AEx.{Client, TaskStore, EventQueue, RequestHandler}
  alias A2AEx.{Message, TextPart, TaskStatusUpdateEvent, TaskArtifactUpdateEvent, Artifact, AgentCard}

  # --- Test executor ---

  defmodule ClientEchoExecutor do
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

  defmodule ArtifactExecutor do
    @behaviour A2AEx.AgentExecutor

    @impl true
    def execute(%A2AEx.RequestContext{} = ctx, task_id) do
      working = TaskStatusUpdateEvent.new(task_id, ctx.context_id, :working)
      EventQueue.enqueue(task_id, working)

      artifact = %Artifact{id: "art-1", parts: [%TextPart{text: "artifact output"}]}

      artifact_event = %TaskArtifactUpdateEvent{
        task_id: task_id,
        context_id: ctx.context_id,
        artifact: artifact
      }

      EventQueue.enqueue(task_id, artifact_event)

      completed = TaskStatusUpdateEvent.new(task_id, ctx.context_id, :completed)
      EventQueue.enqueue(task_id, %{completed | final: true})
      :ok
    end

    @impl true
    def cancel(_ctx, _task_id), do: :ok
  end

  # --- Setup: start real HTTP server ---

  setup do
    {:ok, store} = TaskStore.InMemory.start_link()

    card = %AgentCard{
      name: "Test Agent",
      description: "A test agent for client tests",
      url: "http://localhost",
      version: "1.0"
    }

    handler = %RequestHandler{
      executor: ClientEchoExecutor,
      task_store: {TaskStore.InMemory, store},
      agent_card: card
    }

    {:ok, server_pid} =
      Bandit.start_link(
        plug: {A2AEx.Server, [handler: handler]},
        port: 0,
        ip: :loopback
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server_pid)
    base_url = "http://127.0.0.1:#{port}"

    on_exit(fn ->
      if Process.alive?(server_pid), do: Process.exit(server_pid, :normal)
      Process.sleep(10)
    end)

    %{base_url: base_url, store: store, handler: handler, server_pid: server_pid, port: port}
  end

  defp make_send_params(text) do
    %{
      "message" => %{
        "role" => "user",
        "messageId" => "test-msg-#{System.unique_integer([:positive])}",
        "parts" => [%{"kind" => "text", "text" => text}]
      }
    }
  end

  # --- SSE Parser Tests ---

  describe "A2AEx.Client.SSE" do
    test "parse_chunk with single complete event" do
      data = "data: {\"a\":1}\n\n"
      assert {[%{"a" => 1}], ""} = A2AEx.Client.SSE.parse_chunk(data, "")
    end

    test "parse_chunk with multiple events" do
      data = "data: {\"a\":1}\n\ndata: {\"b\":2}\n\n"
      assert {[%{"a" => 1}, %{"b" => 2}], ""} = A2AEx.Client.SSE.parse_chunk(data, "")
    end

    test "parse_chunk with incomplete event returns buffer" do
      data = "data: {\"a\":1}\n\ndata: {\"b\""
      assert {[%{"a" => 1}], "data: {\"b\""} = A2AEx.Client.SSE.parse_chunk(data, "")
    end

    test "parse_chunk with buffer from previous call" do
      assert {[], buffer} = A2AEx.Client.SSE.parse_chunk("data: {\"x\"", "")
      assert {[%{"x" => 1}], ""} = A2AEx.Client.SSE.parse_chunk(":1}\n\n", buffer)
    end

    test "parse_chunk skips non-data lines" do
      data = "event: update\n\ndata: {\"a\":1}\n\n"
      assert {[%{"a" => 1}], ""} = A2AEx.Client.SSE.parse_chunk(data, "")
    end
  end

  # --- Client Sync Tests ---

  test "new creates client with base_url", _ctx do
    client = Client.new("http://localhost:4000")
    assert client.base_url == "http://localhost:4000"
  end

  test "new strips trailing slash", _ctx do
    client = Client.new("http://localhost:4000/")
    assert client.base_url == "http://localhost:4000"
  end

  test "get_agent_card fetches card", ctx do
    client = Client.new(ctx.base_url)
    assert {:ok, card} = Client.get_agent_card(client)
    assert card.name == "Test Agent"
    assert card.version == "1.0"
  end

  test "send_message returns completed task", ctx do
    client = Client.new(ctx.base_url)
    params = make_send_params("hello")
    assert {:ok, result} = Client.send_message(client, params)
    assert result["status"]["state"] == "completed"
  end

  test "send_message echoes text", ctx do
    client = Client.new(ctx.base_url)
    params = make_send_params("ping")
    assert {:ok, result} = Client.send_message(client, params)
    status_msg = result["status"]["message"]
    assert status_msg != nil
    text = hd(status_msg["parts"])["text"]
    assert text =~ "echo: ping"
  end

  test "get_task retrieves stored task", ctx do
    client = Client.new(ctx.base_url)
    params = make_send_params("test")
    {:ok, result} = Client.send_message(client, params)
    task_id = result["id"]

    assert {:ok, fetched} = Client.get_task(client, %{"id" => task_id})
    assert fetched["id"] == task_id
    assert fetched["status"]["state"] == "completed"
  end

  test "get_task returns error for missing task", ctx do
    client = Client.new(ctx.base_url)
    assert {:error, error} = Client.get_task(client, %{"id" => "nonexistent"})
    assert is_map(error)
  end

  test "cancel_task on nonexistent returns error", ctx do
    client = Client.new(ctx.base_url)
    assert {:error, _} = Client.cancel_task(client, %{"id" => "no-such-task"})
  end

  # --- Streaming Tests ---

  test "stream_message returns event stream", ctx do
    client = Client.new(ctx.base_url)
    params = make_send_params("stream test")

    assert {:ok, stream} = Client.stream_message(client, params)
    events = Enum.to_list(stream)

    # SSE now sends Task objects (not raw events)
    task_events = Enum.filter(events, &match?(%A2AEx.Task{}, &1))
    assert length(task_events) >= 2

    states = Enum.map(task_events, & &1.status.state)
    assert :working in states
    assert :completed in states
  end

  test "stream_message with artifact executor", _ctx do
    # Restart server with artifact executor
    {:ok, store} = TaskStore.InMemory.start_link()

    handler = %RequestHandler{
      executor: ArtifactExecutor,
      task_store: {TaskStore.InMemory, store},
      agent_card: %AgentCard{name: "Artifact Agent", description: "test", url: "http://localhost", version: "1.0"}
    }

    {:ok, server_pid} =
      Bandit.start_link(
        plug: {A2AEx.Server, [handler: handler]},
        port: 0,
        ip: :loopback
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server_pid)
    client = Client.new("http://127.0.0.1:#{port}")

    params = make_send_params("artifacts")
    assert {:ok, stream} = Client.stream_message(client, params)
    events = Enum.to_list(stream)

    # SSE now sends Task objects with accumulated artifacts
    task_with_artifacts = Enum.filter(events, fn
      %A2AEx.Task{artifacts: arts} when is_list(arts) and arts != [] -> true
      _ -> false
    end)
    assert task_with_artifacts != []

    if Process.alive?(server_pid), do: Process.exit(server_pid, :normal)
  end

  # --- Client with req_options ---

  test "client passes req_options through", ctx do
    client = Client.new(ctx.base_url, receive_timeout: 5_000)
    params = make_send_params("opts test")
    assert {:ok, result} = Client.send_message(client, params)
    assert result["status"]["state"] == "completed"
  end
end
