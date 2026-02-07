defmodule A2AEx.PushConfigStoreTest do
  use ExUnit.Case, async: true

  alias A2AEx.PushConfigStore.InMemory
  alias A2AEx.PushConfig

  setup do
    {:ok, store} = InMemory.start_link()
    %{store: store}
  end

  test "save assigns ID if not set", %{store: store} do
    config = %PushConfig{url: "https://example.com/webhook"}
    assert {:ok, saved} = InMemory.save(store, "task-1", config)
    assert saved.id != nil
    assert saved.url == "https://example.com/webhook"
  end

  test "save preserves existing ID", %{store: store} do
    config = %PushConfig{url: "https://example.com/webhook", id: "my-id"}
    assert {:ok, saved} = InMemory.save(store, "task-1", config)
    assert saved.id == "my-id"
  end

  test "get retrieves saved config", %{store: store} do
    config = %PushConfig{url: "https://example.com/webhook", id: "cfg-1"}
    {:ok, _} = InMemory.save(store, "task-1", config)

    assert {:ok, retrieved} = InMemory.get(store, "task-1", "cfg-1")
    assert retrieved.url == "https://example.com/webhook"
    assert retrieved.id == "cfg-1"
  end

  test "get returns error for non-existent config", %{store: store} do
    assert {:error, :not_found} = InMemory.get(store, "task-1", "no-such-id")
  end

  test "get returns error for wrong task ID", %{store: store} do
    config = %PushConfig{url: "https://example.com/webhook", id: "cfg-1"}
    {:ok, _} = InMemory.save(store, "task-1", config)

    assert {:error, :not_found} = InMemory.get(store, "task-2", "cfg-1")
  end

  test "list returns all configs for a task", %{store: store} do
    {:ok, _} = InMemory.save(store, "task-1", %PushConfig{url: "https://a.com", id: "a"})
    {:ok, _} = InMemory.save(store, "task-1", %PushConfig{url: "https://b.com", id: "b"})
    {:ok, _} = InMemory.save(store, "task-2", %PushConfig{url: "https://c.com", id: "c"})

    assert {:ok, configs} = InMemory.list(store, "task-1")
    assert length(configs) == 2
    urls = Enum.map(configs, & &1.url) |> Enum.sort()
    assert urls == ["https://a.com", "https://b.com"]
  end

  test "list returns empty for unknown task", %{store: store} do
    assert {:ok, []} = InMemory.list(store, "no-such-task")
  end

  test "delete removes a config", %{store: store} do
    {:ok, _} = InMemory.save(store, "task-1", %PushConfig{url: "https://a.com", id: "a"})
    {:ok, _} = InMemory.save(store, "task-1", %PushConfig{url: "https://b.com", id: "b"})

    :ok = InMemory.delete(store, "task-1", "a")

    assert {:error, :not_found} = InMemory.get(store, "task-1", "a")
    assert {:ok, _} = InMemory.get(store, "task-1", "b")
  end

  test "delete is idempotent", %{store: store} do
    :ok = InMemory.delete(store, "task-1", "no-such-id")
  end

  test "save overwrites config with same ID", %{store: store} do
    {:ok, _} = InMemory.save(store, "task-1", %PushConfig{url: "https://old.com", id: "cfg-1"})
    {:ok, _} = InMemory.save(store, "task-1", %PushConfig{url: "https://new.com", id: "cfg-1"})

    assert {:ok, config} = InMemory.get(store, "task-1", "cfg-1")
    assert config.url == "https://new.com"
  end
end
