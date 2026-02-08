defmodule A2AEx.ADKExecutorTest do
  use ExUnit.Case, async: true

  alias A2AEx.{ADKExecutor, EventQueue, RequestContext, TaskStore, Message, TextPart}
  alias A2AEx.{TaskStatusUpdateEvent, TaskArtifactUpdateEvent}
  alias ADK.Agent.{Config, CustomAgent}
  alias ADK.Event
  alias ADK.Types.Content

  setup do
    prefix = :"test_#{System.unique_integer([:positive])}"
    {:ok, session_svc} = ADK.Session.InMemory.start_link(name: nil, table_prefix: prefix)
    {:ok, store} = TaskStore.InMemory.start_link()

    %{session_svc: session_svc, store: store}
  end

  defp make_agent(name, run_fn) do
    config = %Config{name: name, run: run_fn}
    CustomAgent.new(config)
  end

  defp make_runner(agent, session_svc) do
    {:ok, runner} =
      ADK.Runner.new(app_name: "test", root_agent: agent, session_service: session_svc)

    runner
  end

  defp make_config(runner) do
    %ADKExecutor.Config{runner: runner, app_name: "test"}
  end

  defp make_req_ctx(task_id, context_id, text) do
    %RequestContext{
      task_id: task_id,
      context_id: context_id,
      message: Message.new(:user, [%TextPart{text: text}])
    }
  end

  defp collect_events(task_id, timeout \\ 2000) do
    collect_events_acc(task_id, [], timeout)
  end

  defp collect_events_acc(task_id, acc, timeout) do
    receive do
      {:a2a_event, ^task_id, event} ->
        collect_events_acc(task_id, acc ++ [event], timeout)

      {:a2a_done, ^task_id} ->
        acc
    after
      timeout -> acc
    end
  end

  defp run_executor(config, req_ctx, task_id) do
    {:ok, _} = EventQueue.get_or_create(task_id)
    :ok = EventQueue.subscribe(task_id)

    spawn(fn ->
      try do
        ADKExecutor.execute(config, req_ctx, task_id)
      after
        EventQueue.close(task_id)
      end
    end)

    collect_events(task_id)
  end

  # --- Tests ---

  test "text response: working → artifact → last_chunk → completed", ctx do
    agent =
      make_agent("echo", fn _inv_ctx ->
        [Event.new(author: "echo", content: Content.new_from_text("model", "Hello!"))]
      end)

    config = make_config(make_runner(agent, ctx.session_svc))
    task_id = A2AEx.ID.new()
    req_ctx = make_req_ctx(task_id, "ctx-1", "hi")

    events = run_executor(config, req_ctx, task_id)

    assert [working, artifact, last_chunk, completed] = events
    assert %TaskStatusUpdateEvent{status: %{state: :working}} = working
    assert %TaskArtifactUpdateEvent{artifact: %{parts: [%TextPart{text: "Hello!"}]}, append: false} = artifact
    assert %TaskArtifactUpdateEvent{last_chunk: true, append: true, artifact: %{parts: []}} = last_chunk
    assert %TaskStatusUpdateEvent{status: %{state: :completed}, final: true} = completed
  end

  test "multi-event: append flag and same artifact_id", ctx do
    agent =
      make_agent("multi", fn _inv_ctx ->
        [
          Event.new(author: "multi", content: Content.new_from_text("model", "Part 1")),
          Event.new(author: "multi", content: Content.new_from_text("model", "Part 2"))
        ]
      end)

    config = make_config(make_runner(agent, ctx.session_svc))
    task_id = A2AEx.ID.new()
    req_ctx = make_req_ctx(task_id, "ctx-2", "go")

    events = run_executor(config, req_ctx, task_id)

    artifact_events =
      Enum.filter(events, fn
        %TaskArtifactUpdateEvent{last_chunk: false} -> true
        _ -> false
      end)

    assert [first, second] = artifact_events
    assert first.append == false
    assert second.append == true
    assert first.artifact.id == second.artifact.id
  end

  test "error event → :failed final status", ctx do
    agent =
      make_agent("err", fn _inv_ctx ->
        [Event.new(author: "err", error_code: "500", error_message: "server error")]
      end)

    config = make_config(make_runner(agent, ctx.session_svc))
    task_id = A2AEx.ID.new()
    req_ctx = make_req_ctx(task_id, "ctx-3", "fail")

    events = run_executor(config, req_ctx, task_id)

    final = List.last(events)
    assert %TaskStatusUpdateEvent{status: %{state: :failed}, final: true} = final
    assert final.status.message != nil
    assert hd(final.status.message.parts).text == "server error"
  end

  test "escalation → :input_required final status", ctx do
    agent =
      make_agent("esc", fn _inv_ctx ->
        [Event.new(
          author: "esc",
          content: Content.new_from_text("model", "Need help"),
          actions: %ADK.Event.Actions{escalate: true}
        )]
      end)

    config = make_config(make_runner(agent, ctx.session_svc))
    task_id = A2AEx.ID.new()
    req_ctx = make_req_ctx(task_id, "ctx-4", "help")

    events = run_executor(config, req_ctx, task_id)

    final = List.last(events)
    assert %TaskStatusUpdateEvent{status: %{state: :input_required}, final: true} = final
  end

  test "no content events → working then completed, no artifacts", ctx do
    agent =
      make_agent("empty", fn _inv_ctx ->
        [Event.new(author: "empty")]
      end)

    config = make_config(make_runner(agent, ctx.session_svc))
    task_id = A2AEx.ID.new()
    req_ctx = make_req_ctx(task_id, "ctx-5", "nothing")

    events = run_executor(config, req_ctx, task_id)

    artifact_events = Enum.filter(events, &match?(%TaskArtifactUpdateEvent{}, &1))
    assert artifact_events == []

    assert [working, completed] = events
    assert %TaskStatusUpdateEvent{status: %{state: :working}} = working
    assert %TaskStatusUpdateEvent{status: %{state: :completed}, final: true} = completed
  end

  test "cancel emits :canceled with final: true", ctx do
    agent = make_agent("cancelable", fn _inv_ctx -> [] end)
    config = make_config(make_runner(agent, ctx.session_svc))
    task_id = A2AEx.ID.new()
    req_ctx = make_req_ctx(task_id, "ctx-6", "cancel me")

    {:ok, _} = EventQueue.get_or_create(task_id)
    :ok = EventQueue.subscribe(task_id)

    ADKExecutor.cancel(config, req_ctx, task_id)

    events = collect_events(task_id, 1000)
    assert [canceled] = events
    assert %TaskStatusUpdateEvent{status: %{state: :canceled}, final: true} = canceled
  end

  test "final artifact has last_chunk: true", ctx do
    agent =
      make_agent("chunk", fn _inv_ctx ->
        [Event.new(author: "chunk", content: Content.new_from_text("model", "data"))]
      end)

    config = make_config(make_runner(agent, ctx.session_svc))
    task_id = A2AEx.ID.new()
    req_ctx = make_req_ctx(task_id, "ctx-7", "test")

    events = run_executor(config, req_ctx, task_id)

    last_chunk_events =
      Enum.filter(events, fn
        %TaskArtifactUpdateEvent{last_chunk: true} -> true
        _ -> false
      end)

    assert [last_chunk_event] = last_chunk_events
    assert last_chunk_event.artifact.parts == []
  end

  test "integration: message/send with {ADKExecutor, config} executor", ctx do
    agent =
      make_agent("integ", fn _inv_ctx ->
        [Event.new(author: "integ", content: Content.new_from_text("model", "response"))]
      end)

    config = make_config(make_runner(agent, ctx.session_svc))

    handler = %A2AEx.RequestHandler{
      executor: {ADKExecutor, config},
      task_store: {TaskStore.InMemory, ctx.store}
    }

    params = %{
      "message" => %{
        "role" => "user",
        "messageId" => "test-msg-#{System.unique_integer([:positive])}",
        "parts" => [%{"kind" => "text", "text" => "hello"}]
      }
    }

    request = %{jsonrpc: "2.0", method: "message/send", params: params, id: 1}
    assert {:ok, result} = A2AEx.RequestHandler.handle(handler, request)
    assert result["status"]["state"] == "completed"
    assert result["artifacts"] != []
  end

  test "integration: message/stream with {ADKExecutor, config} executor", ctx do
    agent =
      make_agent("stream", fn _inv_ctx ->
        [Event.new(author: "stream", content: Content.new_from_text("model", "streamed"))]
      end)

    config = make_config(make_runner(agent, ctx.session_svc))

    handler = %A2AEx.RequestHandler{
      executor: {ADKExecutor, config},
      task_store: {TaskStore.InMemory, ctx.store}
    }

    params = %{
      "message" => %{
        "role" => "user",
        "messageId" => "test-msg-#{System.unique_integer([:positive])}",
        "parts" => [%{"kind" => "text", "text" => "stream me"}]
      }
    }

    request = %{jsonrpc: "2.0", method: "message/stream", params: params, id: 2}
    assert {:stream, task_id} = A2AEx.RequestHandler.handle(handler, request)
    assert is_binary(task_id)

    events = collect_events(task_id)
    status_events = Enum.filter(events, &match?(%TaskStatusUpdateEvent{}, &1))
    assert length(status_events) >= 2
  end
end
