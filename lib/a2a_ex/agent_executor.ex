defmodule A2AEx.RequestContext do
  @moduledoc """
  Context for an agent execution request.

  Carries the incoming message, task info, and metadata needed by the
  AgentExecutor to process the request.
  """

  @type t :: %__MODULE__{
          task_id: String.t(),
          context_id: String.t(),
          message: A2AEx.Message.t(),
          task: A2AEx.Task.t() | nil,
          metadata: map() | nil
        }

  @enforce_keys [:task_id, :context_id, :message]
  defstruct [:task_id, :context_id, :message, :task, :metadata]
end

defmodule A2AEx.AgentExecutor do
  @moduledoc """
  Behaviour for agent execution.

  Implementations receive a request context and write events to the event queue.
  The executor runs asynchronously — it writes `TaskStatusUpdateEvent` and
  `TaskArtifactUpdateEvent` events to the queue as work progresses, and writes
  a final event (with `final: true`) when complete.

  ## Implementing

      defmodule MyExecutor do
        @behaviour A2AEx.AgentExecutor

        @impl true
        def execute(context, task_id) do
          # Write status update: working
          A2AEx.EventQueue.enqueue(task_id, status_event(:working))

          # Do work, write artifacts...

          # Write final status: completed
          A2AEx.EventQueue.enqueue(task_id, final_event(:completed))
          :ok
        end

        @impl true
        def cancel(context, task_id) do
          A2AEx.EventQueue.enqueue(task_id, final_event(:canceled))
          :ok
        end
      end
  """

  @doc """
  Execute the agent for the given request.

  The executor should write events to the event queue identified by `task_id`.
  Returns `:ok` on success or `{:error, reason}` if execution cannot proceed.
  """
  @callback execute(context :: A2AEx.RequestContext.t(), task_id :: String.t()) ::
              :ok | {:error, term()}

  @doc """
  Cancel an in-progress execution.

  The executor should write a cancellation event to the queue and clean up.
  """
  @callback cancel(context :: A2AEx.RequestContext.t(), task_id :: String.t()) ::
              :ok | {:error, term()}
end
