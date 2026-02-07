defmodule A2AEx.MockExecutor do
  @moduledoc false
  @behaviour A2AEx.AgentExecutor

  @impl true
  def execute(context, task_id) do
    # Simulate: emit working → completed
    working = A2AEx.TaskStatusUpdateEvent.new(task_id, context.context_id, :working)
    A2AEx.EventQueue.enqueue(task_id, working)

    completed =
      %{A2AEx.TaskStatusUpdateEvent.new(task_id, context.context_id, :completed) | final: true}

    A2AEx.EventQueue.enqueue(task_id, completed)
    :ok
  end

  @impl true
  def cancel(context, task_id) do
    canceled =
      %{A2AEx.TaskStatusUpdateEvent.new(task_id, context.context_id, :canceled) | final: true}

    A2AEx.EventQueue.enqueue(task_id, canceled)
    :ok
  end
end

defmodule A2AEx.FailingExecutor do
  @moduledoc false
  @behaviour A2AEx.AgentExecutor

  @impl true
  def execute(_context, _task_id) do
    {:error, :agent_unavailable}
  end

  @impl true
  def cancel(_context, _task_id) do
    {:error, :not_cancelable}
  end
end

defmodule A2AEx.AgentExecutorTest do
  use ExUnit.Case, async: true

  alias A2AEx.EventQueue

  defp unique_task_id do
    "exec-test-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp make_context(task_id) do
    %A2AEx.RequestContext{
      task_id: task_id,
      context_id: "ctx-1",
      message: %A2AEx.Message{
        id: "msg-1",
        role: :user,
        parts: [%A2AEx.TextPart{text: "hello"}]
      }
    }
  end

  describe "RequestContext" do
    test "creates with required fields" do
      ctx = make_context("t1")
      assert ctx.task_id == "t1"
      assert ctx.context_id == "ctx-1"
      assert ctx.message.role == :user
      assert ctx.task == nil
      assert ctx.metadata == nil
    end

    test "creates with optional fields" do
      task = %A2AEx.Task{
        id: "t1",
        context_id: "ctx-1",
        status: %A2AEx.TaskStatus{state: :working}
      }

      ctx = %A2AEx.RequestContext{
        task_id: "t1",
        context_id: "ctx-1",
        message: %A2AEx.Message{id: "m1", role: :user, parts: []},
        task: task,
        metadata: %{"key" => "value"}
      }

      assert ctx.task == task
      assert ctx.metadata == %{"key" => "value"}
    end
  end

  describe "MockExecutor.execute/2" do
    test "writes working and completed events to queue" do
      task_id = unique_task_id()
      context = make_context(task_id)

      {:ok, _} = EventQueue.start(task_id)
      :ok = EventQueue.subscribe(task_id)

      assert :ok = A2AEx.MockExecutor.execute(context, task_id)

      assert_receive {:a2a_event, ^task_id, %A2AEx.TaskStatusUpdateEvent{status: %{state: :working}}}

      assert_receive {:a2a_event, ^task_id,
                      %A2AEx.TaskStatusUpdateEvent{status: %{state: :completed}, final: true}}

      EventQueue.close(task_id)
    end
  end

  describe "MockExecutor.cancel/2" do
    test "writes canceled event to queue" do
      task_id = unique_task_id()
      context = make_context(task_id)

      {:ok, _} = EventQueue.start(task_id)
      :ok = EventQueue.subscribe(task_id)

      assert :ok = A2AEx.MockExecutor.cancel(context, task_id)

      assert_receive {:a2a_event, ^task_id,
                      %A2AEx.TaskStatusUpdateEvent{status: %{state: :canceled}, final: true}}

      EventQueue.close(task_id)
    end
  end

  describe "FailingExecutor" do
    test "execute returns error tuple" do
      context = make_context("t1")
      assert {:error, :agent_unavailable} = A2AEx.FailingExecutor.execute(context, "t1")
    end

    test "cancel returns error tuple" do
      context = make_context("t1")
      assert {:error, :not_cancelable} = A2AEx.FailingExecutor.cancel(context, "t1")
    end
  end
end
