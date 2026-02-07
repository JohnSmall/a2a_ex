defmodule A2AEx.TaskStore.InMemory do
  @moduledoc """
  In-memory task store backed by ETS.

  Uses a GenServer for serialized writes and ETS for concurrent reads.
  Each instance owns its own ETS table, identified by the GenServer name/pid.
  """

  @behaviour A2AEx.TaskStore

  use GenServer

  # --- Client API ---

  @doc "Start the in-memory task store."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @impl A2AEx.TaskStore
  def get(store, task_id) do
    table = GenServer.call(store, :table)

    case :ets.lookup(table, task_id) do
      [{^task_id, task}] -> {:ok, task}
      [] -> {:error, :not_found}
    end
  end

  @impl A2AEx.TaskStore
  def save(store, %A2AEx.Task{} = task) do
    GenServer.call(store, {:save, task})
  end

  @impl A2AEx.TaskStore
  def delete(store, task_id) do
    GenServer.call(store, {:delete, task_id})
  end

  # --- GenServer callbacks ---

  @impl GenServer
  def init(_opts) do
    table = :ets.new(:a2a_task_store, [:set, :protected, read_concurrency: true])
    {:ok, %{table: table}}
  end

  @impl GenServer
  def handle_call(:table, _from, state) do
    {:reply, state.table, state}
  end

  @impl GenServer
  def handle_call({:save, %A2AEx.Task{} = task}, _from, state) do
    :ets.insert(state.table, {task.id, task})
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:delete, task_id}, _from, state) do
    :ets.delete(state.table, task_id)
    {:reply, :ok, state}
  end
end
