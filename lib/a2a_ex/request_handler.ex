defmodule A2AEx.RequestHandler do
  @moduledoc """
  Business logic for all A2A JSON-RPC methods.

  Manages the task lifecycle: creates tasks, starts event queues,
  spawns agent executors, collects events, and updates the task store.

  ## Configuration

  The handler is configured via a struct with the following fields:

  - `:executor` — Module implementing `A2AEx.AgentExecutor` (required)
  - `:task_store` — `{module, server}` tuple for task persistence (required)
  - `:agent_card` — `A2AEx.AgentCard` struct served at well-known URL
  - `:push_config_store` — `{module, server}` tuple for push configs (optional)
  - `:push_sender` — Module implementing `A2AEx.PushSender` (optional)
  - `:extended_card` — `A2AEx.AgentCard` for authenticated extended card (optional)
  """

  @type store_ref :: {module(), GenServer.server()}

  @type t :: %__MODULE__{
          executor: module(),
          task_store: store_ref(),
          agent_card: A2AEx.AgentCard.t() | nil,
          push_config_store: store_ref() | nil,
          push_sender: module() | nil,
          extended_card: A2AEx.AgentCard.t() | nil
        }

  @enforce_keys [:executor, :task_store]
  defstruct [
    :executor,
    :task_store,
    :agent_card,
    :push_config_store,
    :push_sender,
    :extended_card
  ]

  # Method dispatch tables — reduces cyclomatic complexity
  @sync_methods %{
    "message/send" => :handle_message_send,
    "tasks/get" => :handle_tasks_get,
    "tasks/cancel" => :handle_tasks_cancel,
    "tasks/pushNotificationConfig/set" => :handle_push_config_set,
    "tasks/pushNotificationConfig/get" => :handle_push_config_get,
    "tasks/pushNotificationConfig/delete" => :handle_push_config_delete,
    "tasks/pushNotificationConfig/list" => :handle_push_config_list,
    "agent/getAuthenticatedExtendedCard" => :handle_get_extended_card
  }

  @stream_methods %{
    "message/stream" => :handle_message_stream,
    "tasks/resubscribe" => :handle_tasks_resubscribe
  }

  @doc """
  Dispatch a JSON-RPC request to the appropriate handler.

  Returns:
  - `{:ok, result}` for synchronous methods
  - `{:error, A2AEx.Error.t()}` on failure
  - `{:stream, task_id}` for streaming methods (caller must subscribe to EventQueue)
  """
  @spec handle(t(), A2AEx.JSONRPC.request()) ::
          {:ok, term()} | {:error, A2AEx.Error.t()} | {:stream, String.t()}
  def handle(handler, request) do
    method = request.method
    dispatch(handler, method, request.params)
  end

  defp dispatch(_handler, "", _params) do
    {:error, A2AEx.Error.new(:invalid_request, "missing method")}
  end

  defp dispatch(handler, method, params) do
    cond do
      fun = @sync_methods[method] -> apply(__MODULE__, fun, [handler, params])
      fun = @stream_methods[method] -> apply(__MODULE__, fun, [handler, params])
      true -> {:error, A2AEx.Error.new(:method_not_found, "unknown method")}
    end
  end

  # --- message/send (synchronous) ---

  @doc false
  def handle_message_send(handler, params) do
    with {:ok, send_params} <- parse_send_params(params),
         :ok <- validate_message(send_params),
         {:ok, task, req_ctx} <- prepare_execution(handler, send_params) do
      execute_and_collect(handler, task, req_ctx, send_params)
    end
  end

  defp execute_and_collect(handler, task, req_ctx, send_params) do
    {:ok, _} = A2AEx.EventQueue.get_or_create(task.id)
    :ok = A2AEx.EventQueue.subscribe(task.id)

    spawn_executor(handler, req_ctx, task.id)

    collect_events(handler, task.id, send_params)
  end

  defp collect_events(handler, task_id, send_params) do
    receive do
      {:a2a_event, ^task_id, event} ->
        update_task_from_event(handler, task_id, event)

        if should_interrupt?(send_params, event) do
          load_task_result(handler, task_id)
        else
          collect_events(handler, task_id, send_params)
        end

      {:a2a_done, ^task_id} ->
        load_task_result(handler, task_id)
    after
      60_000 -> {:error, A2AEx.Error.new(:internal_error, "execution timeout")}
    end
  end

  # --- message/stream ---

  @doc false
  def handle_message_stream(handler, params) do
    with {:ok, send_params} <- parse_send_params(params),
         :ok <- validate_message(send_params),
         {:ok, task, req_ctx} <- prepare_execution(handler, send_params) do
      {:ok, _} = A2AEx.EventQueue.get_or_create(task.id)
      :ok = A2AEx.EventQueue.subscribe(task.id)

      spawn_executor(handler, req_ctx, task.id)

      {:stream, task.id}
    end
  end

  # --- tasks/get ---

  @doc false
  def handle_tasks_get(handler, params) do
    with {:ok, query} <- A2AEx.TaskQueryParams.from_map(params || %{}),
         :ok <- require_id(query.id) do
      fetch_task_for_query(handler, query)
    end
  end

  defp fetch_task_for_query(handler, query) do
    case task_store_get(handler, query.id) do
      {:ok, task} ->
        task = truncate_history(task, query.history_length)
        {:ok, A2AEx.Task.to_map(task)}

      {:error, :not_found} ->
        {:error, A2AEx.Error.new(:task_not_found, "task not found")}
    end
  end

  # --- tasks/cancel ---

  @doc false
  def handle_tasks_cancel(handler, params) do
    with {:ok, id_params} <- A2AEx.TaskIDParams.from_map(params || %{}),
         :ok <- require_id(id_params.id),
         {:ok, task} <- find_task(handler, id_params.id),
         :ok <- check_cancelable(task) do
      do_cancel(handler, task, id_params)
    end
  end

  defp check_cancelable(task) do
    if A2AEx.TaskState.terminal?(task.status.state) do
      {:error, A2AEx.Error.new(:task_not_cancelable, "task is already in terminal state")}
    else
      :ok
    end
  end

  defp do_cancel(handler, task, id_params) do
    req_ctx = %A2AEx.RequestContext{
      task_id: task.id,
      context_id: task.context_id,
      message: A2AEx.Message.new(:user, [%A2AEx.TextPart{text: "cancel"}]),
      task: task
    }

    case handler.executor.cancel(req_ctx, id_params.id) do
      :ok ->
        canceled_task = %{
          task
          | status: %A2AEx.TaskStatus{state: :canceled, timestamp: DateTime.utc_now()}
        }

        task_store_save(handler, canceled_task)
        {:ok, A2AEx.Task.to_map(canceled_task)}

      {:error, reason} ->
        {:error, A2AEx.Error.new(:task_not_cancelable, "cancel failed: #{inspect(reason)}")}
    end
  end

  # --- tasks/resubscribe ---

  @doc false
  def handle_tasks_resubscribe(_handler, params) do
    with {:ok, id_params} <- A2AEx.TaskIDParams.from_map(params || %{}),
         :ok <- require_id(id_params.id) do
      resubscribe_to_queue(id_params.id)
    end
  end

  defp resubscribe_to_queue(task_id) do
    case A2AEx.EventQueue.lookup(task_id) do
      {:ok, _pid} ->
        :ok = A2AEx.EventQueue.subscribe(task_id)
        {:stream, task_id}

      {:error, :not_found} ->
        {:error, A2AEx.Error.new(:task_not_found, "no active event queue for task")}
    end
  end

  # --- Push notification config methods ---

  @doc false
  def handle_push_config_set(handler, params) do
    with :ok <- check_push_support(handler),
         {:ok, tpc} <- A2AEx.TaskPushConfig.from_map(params || %{}) do
      do_push_config_save(handler, tpc)
    end
  end

  defp do_push_config_save(handler, tpc) do
    {mod, store} = handler.push_config_store

    case mod.save(store, tpc.task_id, tpc.push_notification_config) do
      {:ok, saved} ->
        {:ok, A2AEx.TaskPushConfig.to_map(%{tpc | push_notification_config: saved})}

      {:error, reason} ->
        {:error,
         A2AEx.Error.new(:internal_error, "failed to save push config: #{inspect(reason)}")}
    end
  end

  @doc false
  def handle_push_config_get(handler, params) do
    with :ok <- check_push_support(handler),
         {:ok, gp} <- A2AEx.GetTaskPushConfigParams.from_map(params || %{}) do
      do_push_config_get(handler, gp)
    end
  end

  defp do_push_config_get(handler, gp) do
    {mod, store} = handler.push_config_store

    case mod.get(store, gp.task_id, gp.config_id || "") do
      {:ok, config} ->
        result = %A2AEx.TaskPushConfig{task_id: gp.task_id, push_notification_config: config}
        {:ok, A2AEx.TaskPushConfig.to_map(result)}

      {:error, :not_found} ->
        {:error, A2AEx.Error.new(:task_not_found, "push config not found")}
    end
  end

  @doc false
  def handle_push_config_delete(handler, params) do
    with :ok <- check_push_support(handler),
         {:ok, dp} <- A2AEx.DeleteTaskPushConfigParams.from_map(params || %{}) do
      {mod, store} = handler.push_config_store
      mod.delete(store, dp.task_id, dp.config_id)
      {:ok, %{}}
    end
  end

  @doc false
  def handle_push_config_list(handler, params) do
    with :ok <- check_push_support(handler),
         {:ok, lp} <- A2AEx.ListTaskPushConfigParams.from_map(params || %{}) do
      do_push_config_list(handler, lp)
    end
  end

  defp do_push_config_list(handler, lp) do
    {mod, store} = handler.push_config_store

    case mod.list(store, lp.task_id) do
      {:ok, configs} ->
        result =
          Enum.map(configs, fn config ->
            A2AEx.TaskPushConfig.to_map(%A2AEx.TaskPushConfig{
              task_id: lp.task_id,
              push_notification_config: config
            })
          end)

        {:ok, result}

      {:error, reason} ->
        {:error,
         A2AEx.Error.new(:internal_error, "failed to list push configs: #{inspect(reason)}")}
    end
  end

  defp check_push_support(%{push_config_store: nil}) do
    {:error,
     A2AEx.Error.new(:push_notification_not_supported, "push notifications not configured")}
  end

  defp check_push_support(%{push_sender: nil}) do
    {:error, A2AEx.Error.new(:push_notification_not_supported, "push sender not configured")}
  end

  defp check_push_support(_handler), do: :ok

  # --- Extended card ---

  @doc false
  def handle_get_extended_card(handler, params \\ nil)

  def handle_get_extended_card(%{extended_card: nil}, _params) do
    {:error, A2AEx.Error.new(:extended_card_not_configured, "extended card not configured")}
  end

  def handle_get_extended_card(%{extended_card: card}, _params) do
    {:ok, A2AEx.AgentCard.to_map(card)}
  end

  # --- Shared helpers ---

  defp require_id(id) when is_binary(id) and id != "", do: :ok
  defp require_id(_), do: {:error, A2AEx.Error.new(:invalid_params, "missing task ID")}

  defp find_task(handler, task_id) do
    case task_store_get(handler, task_id) do
      {:ok, _} = ok -> ok
      {:error, :not_found} -> {:error, A2AEx.Error.new(:task_not_found, "task not found")}
    end
  end

  defp parse_send_params(nil) do
    {:error, A2AEx.Error.new(:invalid_params, "missing params")}
  end

  defp parse_send_params(params) when is_map(params) do
    case A2AEx.MessageSendParams.from_map(params) do
      {:ok, _} = ok -> ok
      {:error, reason} -> {:error, A2AEx.Error.new(:invalid_params, "invalid params: #{reason}")}
    end
  end

  defp validate_message(%A2AEx.MessageSendParams{message: %A2AEx.Message{parts: []}}) do
    {:error, A2AEx.Error.new(:invalid_params, "message parts is required")}
  end

  defp validate_message(_), do: :ok

  defp prepare_execution(handler, send_params) do
    message = send_params.message
    task_id = message.task_id || A2AEx.ID.new()
    context_id = message.context_id || A2AEx.ID.new()

    {task, context_id} =
      case task_store_get(handler, task_id) do
        {:ok, existing} ->
          updated = %{existing | history: (existing.history || []) ++ [message]}
          task_store_save(handler, updated)
          {updated, existing.context_id}

        {:error, :not_found} ->
          new_task =
            A2AEx.Task.new_submitted(message, task_id: task_id, context_id: context_id)

          task_store_save(handler, new_task)
          {new_task, context_id}
      end

    req_ctx = %A2AEx.RequestContext{
      task_id: task_id,
      context_id: context_id,
      message: message,
      task: task
    }

    {:ok, task, req_ctx}
  end

  defp spawn_executor(handler, req_ctx, task_id) do
    spawn(fn ->
      try do
        handler.executor.execute(req_ctx, task_id)
      rescue
        e -> enqueue_error_event(task_id, req_ctx.context_id, Exception.message(e))
      after
        A2AEx.EventQueue.close(task_id)
      end
    end)
  end

  defp enqueue_error_event(task_id, context_id, message) do
    error_msg = A2AEx.Message.new(:agent, [%A2AEx.TextPart{text: "execution failed: #{message}"}])
    error_event = A2AEx.TaskStatusUpdateEvent.new(task_id, context_id, :failed, error_msg)
    A2AEx.EventQueue.enqueue(task_id, %{error_event | final: true})
  end

  defp update_task_from_event(handler, task_id, %A2AEx.TaskStatusUpdateEvent{} = event) do
    with {:ok, task} <- task_store_get(handler, task_id) do
      task_store_save(handler, %{task | status: event.status})
    end
  end

  defp update_task_from_event(handler, task_id, %A2AEx.TaskArtifactUpdateEvent{} = event) do
    with {:ok, task} <- task_store_get(handler, task_id) do
      artifacts = (task.artifacts || []) ++ [event.artifact]
      task_store_save(handler, %{task | artifacts: artifacts})
    end
  end

  defp update_task_from_event(_handler, _task_id, _event), do: :ok

  defp should_interrupt?(send_params, event) do
    config = send_params.config
    do_should_interrupt?(config, event)
  end

  defp do_should_interrupt?(%{blocking: false}, %A2AEx.Message{}), do: false
  defp do_should_interrupt?(%{blocking: false}, _event), do: true

  defp do_should_interrupt?(_config, %A2AEx.TaskStatusUpdateEvent{
         status: %{state: :auth_required}
       }),
       do: true

  defp do_should_interrupt?(_config, _event), do: false

  defp load_task_result(handler, task_id) do
    case task_store_get(handler, task_id) do
      {:ok, task} -> {:ok, A2AEx.Task.to_map(task)}
      {:error, :not_found} -> {:error, A2AEx.Error.new(:task_not_found, "task not found")}
    end
  end

  defp truncate_history(task, nil), do: task

  defp truncate_history(task, hist_len) when is_integer(hist_len) and hist_len <= 0 do
    %{task | history: []}
  end

  defp truncate_history(%{history: nil} = task, _), do: task

  defp truncate_history(task, hist_len) when is_integer(hist_len) do
    history = task.history || []

    if hist_len >= length(history) do
      task
    else
      %{task | history: Enum.take(history, -hist_len)}
    end
  end

  # TaskStore helpers

  defp task_store_get(%{task_store: {mod, store}}, task_id), do: mod.get(store, task_id)
  defp task_store_save(%{task_store: {mod, store}}, task), do: mod.save(store, task)
end
