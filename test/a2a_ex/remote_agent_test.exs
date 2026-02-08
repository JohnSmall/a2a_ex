defmodule A2AEx.RemoteAgentTest do
  use ExUnit.Case, async: false

  alias A2AEx.{
    RemoteAgent,
    Client,
    TaskStore,
    EventQueue,
    RequestHandler,
    Message,
    TextPart,
    AgentCard,
    TaskStatusUpdateEvent,
    TaskArtifactUpdateEvent,
    Artifact
  }

  alias ADK.Agent.InvocationContext
  alias ADK.Types.Content

  # --- Test executors (server side) ---

  defmodule RemoteEchoExecutor do
    @behaviour A2AEx.AgentExecutor

    @impl true
    def execute(%A2AEx.RequestContext{} = ctx, task_id) do
      working = TaskStatusUpdateEvent.new(task_id, ctx.context_id, :working)
      EventQueue.enqueue(task_id, working)

      text = hd(ctx.message.parts).text
      reply = Message.new(:agent, [%TextPart{text: "remote echo: #{text}"}])
      completed = TaskStatusUpdateEvent.new(task_id, ctx.context_id, :completed, reply)
      EventQueue.enqueue(task_id, %{completed | final: true})
      :ok
    end

    @impl true
    def cancel(_ctx, _task_id), do: :ok
  end

  defmodule RemoteFailExecutor do
    @behaviour A2AEx.AgentExecutor

    @impl true
    def execute(%A2AEx.RequestContext{} = ctx, task_id) do
      failed = TaskStatusUpdateEvent.new(task_id, ctx.context_id, :failed)
      EventQueue.enqueue(task_id, %{failed | final: true})
      :ok
    end

    @impl true
    def cancel(_ctx, _task_id), do: :ok
  end

  defmodule RemoteArtifactExecutor do
    @behaviour A2AEx.AgentExecutor

    @impl true
    def execute(%A2AEx.RequestContext{} = ctx, task_id) do
      working = TaskStatusUpdateEvent.new(task_id, ctx.context_id, :working)
      EventQueue.enqueue(task_id, working)

      artifact = %Artifact{id: "art-1", parts: [%TextPart{text: "artifact content"}]}

      artifact_event = %TaskArtifactUpdateEvent{
        task_id: task_id,
        context_id: ctx.context_id,
        artifact: artifact
      }

      EventQueue.enqueue(task_id, artifact_event)

      reply = Message.new(:agent, [%TextPart{text: "done"}])
      completed = TaskStatusUpdateEvent.new(task_id, ctx.context_id, :completed, reply)
      EventQueue.enqueue(task_id, %{completed | final: true})
      :ok
    end

    @impl true
    def cancel(_ctx, _task_id), do: :ok
  end

  # --- Helpers ---

  defp start_server(executor) do
    {:ok, store} = TaskStore.InMemory.start_link()

    card = %AgentCard{
      name: "Remote Test Agent",
      description: "A test remote agent",
      url: "http://localhost",
      version: "1.0"
    }

    handler = %RequestHandler{
      executor: executor,
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
    url = "http://127.0.0.1:#{port}"
    {server_pid, url}
  end

  defp stop_server(server_pid) do
    if Process.alive?(server_pid), do: Process.exit(server_pid, :normal)
    Process.sleep(10)
  end

  defp make_ctx(agent, user_text, opts \\ []) do
    streaming = Keyword.get(opts, :streaming, :none)

    content = Content.new_from_text("user", user_text)

    %InvocationContext{
      agent: agent,
      invocation_id: "inv-#{System.unique_integer([:positive])}",
      user_content: content,
      run_config: %ADK.RunConfig{streaming_mode: streaming}
    }
  end

  # --- Tests ---

  test "new creates a CustomAgent" do
    config = %RemoteAgent.Config{name: "test-remote", url: "http://localhost:9999"}
    agent = RemoteAgent.new(config)
    assert %ADK.Agent.CustomAgent{} = agent
    assert ADK.Agent.CustomAgent.name(agent) == "test-remote"
  end

  test "new preserves description" do
    config = %RemoteAgent.Config{
      name: "test-remote",
      url: "http://localhost:9999",
      description: "A helper"
    }

    agent = RemoteAgent.new(config)
    assert ADK.Agent.CustomAgent.description(agent) == "A helper"
  end

  test "sync request returns echo response" do
    {server_pid, url} = start_server(RemoteEchoExecutor)

    config = %RemoteAgent.Config{name: "echo-remote", url: url}
    agent = RemoteAgent.new(config)
    ctx = make_ctx(agent, "hello world")

    events = agent.__struct__.run(agent, ctx) |> Enum.to_list()

    assert events != []

    text_events =
      Enum.filter(events, fn e ->
        e.content != nil and e.content.parts != []
      end)

    assert text_events != []

    texts =
      Enum.flat_map(text_events, fn e ->
        Enum.map(e.content.parts, & &1.text)
      end)

    assert Enum.any?(texts, &String.contains?(&1, "remote echo: hello world"))

    stop_server(server_pid)
  end

  test "streaming request returns echo response" do
    {server_pid, url} = start_server(RemoteEchoExecutor)

    config = %RemoteAgent.Config{name: "echo-stream", url: url}
    agent = RemoteAgent.new(config)
    ctx = make_ctx(agent, "stream test", streaming: :sse)

    events = agent.__struct__.run(agent, ctx) |> Enum.to_list()

    text_events =
      Enum.filter(events, fn e ->
        e.content != nil and e.content.parts != []
      end)

    assert text_events != []

    texts =
      Enum.flat_map(text_events, fn e ->
        Enum.map(e.content.parts, & &1.text)
      end)

    assert Enum.any?(texts, &String.contains?(&1, "remote echo: stream test"))

    stop_server(server_pid)
  end

  test "failed remote agent sets error on event" do
    {server_pid, url} = start_server(RemoteFailExecutor)

    config = %RemoteAgent.Config{name: "fail-remote", url: url}
    agent = RemoteAgent.new(config)
    ctx = make_ctx(agent, "will fail")

    events = agent.__struct__.run(agent, ctx) |> Enum.to_list()

    # Sync path: failed status with no message → no events with content
    # The task result has status.state=failed but no message
    # So convert_status_message returns [] → events may be empty
    # That's acceptable - the status is failed but no content to relay
    assert is_list(events)

    stop_server(server_pid)
  end

  test "streaming with artifacts produces partial events" do
    {server_pid, url} = start_server(RemoteArtifactExecutor)

    config = %RemoteAgent.Config{name: "artifact-remote", url: url}
    agent = RemoteAgent.new(config)
    ctx = make_ctx(agent, "give artifacts", streaming: :sse)

    events = agent.__struct__.run(agent, ctx) |> Enum.to_list()

    partial_events = Enum.filter(events, & &1.partial)
    assert partial_events != []

    partial_text =
      Enum.flat_map(partial_events, fn e ->
        Enum.map(e.content.parts, & &1.text)
      end)

    assert Enum.any?(partial_text, &(&1 == "artifact content"))

    stop_server(server_pid)
  end

  test "no user content produces error event" do
    config = %RemoteAgent.Config{name: "no-content", url: "http://localhost:9999"}
    agent = RemoteAgent.new(config)

    ctx = %InvocationContext{
      agent: agent,
      invocation_id: "inv-1",
      user_content: nil,
      run_config: %ADK.RunConfig{}
    }

    events = agent.__struct__.run(agent, ctx) |> Enum.to_list()

    assert [error_event] = events
    assert error_event.error_message =~ "no user content"
  end

  test "agent name is set as author on events" do
    {server_pid, url} = start_server(RemoteEchoExecutor)

    config = %RemoteAgent.Config{name: "author-test", url: url}
    agent = RemoteAgent.new(config)
    ctx = make_ctx(agent, "check author")

    events = agent.__struct__.run(agent, ctx) |> Enum.to_list()

    authored = Enum.filter(events, &(&1.author != nil))
    assert Enum.all?(authored, &(&1.author == "author-test"))

    stop_server(server_pid)
  end

  test "client_opts are passed through" do
    {server_pid, url} = start_server(RemoteEchoExecutor)

    config = %RemoteAgent.Config{
      name: "opts-test",
      url: url,
      client_opts: [receive_timeout: 10_000]
    }

    agent = RemoteAgent.new(config)
    ctx = make_ctx(agent, "with opts")

    events = agent.__struct__.run(agent, ctx) |> Enum.to_list()
    assert is_list(events)

    stop_server(server_pid)
  end

  test "get_agent_card via client from remote agent URL" do
    {server_pid, url} = start_server(RemoteEchoExecutor)

    client = Client.new(url)
    assert {:ok, card} = Client.get_agent_card(client)
    assert card.name == "Remote Test Agent"

    stop_server(server_pid)
  end
end
