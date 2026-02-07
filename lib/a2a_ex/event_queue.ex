defmodule A2AEx.EventQueue do
  @moduledoc """
  Per-task event delivery queue.

  Each task gets a dedicated GenServer (started on demand) that broadcasts
  events to all subscribed processes. Uses Elixir Registry for lookup by task ID.

  ## Usage

      # Start a queue for a task (idempotent)
      {:ok, _pid} = A2AEx.EventQueue.start(task_id)

      # Subscribe the current process to receive events
      :ok = A2AEx.EventQueue.subscribe(task_id)

      # Enqueue an event (broadcasts to all subscribers)
      :ok = A2AEx.EventQueue.enqueue(task_id, event)

      # Subscribers receive:
      #   {:a2a_event, task_id, event}   — for each event
      #   {:a2a_done, task_id}           — when queue is closed

      # Close the queue when the task is complete
      :ok = A2AEx.EventQueue.close(task_id)
  """

  use GenServer

  @registry A2AEx.EventQueue.Registry
  @supervisor A2AEx.EventQueue.Supervisor

  # --- Public API ---

  @doc "Start a queue for the given task. Returns existing queue if already started."
  @spec start(String.t()) :: {:ok, pid()} | {:error, term()}
  def start(task_id) do
    case DynamicSupervisor.start_child(@supervisor, {__MODULE__, task_id}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  @doc "Start or return existing queue for a task."
  @spec get_or_create(String.t()) :: {:ok, pid()}
  def get_or_create(task_id) do
    case lookup(task_id) do
      {:ok, pid} -> {:ok, pid}
      {:error, :not_found} -> start(task_id)
    end
  end

  @doc "Look up the queue process for a task."
  @spec lookup(String.t()) :: {:ok, pid()} | {:error, :not_found}
  def lookup(task_id) do
    case Registry.lookup(@registry, task_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc "Subscribe the calling process to events for the given task."
  @spec subscribe(String.t()) :: :ok | {:error, :not_found}
  def subscribe(task_id) do
    with {:ok, pid} <- lookup(task_id) do
      GenServer.call(pid, {:subscribe, self()})
    end
  end

  @doc "Enqueue an event, broadcasting it to all subscribers."
  @spec enqueue(String.t(), A2AEx.Event.t()) :: :ok | {:error, :not_found}
  def enqueue(task_id, event) do
    with {:ok, pid} <- lookup(task_id) do
      GenServer.call(pid, {:enqueue, event})
    end
  end

  @doc "Close the queue, notifying all subscribers and stopping the process."
  @spec close(String.t()) :: :ok
  def close(task_id) do
    case lookup(task_id) do
      {:ok, pid} -> GenServer.call(pid, :close)
      {:error, :not_found} -> :ok
    end
  end

  # --- GenServer setup ---

  @doc false
  def start_link(task_id) do
    GenServer.start_link(__MODULE__, task_id, name: via(task_id))
  end

  @doc false
  def child_spec(task_id) do
    %{
      id: {__MODULE__, task_id},
      start: {__MODULE__, :start_link, [task_id]},
      restart: :temporary
    }
  end

  defp via(task_id), do: {:via, Registry, {@registry, task_id}}

  # --- GenServer callbacks ---

  @impl GenServer
  def init(task_id) do
    {:ok, %{task_id: task_id, subscribers: %{}}}
  end

  @impl GenServer
  def handle_call({:subscribe, pid}, _from, state) do
    if Map.has_key?(state.subscribers, pid) do
      {:reply, :ok, state}
    else
      ref = Process.monitor(pid)
      {:reply, :ok, %{state | subscribers: Map.put(state.subscribers, pid, ref)}}
    end
  end

  @impl GenServer
  def handle_call({:enqueue, event}, _from, state) do
    for {pid, _ref} <- state.subscribers do
      send(pid, {:a2a_event, state.task_id, event})
    end

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(:close, _from, state) do
    for {pid, _ref} <- state.subscribers do
      send(pid, {:a2a_done, state.task_id})
    end

    {:stop, :normal, :ok, state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: Map.delete(state.subscribers, pid)}}
  end
end
