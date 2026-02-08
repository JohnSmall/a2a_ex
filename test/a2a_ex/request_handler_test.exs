defmodule A2AEx.RequestHandlerTest do
  use ExUnit.Case, async: true

  alias A2AEx.{RequestHandler, TaskStore, EventQueue, Message, TextPart, Task, TaskStatus}
  alias A2AEx.{TaskStatusUpdateEvent, TaskArtifactUpdateEvent, Artifact}

  # --- Test executor that emits events to EventQueue ---

  defmodule EchoExecutor do
    @behaviour A2AEx.AgentExecutor

    @impl true
    def execute(%A2AEx.RequestContext{} = ctx, task_id) do
      # Emit a "working" status update
      working_event = TaskStatusUpdateEvent.new(task_id, ctx.context_id, :working)
      EventQueue.enqueue(task_id, working_event)

      # Emit a "completed" status with agent response
      reply = Message.new(:agent, [%TextPart{text: "echo: #{hd(ctx.message.parts).text}"}])
      completed_event = TaskStatusUpdateEvent.new(task_id, ctx.context_id, :completed, reply)
      EventQueue.enqueue(task_id, %{completed_event | final: true})
      :ok
    end

    @impl true
    def cancel(_ctx, _task_id), do: :ok
  end

  defmodule FailingExecutor do
    @behaviour A2AEx.AgentExecutor

    @impl true
    def execute(_ctx, _task_id) do
      raise "boom"
    end

    @impl true
    def cancel(_ctx, _task_id), do: {:error, :not_cancelable}
  end

  defmodule ArtifactExecutor do
    @behaviour A2AEx.AgentExecutor

    @impl true
    def execute(%A2AEx.RequestContext{} = ctx, task_id) do
      working = TaskStatusUpdateEvent.new(task_id, ctx.context_id, :working)
      EventQueue.enqueue(task_id, working)

      artifact = %Artifact{
        id: "art-1",
        name: "output",
        parts: [%TextPart{text: "artifact content"}]
      }

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

  setup do
    {:ok, store} = TaskStore.InMemory.start_link()
    %{store: store}
  end

  defp make_handler(store, executor \\ EchoExecutor) do
    %RequestHandler{
      executor: executor,
      task_store: {TaskStore.InMemory, store}
    }
  end

  defp send_request(handler, method, params) do
    request = %{jsonrpc: "2.0", method: method, params: params, id: 1}
    RequestHandler.handle(handler, request)
  end

  defp make_send_params(text, opts \\ %{}) do
    message = %{
      "role" => "user",
      "parts" => [%{"kind" => "text", "text" => text}],
      "messageId" => Map.get(opts, "messageId", A2AEx.ID.new())
    }

    message =
      if task_id = Map.get(opts, "taskId"), do: Map.put(message, "taskId", task_id), else: message

    %{"message" => message}
  end

  # --- message/send tests ---

  test "message/send creates task and returns completed result", %{store: store} do
    handler = make_handler(store)
    params = make_send_params("hello")

    assert {:ok, result} = send_request(handler, "message/send", params)
    assert result["kind"] == "task"
    assert result["status"]["state"] == "completed"
  end

  test "message/send echoes message content", %{store: store} do
    handler = make_handler(store)
    params = make_send_params("ping")

    assert {:ok, result} = send_request(handler, "message/send", params)
    assert result["status"]["state"] == "completed"
    # The completed status message has the echo
    assert result["status"]["message"]["parts"] != nil
  end

  test "message/send stores task in TaskStore", %{store: store} do
    handler = make_handler(store)
    params = make_send_params("test")

    {:ok, result} = send_request(handler, "message/send", params)
    task_id = result["id"]

    assert {:ok, stored} = TaskStore.InMemory.get(store, task_id)
    assert stored.status.state == :completed
  end

  test "message/send with artifact executor", %{store: store} do
    handler = make_handler(store, ArtifactExecutor)
    params = make_send_params("generate")

    assert {:ok, result} = send_request(handler, "message/send", params)
    assert result["status"]["state"] == "completed"

    # Check task in store has artifact
    {:ok, stored} = TaskStore.InMemory.get(store, result["id"])
    assert length(stored.artifacts) == 1
    assert hd(stored.artifacts).name == "output"
  end

  test "message/send with failing executor returns error event", %{store: store} do
    handler = make_handler(store, FailingExecutor)
    params = make_send_params("fail")

    {:ok, result} = send_request(handler, "message/send", params)
    assert result["status"]["state"] == "failed"
  end

  test "message/send rejects nil params", %{store: store} do
    handler = make_handler(store)
    assert {:error, error} = send_request(handler, "message/send", nil)
    assert error.type == :invalid_params
  end

  test "message/send rejects empty parts", %{store: store} do
    handler = make_handler(store)

    params = %{
      "message" => %{
        "role" => "user",
        "parts" => [],
        "messageId" => "msg-1"
      }
    }

    assert {:error, error} = send_request(handler, "message/send", params)
    assert error.type == :invalid_params
  end

  # --- message/stream tests ---

  test "message/stream returns stream handle", %{store: store} do
    handler = make_handler(store)
    params = make_send_params("stream me")

    assert {:stream, task_id} = send_request(handler, "message/stream", params)
    assert is_binary(task_id)

    # Should receive events
    assert_receive {:a2a_event, ^task_id, %TaskStatusUpdateEvent{status: %{state: :working}}},
                   1000

    assert_receive {:a2a_event, ^task_id, %TaskStatusUpdateEvent{status: %{state: :completed}}},
                   1000

    assert_receive {:a2a_done, ^task_id}, 1000
  end

  # --- tasks/get tests ---

  test "tasks/get returns stored task", %{store: store} do
    handler = make_handler(store)

    # Create a task first
    task = Task.new_submitted(Message.new(:user, [%TextPart{text: "hi"}]), task_id: "t1")
    TaskStore.InMemory.save(store, task)

    assert {:ok, result} = send_request(handler, "tasks/get", %{"id" => "t1"})
    assert result["id"] == "t1"
    assert result["kind"] == "task"
  end

  test "tasks/get with history_length truncation", %{store: store} do
    handler = make_handler(store)

    msg1 = Message.new(:user, [%TextPart{text: "msg1"}])
    msg2 = Message.new(:agent, [%TextPart{text: "msg2"}])
    msg3 = Message.new(:user, [%TextPart{text: "msg3"}])

    task = %Task{
      id: "t2",
      context_id: "ctx-2",
      status: %TaskStatus{state: :completed},
      history: [msg1, msg2, msg3]
    }

    TaskStore.InMemory.save(store, task)

    assert {:ok, result} =
             send_request(handler, "tasks/get", %{"id" => "t2", "historyLength" => 1})

    assert length(result["history"]) == 1
  end

  test "tasks/get with historyLength 0 returns empty history", %{store: store} do
    handler = make_handler(store)

    task = %Task{
      id: "t3",
      context_id: "ctx-3",
      status: %TaskStatus{state: :completed},
      history: [Message.new(:user, [%TextPart{text: "hi"}])]
    }

    TaskStore.InMemory.save(store, task)

    assert {:ok, result} =
             send_request(handler, "tasks/get", %{"id" => "t3", "historyLength" => 0})

    # Empty history is included as empty list
    assert result["history"] == []
  end

  test "tasks/get returns error for non-existent task", %{store: store} do
    handler = make_handler(store)
    assert {:error, error} = send_request(handler, "tasks/get", %{"id" => "no-such"})
    assert error.type == :task_not_found
  end

  test "tasks/get rejects missing ID", %{store: store} do
    handler = make_handler(store)
    assert {:error, error} = send_request(handler, "tasks/get", %{})
    assert error.type == :invalid_params
  end

  # --- tasks/cancel tests ---

  test "tasks/cancel cancels a running task", %{store: store} do
    handler = make_handler(store)

    task = %Task{
      id: "tc1",
      context_id: "ctx-c1",
      status: %TaskStatus{state: :working},
      history: [Message.new(:user, [%TextPart{text: "work"}])]
    }

    TaskStore.InMemory.save(store, task)

    assert {:ok, result} = send_request(handler, "tasks/cancel", %{"id" => "tc1"})
    assert result["status"]["state"] == "canceled"
  end

  test "tasks/cancel allows canceling completed task", %{store: store} do
    handler = make_handler(store)

    task = %Task{
      id: "tc2",
      context_id: "ctx-c2",
      status: %TaskStatus{state: :completed}
    }

    TaskStore.InMemory.save(store, task)

    assert {:ok, result} = send_request(handler, "tasks/cancel", %{"id" => "tc2"})
    assert result["status"]["state"] == "canceled"
  end

  test "tasks/cancel returns error for non-existent task", %{store: store} do
    handler = make_handler(store)
    assert {:error, error} = send_request(handler, "tasks/cancel", %{"id" => "no-such"})
    assert error.type == :task_not_found
  end

  # --- tasks/resubscribe tests ---

  test "tasks/resubscribe returns stream for active queue", %{store: store} do
    handler = make_handler(store)

    # Start a queue
    task_id = "resub-#{System.unique_integer([:positive])}"
    {:ok, _} = EventQueue.get_or_create(task_id)

    assert {:stream, ^task_id} =
             send_request(handler, "tasks/resubscribe", %{"id" => task_id})
  end

  test "tasks/resubscribe returns error for no active queue", %{store: store} do
    handler = make_handler(store)

    assert {:error, error} =
             send_request(handler, "tasks/resubscribe", %{"id" => "no-such-queue"})

    assert error.type == :task_not_found
  end

  # --- Push config tests ---

  test "push config methods return error when not configured", %{store: store} do
    handler = make_handler(store)

    for method <- [
          "tasks/pushNotificationConfig/set",
          "tasks/pushNotificationConfig/get",
          "tasks/pushNotificationConfig/delete",
          "tasks/pushNotificationConfig/list"
        ] do
      assert {:error, error} = send_request(handler, method, %{})
      assert error.type == :push_notification_not_supported
    end
  end

  test "push config set/get/list/delete lifecycle", %{store: store} do
    {:ok, push_store} = A2AEx.PushConfigStore.InMemory.start_link()

    handler = %RequestHandler{
      executor: EchoExecutor,
      task_store: {TaskStore.InMemory, store},
      push_config_store: {A2AEx.PushConfigStore.InMemory, push_store},
      push_sender: A2AEx.PushSender.HTTP
    }

    # Pre-create task so push config operations can find it
    task = %A2AEx.Task{
      id: "task-push-1",
      context_id: "ctx-push",
      status: %A2AEx.TaskStatus{state: :working, timestamp: DateTime.utc_now()},
      history: [],
      artifacts: []
    }

    TaskStore.InMemory.save(store, task)

    # Set
    set_params = %{
      "taskId" => "task-push-1",
      "pushNotificationConfig" => %{
        "url" => "https://hooks.example.com/a2a"
      }
    }

    assert {:ok, set_result} =
             send_request(handler, "tasks/pushNotificationConfig/set", set_params)

    assert set_result["taskId"] == "task-push-1"
    config_id = set_result["pushNotificationConfig"]["id"]
    assert config_id != nil

    # Get
    get_params = %{"id" => "task-push-1", "pushNotificationConfigId" => config_id}

    assert {:ok, get_result} =
             send_request(handler, "tasks/pushNotificationConfig/get", get_params)

    assert get_result["pushNotificationConfig"]["url"] == "https://hooks.example.com/a2a"

    # List
    list_params = %{"id" => "task-push-1"}

    assert {:ok, list_result} =
             send_request(handler, "tasks/pushNotificationConfig/list", list_params)

    assert length(list_result) == 1

    # Delete
    delete_params = %{"id" => "task-push-1", "pushNotificationConfigId" => config_id}

    assert {:ok, _} =
             send_request(handler, "tasks/pushNotificationConfig/delete", delete_params)

    # Verify deleted
    assert {:ok, list_result} =
             send_request(handler, "tasks/pushNotificationConfig/list", list_params)

    assert list_result == []
  end

  # --- Extended card tests ---

  test "extended card returns error when not configured", %{store: store} do
    handler = make_handler(store)

    assert {:error, error} =
             send_request(handler, "agent/getAuthenticatedExtendedCard", nil)

    assert error.type == :extended_card_not_configured
  end

  test "extended card returns configured card", %{store: store} do
    card = %A2AEx.AgentCard{
      name: "Test Agent",
      description: "Extended",
      url: "https://agent.example.com",
      version: "1.0"
    }

    handler = %RequestHandler{
      executor: EchoExecutor,
      task_store: {TaskStore.InMemory, store},
      extended_card: card
    }

    assert {:ok, result} =
             send_request(handler, "agent/getAuthenticatedExtendedCard", nil)

    assert result["name"] == "Test Agent"
  end

  # --- Unknown method test ---

  test "unknown method returns method_not_found", %{store: store} do
    handler = make_handler(store)
    assert {:error, error} = send_request(handler, "unknown/method", %{})
    assert error.type == :method_not_found
  end

  test "empty method returns invalid_request", %{store: store} do
    handler = make_handler(store)
    assert {:error, error} = send_request(handler, "", %{})
    assert error.type == :invalid_request
  end
end
