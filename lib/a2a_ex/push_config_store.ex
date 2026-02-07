defmodule A2AEx.PushConfigStore do
  @moduledoc """
  Behaviour for managing push notification configurations for tasks.

  Each task can have multiple push configs, keyed by config ID.
  """

  @type store :: GenServer.server()

  @doc "Save a push config for a task. Assigns an ID if not set. Returns the saved config."
  @callback save(store(), String.t(), A2AEx.PushConfig.t()) ::
              {:ok, A2AEx.PushConfig.t()} | {:error, term()}

  @doc "Get a push config by task ID and config ID."
  @callback get(store(), String.t(), String.t()) ::
              {:ok, A2AEx.PushConfig.t()} | {:error, :not_found}

  @doc "List all push configs for a task."
  @callback list(store(), String.t()) :: {:ok, [A2AEx.PushConfig.t()]}

  @doc "Delete a push config by task ID and config ID."
  @callback delete(store(), String.t(), String.t()) :: :ok
end
