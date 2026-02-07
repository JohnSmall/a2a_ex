defmodule A2AEx.ADKExecutor.Config do
  @moduledoc """
  Configuration for the ADK executor bridge.

  - `:runner` — A pre-built `ADK.Runner.t()` struct
  - `:app_name` — Application name for session management
  """

  @type t :: %__MODULE__{
          runner: ADK.Runner.t(),
          app_name: String.t()
        }

  @enforce_keys [:runner, :app_name]
  defstruct [:runner, :app_name]
end

defmodule A2AEx.ADKExecutor do
  @moduledoc """
  Bridges ADK agent execution into the A2A protocol.

  Used as `{A2AEx.ADKExecutor, config}` with `A2AEx.RequestHandler`.
  Converts A2A messages to ADK content, runs the agent via `ADK.Runner`,
  and emits A2A events (status updates + artifact updates) to the event queue.
  """

  alias A2AEx.ADKExecutor.Config
  alias A2AEx.Converter

  @doc """
  Execute an ADK agent for the given A2A request.

  Converts the incoming message, runs the agent, and streams ADK events
  as A2A status/artifact update events to the event queue.
  """
  @spec execute(Config.t(), A2AEx.RequestContext.t(), String.t()) :: :ok | {:error, term()}
  def execute(%Config{} = config, %A2AEx.RequestContext{} = req_ctx, task_id) do
    {:ok, content} = Converter.a2a_message_to_content(req_ctx.message)
    run_agent(config, req_ctx, task_id, content)
  end

  @doc """
  Cancel an in-progress ADK execution.

  Enqueues a canceled status event with `final: true`.
  """
  @spec cancel(Config.t(), A2AEx.RequestContext.t(), String.t()) :: :ok
  def cancel(%Config{}, %A2AEx.RequestContext{} = req_ctx, task_id) do
    event =
      A2AEx.TaskStatusUpdateEvent.new(task_id, req_ctx.context_id, :canceled)
      |> Map.put(:final, true)

    A2AEx.EventQueue.enqueue(task_id, event)
    :ok
  end

  # --- Private ---

  defp run_agent(config, req_ctx, task_id, content) do
    user_id = derive_user_id(req_ctx)
    session_id = req_ctx.context_id

    # Enqueue :working status
    working = A2AEx.TaskStatusUpdateEvent.new(task_id, req_ctx.context_id, :working)
    A2AEx.EventQueue.enqueue(task_id, working)

    # Run the ADK agent
    event_stream = ADK.Runner.run(config.runner, user_id, session_id, content)

    # Process events and emit final status
    acc = process_events(event_stream, task_id, req_ctx.context_id)
    emit_final(task_id, req_ctx.context_id, acc)
    :ok
  end

  defp process_events(event_stream, task_id, context_id) do
    init_acc = %{artifact_id: nil, has_artifact: false, final_state: :completed, error_message: nil}

    Enum.reduce(event_stream, init_acc, fn event, acc ->
      acc = update_terminal(acc, event)
      maybe_enqueue_artifact(event, task_id, context_id, acc)
    end)
  end

  defp maybe_enqueue_artifact(event, task_id, context_id, acc) do
    if has_content_parts?(event) do
      do_enqueue_artifact(event, task_id, context_id, acc)
    else
      acc
    end
  end

  defp do_enqueue_artifact(event, task_id, context_id, acc) do
    {:ok, a2a_parts} = Converter.adk_parts_to_a2a(event.content.parts)
    artifact_id = acc.artifact_id || A2AEx.ID.new()
    append = acc.has_artifact

    artifact = %A2AEx.Artifact{id: artifact_id, parts: a2a_parts}

    artifact_event = %A2AEx.TaskArtifactUpdateEvent{
      task_id: task_id,
      context_id: context_id,
      artifact: artifact,
      append: append
    }

    A2AEx.EventQueue.enqueue(task_id, artifact_event)
    %{acc | artifact_id: artifact_id, has_artifact: true}
  end

  defp update_terminal(acc, event) do
    state = Converter.terminal_state(event)

    case state do
      :completed -> acc
      new_state -> %{acc | final_state: new_state, error_message: event.error_message}
    end
  end

  defp emit_final(task_id, context_id, acc) do
    # Emit last_chunk artifact if we had artifacts
    if acc.has_artifact do
      last_artifact = %A2AEx.TaskArtifactUpdateEvent{
        task_id: task_id,
        context_id: context_id,
        artifact: %A2AEx.Artifact{id: acc.artifact_id, parts: []},
        append: true,
        last_chunk: true
      }

      A2AEx.EventQueue.enqueue(task_id, last_artifact)
    end

    # Build final message for failed states
    message = build_final_message(acc)

    final_event =
      A2AEx.TaskStatusUpdateEvent.new(task_id, context_id, acc.final_state, message)
      |> Map.put(:final, true)

    A2AEx.EventQueue.enqueue(task_id, final_event)
  end

  defp build_final_message(%{final_state: :failed, error_message: msg}) when is_binary(msg) do
    A2AEx.Message.new(:agent, [%A2AEx.TextPart{text: msg}])
  end

  defp build_final_message(_acc), do: nil

  defp has_content_parts?(%{content: %{parts: parts}}) when is_list(parts) and parts != [] do
    true
  end

  defp has_content_parts?(_), do: false

  defp derive_user_id(%A2AEx.RequestContext{context_id: ctx_id}) do
    "a2a_user_" <> ctx_id
  end
end
