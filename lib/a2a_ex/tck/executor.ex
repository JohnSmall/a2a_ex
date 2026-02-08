defmodule A2AEx.TCK.Executor do
  @moduledoc """
  Custom AgentExecutor for A2A TCK compliance testing.

  Implements an echo agent that responds to messages:
  - "hello" or "hi" → "Hello World!"
  - anything else → echoes back the input

  For messages with messageId starting with "test-resubscribe-message-id-",
  runs a long-running task that emits periodic events so the TCK can test
  tasks/resubscribe functionality.
  """

  @behaviour A2AEx.AgentExecutor

  @impl true
  def execute(ctx, task_id) do
    context_id = ctx.context_id

    # Emit working status
    enqueue_status(task_id, context_id, :working)

    if resubscribe_message?(ctx.message) do
      run_slow(task_id, context_id, ctx)
    else
      # Small delay for streaming tests to pick up working event
      Process.sleep(50)
      run_echo(task_id, context_id, ctx)
    end

    :ok
  end

  @impl true
  def cancel(_ctx, _task_id), do: :ok

  # --- Private ---

  defp resubscribe_message?(%A2AEx.Message{id: id}) when is_binary(id) do
    String.starts_with?(id, "test-resubscribe-message-id")
  end

  defp resubscribe_message?(_), do: false

  defp run_echo(task_id, context_id, ctx) do
    input_text = extract_text(ctx.message)
    response_text = generate_response(input_text)

    # Emit artifact
    artifact = %A2AEx.Artifact{
      id: A2AEx.ID.new(),
      name: "response",
      parts: [%A2AEx.TextPart{text: response_text}]
    }

    artifact_event = %A2AEx.TaskArtifactUpdateEvent{
      task_id: task_id,
      context_id: context_id,
      artifact: artifact
    }

    A2AEx.EventQueue.enqueue(task_id, artifact_event)

    # Emit completed status with response message
    response_msg =
      A2AEx.Message.new(:agent, [%A2AEx.TextPart{text: response_text}])

    completed_event =
      A2AEx.TaskStatusUpdateEvent.new(task_id, context_id, :completed, response_msg)

    A2AEx.EventQueue.enqueue(task_id, %{completed_event | final: true})
  end

  defp run_slow(task_id, context_id, _ctx) do
    # Emit periodic working events so resubscribe test can pick them up.
    # Total duration: ~6 seconds with events every 500ms.
    Enum.each(1..12, fn i ->
      Process.sleep(500)

      msg =
        A2AEx.Message.new(:agent, [
          %A2AEx.TextPart{text: "Still working... (#{i})"}
        ])

      event = A2AEx.TaskStatusUpdateEvent.new(task_id, context_id, :working, msg)
      A2AEx.EventQueue.enqueue(task_id, event)
    end)

    # Finally complete
    response_msg =
      A2AEx.Message.new(:agent, [%A2AEx.TextPart{text: "Long task completed"}])

    completed_event =
      A2AEx.TaskStatusUpdateEvent.new(task_id, context_id, :completed, response_msg)

    A2AEx.EventQueue.enqueue(task_id, %{completed_event | final: true})
  end

  defp extract_text(%A2AEx.Message{parts: parts}) do
    parts
    |> Enum.find_value("", fn
      %A2AEx.TextPart{text: text} -> text
      _ -> nil
    end)
  end

  defp generate_response(input) do
    case String.downcase(String.trim(input)) do
      "hello" -> "Hello World!"
      "hi" -> "Hello World!"
      _ -> "Echo: #{input}"
    end
  end

  defp enqueue_status(task_id, context_id, state) do
    event = A2AEx.TaskStatusUpdateEvent.new(task_id, context_id, state)
    A2AEx.EventQueue.enqueue(task_id, event)
  end
end
