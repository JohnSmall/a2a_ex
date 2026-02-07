defmodule A2AEx.TaskStore do
  @moduledoc """
  Behaviour for persisting A2A tasks.

  Implementations must provide get/save/delete operations keyed by task ID.
  The `store` argument is a GenServer reference (pid, name, or via tuple).
  """

  @type store :: GenServer.server()

  @doc "Retrieve a task by its ID."
  @callback get(store(), String.t()) :: {:ok, A2AEx.Task.t()} | {:error, :not_found}

  @doc "Save or update a task."
  @callback save(store(), A2AEx.Task.t()) :: :ok | {:error, term()}

  @doc "Delete a task by its ID."
  @callback delete(store(), String.t()) :: :ok
end
