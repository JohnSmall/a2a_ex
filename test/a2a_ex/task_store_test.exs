defmodule A2AEx.TaskStore.InMemoryTest do
  use ExUnit.Case, async: true

  alias A2AEx.TaskStore.InMemory

  setup do
    {:ok, store} = InMemory.start_link()
    {:ok, store: store}
  end

  defp make_task(id \\ "task-1") do
    %A2AEx.Task{
      id: id,
      context_id: "ctx-1",
      status: %A2AEx.TaskStatus{state: :submitted}
    }
  end

  describe "get/2" do
    test "returns {:error, :not_found} for missing task", %{store: store} do
      assert {:error, :not_found} = InMemory.get(store, "nonexistent")
    end

    test "returns task after save", %{store: store} do
      task = make_task()
      :ok = InMemory.save(store, task)

      assert {:ok, ^task} = InMemory.get(store, "task-1")
    end
  end

  describe "save/2" do
    test "saves a new task", %{store: store} do
      assert :ok = InMemory.save(store, make_task())
      assert {:ok, _} = InMemory.get(store, "task-1")
    end

    test "overwrites existing task", %{store: store} do
      task = make_task()
      :ok = InMemory.save(store, task)

      updated = %{task | status: %A2AEx.TaskStatus{state: :working}}
      :ok = InMemory.save(store, updated)

      assert {:ok, %{status: %{state: :working}}} = InMemory.get(store, "task-1")
    end

    test "saves multiple tasks with different IDs", %{store: store} do
      :ok = InMemory.save(store, make_task("t1"))
      :ok = InMemory.save(store, make_task("t2"))
      :ok = InMemory.save(store, make_task("t3"))

      assert {:ok, %{id: "t1"}} = InMemory.get(store, "t1")
      assert {:ok, %{id: "t2"}} = InMemory.get(store, "t2")
      assert {:ok, %{id: "t3"}} = InMemory.get(store, "t3")
    end
  end

  describe "delete/2" do
    test "deletes an existing task", %{store: store} do
      :ok = InMemory.save(store, make_task())
      :ok = InMemory.delete(store, "task-1")

      assert {:error, :not_found} = InMemory.get(store, "task-1")
    end

    test "no-op for nonexistent task", %{store: store} do
      assert :ok = InMemory.delete(store, "nonexistent")
    end

    test "only deletes the specified task", %{store: store} do
      :ok = InMemory.save(store, make_task("t1"))
      :ok = InMemory.save(store, make_task("t2"))

      :ok = InMemory.delete(store, "t1")

      assert {:error, :not_found} = InMemory.get(store, "t1")
      assert {:ok, %{id: "t2"}} = InMemory.get(store, "t2")
    end
  end

  describe "concurrent reads" do
    test "multiple processes can read simultaneously", %{store: store} do
      :ok = InMemory.save(store, make_task("t1"))

      tasks =
        for _ <- 1..10 do
          Task.async(fn -> InMemory.get(store, "t1") end)
        end

      results = Task.await_many(tasks)
      assert Enum.all?(results, fn {:ok, %{id: "t1"}} -> true end)
    end
  end
end
