# A2AEx Server Usage Rules

## RequestHandler config

```elixir
%A2AEx.RequestHandler{
  executor: MyExecutor,                               # module OR {module, config}
  task_store: {A2AEx.TaskStore.InMemory, store_pid},  # required
  agent_card: %A2AEx.AgentCard{...},                  # served at /.well-known/agent.json
  push_config_store: {A2AEx.PushConfigStore.InMemory, pid}, # optional
  push_sender: A2AEx.PushSender.HTTP,                 # optional
  extended_card: %A2AEx.AgentCard{...}                # optional, for authenticated clients
}
```

Only `executor` and `task_store` are required. Omit `push_config_store`/`push_sender` and push-related JSON-RPC methods will return `PushNotificationNotSupported` errors.

## Mounting the Plug

`A2AEx.Server` is a plain Plug. Mount it under [Bandit](https://hex.pm/packages/bandit) (pure-Elixir, recommended):

```elixir
Bandit.start_link(plug: {A2AEx.Server, handler: handler}, port: 4000)
```

Bandit is not a hard dep of `a2a_elixir_sdk` — add it to your consumer app:

```elixir
{:bandit, "~> 1.0"}
```

Routes exposed:

| Path                          | Method | Purpose                                |
|-------------------------------|--------|----------------------------------------|
| `/.well-known/agent.json`     | GET    | Agent card                             |
| `/`                           | POST   | JSON-RPC (sync + SSE based on method)  |

All JSON-RPC methods route through the same POST endpoint. Streaming methods (`message/stream`, `tasks/resubscribe`) are auto-detected and upgraded to SSE.

## AgentExecutor behaviour

```elixir
@callback execute(ctx :: A2AEx.RequestContext.t(), task_id :: String.t()) ::
            :ok | {:error, term()}
@callback cancel(ctx :: A2AEx.RequestContext.t(), task_id :: String.t()) ::
            :ok | {:error, term()}
```

The 3-arity variant `execute(ctx, task_id, config)` is used automatically when the handler is configured with `executor: {MyExecutor, config}`. Pick one shape and implement it consistently.

Executors write events to the queue via `A2AEx.EventQueue.enqueue(task_id, event)`. The final event for a task MUST have `final: true` set so the SSE stream terminates.

## Task lifecycle and terminal states

States: `:submitted` → `:working` → `:input_required` ↔ `:working` → terminal.

Terminal (absorbing) states — no further transitions:
- `:completed`, `:canceled`, `:failed`, `:rejected`

The `RequestHandler` rejects attempts to send messages to tasks already in a terminal state.

## Stores

### `TaskStore.InMemory`

```elixir
{:ok, pid} = A2AEx.TaskStore.InMemory.start_link()
# optional opts: name: :my_store
```

Backed by ETS owned by the GenServer. Not started by the app supervisor — you own the pid.

Behaviour callbacks:

```elixir
@callback get(server, task_id) :: {:ok, Task.t()} | {:error, :not_found}
@callback save(server, Task.t()) :: :ok
@callback delete(server, task_id) :: :ok
```

Swap in your own implementation by writing a module that implements `A2AEx.TaskStore` and passing `{MyStore, server}` in the handler config.

### `PushConfigStore.InMemory`

Composite key is `{task_id, config_id}` — a single task can have multiple push configs. Same start_link + `{module, server}` pattern.

## EventQueue

Started by the `:a2a_elixir_sdk` application supervisor. Uses `Registry` for per-task lookup + `DynamicSupervisor` for queue processes. Just call:

```elixir
A2AEx.EventQueue.enqueue(task_id, event)
A2AEx.EventQueue.subscribe(task_id)    # for SSE delivery
```

Events written before a subscriber attaches are buffered.

## Push notifications (webhooks)

Wire `push_config_store` + `push_sender: A2AEx.PushSender.HTTP` into the handler. The handler calls `PushSender.send(config, task)` whenever a task status changes. `PushSender.HTTP` uses Req and supports bearer/API-key auth via `PushAuthInfo`.

To implement a custom sender:

```elixir
defmodule MySender do
  @behaviour A2AEx.PushSender

  @impl true
  def send(%A2AEx.PushConfig{} = cfg, %A2AEx.Task{} = task) do
    # deliver somehow
    :ok
  end
end
```

## JSON-RPC error codes

A2A-specific codes live in `A2AEx.Error`:

- `-32001` TaskNotFound
- `-32002` TaskNotCancelable
- `-32003` PushNotificationNotSupported
- `-32004` UnsupportedOperation
- `-32005` ContentTypeNotSupported
- `-32006` InvalidAgentResponse

Standard JSON-RPC codes (`-32700` parse error, `-32600` invalid request, `-32601` method not found, `-32602` invalid params, `-32603` internal error) are also defined. Use `A2AEx.Error` helpers — do not hand-build error responses.
