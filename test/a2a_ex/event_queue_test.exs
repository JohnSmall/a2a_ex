defmodule A2AEx.EventQueueTest do
  use ExUnit.Case, async: true

  alias A2AEx.EventQueue

  defp unique_task_id do
    "eq-test-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp make_status_event(task_id, state) do
    A2AEx.TaskStatusUpdateEvent.new(task_id, "ctx-1", state)
  end

  describe "start/1 and lookup/1" do
    test "starts a new queue" do
      task_id = unique_task_id()
      assert {:ok, pid} = EventQueue.start(task_id)
      assert is_pid(pid)
    end

    test "start is idempotent" do
      task_id = unique_task_id()
      {:ok, pid1} = EventQueue.start(task_id)
      {:ok, pid2} = EventQueue.start(task_id)
      assert pid1 == pid2
    end

    test "lookup finds started queue" do
      task_id = unique_task_id()
      {:ok, pid} = EventQueue.start(task_id)
      assert {:ok, ^pid} = EventQueue.lookup(task_id)
    end

    test "lookup returns error for nonexistent queue" do
      assert {:error, :not_found} = EventQueue.lookup("nonexistent-#{System.unique_integer()}")
    end
  end

  describe "get_or_create/1" do
    test "creates queue if not started" do
      task_id = unique_task_id()
      assert {:ok, pid} = EventQueue.get_or_create(task_id)
      assert is_pid(pid)
    end

    test "returns existing queue" do
      task_id = unique_task_id()
      {:ok, pid1} = EventQueue.start(task_id)
      {:ok, pid2} = EventQueue.get_or_create(task_id)
      assert pid1 == pid2
    end
  end

  describe "subscribe/1 and enqueue/2" do
    test "subscriber receives events" do
      task_id = unique_task_id()
      {:ok, _} = EventQueue.start(task_id)
      :ok = EventQueue.subscribe(task_id)

      event = make_status_event(task_id, :working)
      :ok = EventQueue.enqueue(task_id, event)

      assert_receive {:a2a_event, ^task_id, ^event}
    end

    test "multiple subscribers all receive events" do
      task_id = unique_task_id()
      {:ok, _} = EventQueue.start(task_id)
      parent = self()

      pids =
        for i <- 1..3 do
          spawn(fn ->
            :ok = EventQueue.subscribe(task_id)
            send(parent, {:subscribed, i})

            receive do
              {:a2a_event, ^task_id, event} -> send(parent, {:received, i, event})
            end
          end)
        end

      # Wait for all to subscribe
      for i <- 1..3, do: assert_receive({:subscribed, ^i})

      event = make_status_event(task_id, :working)
      :ok = EventQueue.enqueue(task_id, event)

      for i <- 1..3 do
        assert_receive {:received, ^i, ^event}
      end

      # Ensure processes exit cleanly
      for pid <- pids, do: Process.exit(pid, :normal)
    end

    test "subscribe is idempotent" do
      task_id = unique_task_id()
      {:ok, _} = EventQueue.start(task_id)
      :ok = EventQueue.subscribe(task_id)
      :ok = EventQueue.subscribe(task_id)

      event = make_status_event(task_id, :working)
      :ok = EventQueue.enqueue(task_id, event)

      # Should receive exactly one copy
      assert_receive {:a2a_event, ^task_id, ^event}
      refute_receive {:a2a_event, ^task_id, _}, 50
    end

    test "subscribe returns error for nonexistent queue" do
      assert {:error, :not_found} = EventQueue.subscribe("nonexistent-#{System.unique_integer()}")
    end

    test "enqueue returns error for nonexistent queue" do
      event = make_status_event("x", :working)
      assert {:error, :not_found} = EventQueue.enqueue("nonexistent-#{System.unique_integer()}", event)
    end
  end

  describe "close/1" do
    test "subscribers receive done signal" do
      task_id = unique_task_id()
      {:ok, _} = EventQueue.start(task_id)
      :ok = EventQueue.subscribe(task_id)

      :ok = EventQueue.close(task_id)

      assert_receive {:a2a_done, ^task_id}
    end

    test "queue process stops after close" do
      task_id = unique_task_id()
      {:ok, pid} = EventQueue.start(task_id)
      ref = Process.monitor(pid)

      :ok = EventQueue.close(task_id)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
      # Registry cleanup is async; wait briefly for it to propagate
      Process.sleep(10)
      assert {:error, :not_found} = EventQueue.lookup(task_id)
    end

    test "close is idempotent for nonexistent queue" do
      assert :ok = EventQueue.close("nonexistent-#{System.unique_integer()}")
    end
  end

  describe "subscriber cleanup" do
    test "dead subscriber is removed" do
      task_id = unique_task_id()
      {:ok, _} = EventQueue.start(task_id)

      pid =
        spawn(fn ->
          EventQueue.subscribe(task_id)

          receive do
            :stop -> :ok
          end
        end)

      # Allow time for subscription
      Process.sleep(20)

      # Kill the subscriber
      Process.exit(pid, :kill)
      Process.sleep(20)

      # Queue should still work — enqueue doesn't fail
      :ok = EventQueue.subscribe(task_id)
      event = make_status_event(task_id, :completed)
      :ok = EventQueue.enqueue(task_id, event)

      assert_receive {:a2a_event, ^task_id, ^event}

      EventQueue.close(task_id)
    end
  end

  describe "multiple events in sequence" do
    test "subscriber receives events in order" do
      task_id = unique_task_id()
      {:ok, _} = EventQueue.start(task_id)
      :ok = EventQueue.subscribe(task_id)

      events = [
        make_status_event(task_id, :submitted),
        make_status_event(task_id, :working),
        make_status_event(task_id, :completed)
      ]

      for event <- events do
        :ok = EventQueue.enqueue(task_id, event)
      end

      received =
        for _ <- 1..3 do
          receive do
            {:a2a_event, ^task_id, event} -> event
          after
            1000 -> flunk("timed out waiting for event")
          end
        end

      assert Enum.map(received, & &1.status.state) == [:submitted, :working, :completed]
    end
  end
end
