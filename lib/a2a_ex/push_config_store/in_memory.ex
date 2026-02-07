defmodule A2AEx.PushConfigStore.InMemory do
  @moduledoc """
  In-memory push config store backed by ETS.

  Uses a GenServer for serialized writes and ETS for concurrent reads.
  Stores push configs keyed by `{task_id, config_id}`.
  """

  @behaviour A2AEx.PushConfigStore

  use GenServer

  # --- Client API ---

  @doc "Start the in-memory push config store."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @impl A2AEx.PushConfigStore
  def save(store, task_id, %A2AEx.PushConfig{} = config) do
    GenServer.call(store, {:save, task_id, config})
  end

  @impl A2AEx.PushConfigStore
  def get(store, task_id, config_id) do
    table = GenServer.call(store, :table)

    case :ets.lookup(table, {task_id, config_id}) do
      [{_key, config}] -> {:ok, config}
      [] -> {:error, :not_found}
    end
  end

  @impl A2AEx.PushConfigStore
  def list(store, task_id) do
    table = GenServer.call(store, :table)
    configs = :ets.select(table, [{{{task_id, :_}, :"$1"}, [], [:"$1"]}])
    {:ok, configs}
  end

  @impl A2AEx.PushConfigStore
  def delete(store, task_id, config_id) do
    GenServer.call(store, {:delete, task_id, config_id})
  end

  # --- GenServer callbacks ---

  @impl GenServer
  def init(_opts) do
    table = :ets.new(:a2a_push_config_store, [:set, :protected, read_concurrency: true])
    {:ok, %{table: table}}
  end

  @impl GenServer
  def handle_call(:table, _from, state) do
    {:reply, state.table, state}
  end

  @impl GenServer
  def handle_call({:save, task_id, %A2AEx.PushConfig{} = config}, _from, state) do
    config = if config.id, do: config, else: %{config | id: A2AEx.ID.new()}
    :ets.insert(state.table, {{task_id, config.id}, config})
    {:reply, {:ok, config}, state}
  end

  @impl GenServer
  def handle_call({:delete, task_id, config_id}, _from, state) do
    :ets.delete(state.table, {task_id, config_id})
    {:reply, :ok, state}
  end
end
