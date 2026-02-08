defmodule A2AEx.IntegrationTest do
  use ExUnit.Case, async: false

  alias A2AEx.{
    Client,
    TaskStore,
    PushConfigStore,
    RequestHandler,
    AgentCard,
    AgentCapabilities,
    ADKExecutor,
    RemoteAgent,
    PushSender,
    TaskStatusUpdateEvent,
    TaskArtifactUpdateEvent
  }

  alias ADK.Agent.{CustomAgent, Config, InvocationContext, SequentialAgent}
  alias ADK.Types.Content
  alias ADK.Event

  # ── ADK Infrastructure Helpers ──────────────────────────────────────

  defp make_session_service do
    name = :"integ_session_#{System.unique_integer([:positive])}"
    {:ok, svc} = ADK.Session.InMemory.start_link(name: name)
    svc
  end

  defp make_runner(agent) do
    svc = make_session_service()
    {:ok, runner} = ADK.Runner.new(app_name: "integ_test", root_agent: agent, session_service: svc)
    runner
  end

  defp make_adk_config(runner) do
    %ADKExecutor.Config{runner: runner, app_name: "integ_test"}
  end

  # ── Agent Constructors ─────────────────────────────────────────────

  defp make_echo_agent do
    CustomAgent.new(%Config{
      name: "echo-agent",
      description: "Echoes a greeting",
      run: fn _ctx ->
        [Event.new(author: "echo-agent", content: Content.new_from_text("model", "Hello from echo!"))]
      end
    })
  end

  defp make_multi_event_agent do
    CustomAgent.new(%Config{
      name: "multi-agent",
      description: "Emits two events",
      run: fn _ctx ->
        [
          Event.new(author: "multi-agent", content: Content.new_from_text("model", "Part one")),
          Event.new(author: "multi-agent", content: Content.new_from_text("model", "Part two"))
        ]
      end
    })
  end

  defp make_error_agent do
    CustomAgent.new(%Config{
      name: "error-agent",
      description: "Always raises",
      run: fn _ctx ->
        raise "intentional test error"
      end
    })
  end

  defp make_escalation_agent do
    CustomAgent.new(%Config{
      name: "escalation-agent",
      description: "Escalates",
      run: fn _ctx ->
        [
          Event.new(
            author: "escalation-agent",
            content: Content.new_from_text("model", "Need human input"),
            actions: %ADK.Event.Actions{escalate: true}
          )
        ]
      end
    })
  end

  defp make_slow_agent do
    CustomAgent.new(%Config{
      name: "slow-agent",
      description: "Emits events with delays",
      run: fn _ctx ->
        Stream.resource(
          fn -> 1 end,
          fn
            n when n > 3 ->
              {:halt, n}

            n ->
              Process.sleep(500)
              event = Event.new(author: "slow-agent", content: Content.new_from_text("model", "chunk #{n}"))
              {[event], n + 1}
          end,
          fn _ -> :ok end
        )
      end
    })
  end

  defp make_local_agent(name, text) do
    CustomAgent.new(%Config{
      name: name,
      description: "Local agent: #{name}",
      run: fn _ctx ->
        [Event.new(author: name, content: Content.new_from_text("model", text))]
      end
    })
  end

  # ── Server Helpers ─────────────────────────────────────────────────

  defp start_server(adk_config, opts \\ []) do
    {:ok, store} = TaskStore.InMemory.start_link()
    push_config_store = Keyword.get(opts, :push_config_store)
    push_sender = Keyword.get(opts, :push_sender)

    handler = %RequestHandler{
      executor: {ADKExecutor, adk_config},
      task_store: {TaskStore.InMemory, store},
      agent_card: default_card(),
      push_config_store: push_config_store,
      push_sender: push_sender
    }

    {:ok, server_pid} =
      Bandit.start_link(
        plug: {A2AEx.Server, [handler: handler]},
        port: 0,
        ip: :loopback
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server_pid)
    url = "http://127.0.0.1:#{port}"
    {server_pid, url, store}
  end

  defp stop_server(pid) do
    if Process.alive?(pid), do: Process.exit(pid, :normal)
    Process.sleep(10)
  end

  defp default_card do
    %AgentCard{
      name: "Integration Test Agent",
      description: "An agent for integration tests",
      url: "http://localhost",
      version: "1.0",
      capabilities: %AgentCapabilities{streaming: true}
    }
  end

  # ── Param Builders ─────────────────────────────────────────────────

  defp send_params(text) do
    %{
      "message" => %{
        "role" => "user",
        "parts" => [%{"kind" => "text", "text" => text}]
      }
    }
  end

  defp send_params(text, context_id) do
    %{
      "message" => %{
        "role" => "user",
        "parts" => [%{"kind" => "text", "text" => text}],
        "contextId" => context_id
      }
    }
  end

  # ── WebhookReceiver (for push test) ────────────────────────────────

  defmodule WebhookReceiver do
    @behaviour Plug

    import Plug.Conn

    def init(opts), do: opts

    def call(conn, opts) do
      collector = Keyword.fetch!(opts, :collector)
      {:ok, body, conn} = read_body(conn)
      decoded = Jason.decode!(body)
      Agent.update(collector, fn reqs -> [decoded | reqs] end)
      send_resp(conn, 200, "ok")
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # Group 1: Server-Client with ADK Agent
  # ═══════════════════════════════════════════════════════════════════

  describe "server-client with ADK agent" do
    test "sync message send returns completed task" do
      agent = make_echo_agent()
      runner = make_runner(agent)
      config = make_adk_config(runner)
      {pid, url, _store} = start_server(config)

      on_exit(fn -> stop_server(pid) end)

      client = Client.new(url)
      {:ok, result} = Client.send_message(client, send_params("hi"))

      assert result["status"]["state"] == "completed"
      assert result["id"] != nil

      # Verify artifact has our text
      artifacts = result["artifacts"] || []
      assert artifacts != []
      texts = extract_artifact_texts(artifacts)
      assert Enum.any?(texts, &String.contains?(&1, "Hello from echo!"))
    end

    test "streaming message send returns event stream" do
      agent = make_echo_agent()
      runner = make_runner(agent)
      config = make_adk_config(runner)
      {pid, url, _store} = start_server(config)

      on_exit(fn -> stop_server(pid) end)

      client = Client.new(url)
      {:ok, stream} = Client.stream_message(client, send_params("stream hi"))
      events = Enum.to_list(stream)

      status_events = Enum.filter(events, &match?(%TaskStatusUpdateEvent{}, &1))
      states = Enum.map(status_events, & &1.status.state)
      assert :working in states
      assert :completed in states

      # Final event should have final: true
      final = Enum.find(status_events, & &1.final)
      assert final != nil
      assert final.status.state == :completed
    end

    test "multi-event agent produces append artifacts" do
      agent = make_multi_event_agent()
      runner = make_runner(agent)
      config = make_adk_config(runner)
      {pid, url, _store} = start_server(config)

      on_exit(fn -> stop_server(pid) end)

      client = Client.new(url)
      {:ok, stream} = Client.stream_message(client, send_params("multi"))
      events = Enum.to_list(stream)

      artifact_events = Enum.filter(events, &match?(%TaskArtifactUpdateEvent{}, &1))

      # First artifact: append: false, subsequent: append: true
      content_artifacts = Enum.reject(artifact_events, & &1.last_chunk)
      assert length(content_artifacts) >= 2

      first = hd(content_artifacts)
      assert first.append == false

      rest = tl(content_artifacts)
      assert Enum.all?(rest, & &1.append == true)

      # All share the same artifact_id
      ids = Enum.map(content_artifacts, & &1.artifact.id) |> Enum.uniq()
      assert length(ids) == 1
    end

    test "agent error results in failed task" do
      agent = make_error_agent()
      runner = make_runner(agent)
      config = make_adk_config(runner)
      {pid, url, _store} = start_server(config)

      on_exit(fn -> stop_server(pid) end)

      client = Client.new(url)
      {:ok, result} = Client.send_message(client, send_params("fail"))

      assert result["status"]["state"] == "failed"
    end

    test "escalation results in input-required state" do
      agent = make_escalation_agent()
      runner = make_runner(agent)
      config = make_adk_config(runner)
      {pid, url, _store} = start_server(config)

      on_exit(fn -> stop_server(pid) end)

      client = Client.new(url)
      {:ok, result} = Client.send_message(client, send_params("escalate"))

      assert result["status"]["state"] == "input-required"
    end

    test "agent card served via client" do
      agent = make_echo_agent()
      runner = make_runner(agent)
      config = make_adk_config(runner)
      {pid, url, _store} = start_server(config)

      on_exit(fn -> stop_server(pid) end)

      client = Client.new(url)
      {:ok, card} = Client.get_agent_card(client)

      assert card.name == "Integration Test Agent"
      assert card.capabilities.streaming == true
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # Group 2: Task Lifecycle
  # ═══════════════════════════════════════════════════════════════════

  describe "task lifecycle" do
    test "get task after completion" do
      agent = make_echo_agent()
      runner = make_runner(agent)
      config = make_adk_config(runner)
      {pid, url, _store} = start_server(config)

      on_exit(fn -> stop_server(pid) end)

      client = Client.new(url)
      {:ok, result} = Client.send_message(client, send_params("lifecycle"))
      task_id = result["id"]

      {:ok, fetched} = Client.get_task(client, %{"id" => task_id})
      assert fetched["id"] == task_id
      assert fetched["status"]["state"] == "completed"
    end

    test "multi-turn conversation resumes task" do
      agent = make_echo_agent()
      runner = make_runner(agent)
      config = make_adk_config(runner)
      {pid, url, _store} = start_server(config)

      on_exit(fn -> stop_server(pid) end)

      client = Client.new(url)
      context_id = "shared-ctx-#{System.unique_integer([:positive])}"

      # First turn
      {:ok, result1} = Client.send_message(client, send_params("turn 1", context_id))
      assert result1["status"]["state"] == "completed"
      ctx1 = result1["contextId"]

      # Second turn with same contextId
      {:ok, result2} = Client.send_message(client, send_params("turn 2", context_id))
      assert result2["status"]["state"] == "completed"
      ctx2 = result2["contextId"]

      # Both should share the same contextId
      assert ctx1 == ctx2
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # Group 3: Task Cancellation
  # ═══════════════════════════════════════════════════════════════════

  describe "task cancellation" do
    test "cancel a running streaming task" do
      agent = make_slow_agent()
      runner = make_runner(agent)
      config = make_adk_config(runner)
      {pid, url, _store} = start_server(config)

      on_exit(fn -> stop_server(pid) end)

      client = Client.new(url)
      {:ok, stream} = Client.stream_message(client, send_params("cancel me"))

      # Take the first event to get the task_id
      first_events = Enum.take(stream, 1)
      assert first_events != []

      first = hd(first_events)
      task_id = first.task_id

      # Cancel the task
      {:ok, canceled} = Client.cancel_task(client, %{"id" => task_id})
      assert canceled["status"]["state"] == "canceled"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # Group 4: Push Notifications
  # ═══════════════════════════════════════════════════════════════════

  describe "push notifications" do
    test "push config CRUD over HTTP" do
      agent = make_echo_agent()
      runner = make_runner(agent)
      config = make_adk_config(runner)

      {:ok, push_store} = PushConfigStore.InMemory.start_link()

      {pid, url, _store} =
        start_server(config,
          push_config_store: {PushConfigStore.InMemory, push_store},
          push_sender: PushSender.HTTP
        )

      on_exit(fn -> stop_server(pid) end)

      client = Client.new(url)

      # First, create a task so we have a valid task_id
      {:ok, result} = Client.send_message(client, send_params("push test"))
      task_id = result["id"]

      # Set push config
      push_params = %{
        "taskId" => task_id,
        "pushNotificationConfig" => %{
          "url" => "http://example.com/webhook"
        }
      }

      {:ok, set_result} = Client.set_push_config(client, push_params)
      assert set_result["taskId"] == task_id
      config_id = set_result["pushNotificationConfig"]["id"]
      assert config_id != nil

      # Get push config
      get_params = %{"id" => task_id, "pushNotificationConfigId" => config_id}
      {:ok, get_result} = Client.get_push_config(client, get_params)
      assert get_result["pushNotificationConfig"]["url"] == "http://example.com/webhook"

      # List push configs
      list_params = %{"id" => task_id}
      {:ok, list_result} = Client.list_push_configs(client, list_params)
      assert is_list(list_result)
      assert length(list_result) == 1

      # Delete push config
      delete_params = %{"id" => task_id, "pushNotificationConfigId" => config_id}
      {:ok, _} = Client.delete_push_config(client, delete_params)

      # Verify deleted
      {:ok, list_after} = Client.list_push_configs(client, list_params)
      assert list_after == []
    end

    test "push sender delivers to webhook" do
      # Start a webhook receiver
      {:ok, collector} = Agent.start_link(fn -> [] end)

      {:ok, webhook_pid} =
        Bandit.start_link(
          plug: {WebhookReceiver, [collector: collector]},
          port: 0,
          ip: :loopback
        )

      {:ok, {_ip, webhook_port}} = ThousandIsland.listener_info(webhook_pid)
      webhook_url = "http://127.0.0.1:#{webhook_port}"

      on_exit(fn ->
        if Process.alive?(webhook_pid), do: Process.exit(webhook_pid, :normal)
        Process.sleep(10)
      end)

      # Build a push config and a task
      push_config = %A2AEx.PushConfig{
        url: webhook_url,
        token: "test-token"
      }

      task = %A2AEx.Task{
        id: "push-task-1",
        context_id: "push-ctx-1",
        status: %A2AEx.TaskStatus{state: :completed, timestamp: DateTime.utc_now()}
      }

      # Send push notification
      assert :ok = PushSender.HTTP.send_push(push_config, task)

      # Verify webhook received the request
      requests = Agent.get(collector, & &1)
      assert length(requests) == 1
      [body] = requests
      assert body["id"] == "push-task-1"
      assert body["status"]["state"] == "completed"
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # Group 5: Remote Agent Integration
  # ═══════════════════════════════════════════════════════════════════

  describe "remote agent integration" do
    test "remote agent sync mode" do
      agent = make_echo_agent()
      runner = make_runner(agent)
      config = make_adk_config(runner)
      {pid, url, _store} = start_server(config)

      on_exit(fn -> stop_server(pid) end)

      # Create a remote agent pointing at the server
      remote_config = %RemoteAgent.Config{name: "remote-echo", url: url}
      remote_agent = RemoteAgent.new(remote_config)

      ctx = make_invocation_ctx(remote_agent, "hello remote", streaming: :none)
      events = remote_agent.__struct__.run(remote_agent, ctx) |> Enum.to_list()

      assert events != []

      texts = extract_event_texts(events)
      assert Enum.any?(texts, &String.contains?(&1, "Hello from echo!"))
    end

    test "remote agent streaming mode" do
      agent = make_echo_agent()
      runner = make_runner(agent)
      config = make_adk_config(runner)
      {pid, url, _store} = start_server(config)

      on_exit(fn -> stop_server(pid) end)

      remote_config = %RemoteAgent.Config{name: "remote-stream", url: url}
      remote_agent = RemoteAgent.new(remote_config)

      ctx = make_invocation_ctx(remote_agent, "hello streaming", streaming: :sse)
      events = remote_agent.__struct__.run(remote_agent, ctx) |> Enum.to_list()

      assert events != []

      texts = extract_event_texts(events)
      assert Enum.any?(texts, &String.contains?(&1, "Hello from echo!"))
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # Group 6: Multi-Agent Orchestration
  # ═══════════════════════════════════════════════════════════════════

  describe "multi-agent orchestration" do
    test "sequential agent with remote sub-agent" do
      # Start a remote server with echo agent
      echo = make_echo_agent()
      echo_runner = make_runner(echo)
      echo_config = make_adk_config(echo_runner)
      {pid, url, _store} = start_server(echo_config)

      on_exit(fn -> stop_server(pid) end)

      # Create a local agent and a remote agent
      local = make_local_agent("local-agent", "local says hi")
      remote_config = %RemoteAgent.Config{name: "remote-sub", url: url}
      remote = RemoteAgent.new(remote_config)

      # Sequential agent: local then remote
      seq = %SequentialAgent{
        name: "seq-orchestrator",
        description: "Runs local then remote",
        sub_agents: [local, remote]
      }

      svc = make_session_service()
      {:ok, runner} = ADK.Runner.new(app_name: "integ_orch", root_agent: seq, session_service: svc)

      content = Content.new_from_text("user", "orchestrate")
      events = ADK.Runner.run(runner, "user1", "sess1", content) |> Enum.to_list()

      # Filter out the user event
      agent_events = Enum.filter(events, fn e -> e.author != "user" end)
      assert agent_events != []

      texts = extract_event_texts(agent_events)

      # Should have output from local agent
      assert Enum.any?(texts, &String.contains?(&1, "local says hi"))

      # Should have output from remote agent (echo response)
      assert Enum.any?(texts, &String.contains?(&1, "Hello from echo!"))
    end
  end

  # ── Shared Helpers ─────────────────────────────────────────────────

  defp make_invocation_ctx(agent, text, opts) do
    streaming = Keyword.get(opts, :streaming, :none)

    %InvocationContext{
      agent: agent,
      invocation_id: "inv-#{System.unique_integer([:positive])}",
      user_content: Content.new_from_text("user", text),
      run_config: %ADK.RunConfig{streaming_mode: streaming}
    }
  end

  defp extract_event_texts(events) do
    Enum.flat_map(events, fn e ->
      case e.content do
        %{parts: parts} when is_list(parts) ->
          Enum.flat_map(parts, fn
            %{text: t} when is_binary(t) -> [t]
            _ -> []
          end)

        _ ->
          []
      end
    end)
  end

  defp extract_artifact_texts(artifacts) do
    Enum.flat_map(artifacts, fn art ->
      (art["parts"] || [])
      |> Enum.flat_map(fn
        %{"text" => t} when is_binary(t) -> [t]
        _ -> []
      end)
    end)
  end
end
