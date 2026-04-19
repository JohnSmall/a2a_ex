# A2A Elixir SDK Usage Rules

`a2a_elixir_sdk` (module namespace `A2AEx.*`) is an Elixir implementation of the [Agent-to-Agent (A2A) protocol](https://github.com/a2aproject/A2A). It is a full server + client: expose ADK agents as A2A-compatible HTTP endpoints, and consume remote A2A agents as local ADK agents. Depends on [`adk_ex`](https://hex.pm/packages/adk_ex).

## Architecture

```
Server side:
  A2AEx.Server (@behaviour Plug)
      -> A2AEx.JSONRPC (parse/encode)
          -> A2AEx.RequestHandler (dispatch for 10 JSON-RPC methods)
              -> A2AEx.AgentExecutor behaviour (execute/cancel)
                 | {A2AEx.ADKExecutor, config} bridges ADK.Runner
              -> A2AEx.TaskStore (CRUD tasks)
              -> A2AEx.EventQueue (SSE delivery)
              -> A2AEx.PushConfigStore (webhook config)
              -> A2AEx.PushSender (webhook delivery)

Client side:
  A2AEx.Client (Req HTTP + SSE)
      -> A2AEx.Client.SSE (line parser with buffering)
      -> A2AEx.RemoteAgent (ADK agent backed by remote A2A)
          -> A2AEx.Converter (A2A -> ADK event conversion)
```

## Core Patterns

### Expose an ADK agent as an A2A endpoint

```elixir
# 1. Build an ADK agent + runner (see adk_ex usage-rules for details)
agent = %ADK.Agent.LlmAgent{name: "my-agent", ...}
{:ok, session_svc} = ADK.Session.InMemory.start_link()
{:ok, runner} = ADK.Runner.new(
  app_name: "my-app", root_agent: agent, session_service: session_svc
)

# 2. Start stores
{:ok, store} = A2AEx.TaskStore.InMemory.start_link()

# 3. Wire up the request handler — note the {module, config} executor tuple
config = %A2AEx.ADKExecutor.Config{runner: runner, app_name: "my-app"}
handler = %A2AEx.RequestHandler{
  executor: {A2AEx.ADKExecutor, config},
  task_store: {A2AEx.TaskStore.InMemory, store},
  agent_card: %A2AEx.AgentCard{
    name: "My Agent",
    url: "http://localhost:4000",
    version: "1.0.0"
  }
}

# 4. Start the HTTP server (Bandit or Plug.Cowboy)
{:ok, _} = Bandit.start_link(plug: {A2AEx.Server, handler: handler}, port: 4000)
```

### Consume a remote A2A agent (standalone client)

```elixir
# Default receive_timeout is 120s — tuned for LLM-backed agents.
client = A2AEx.Client.new("http://remote:4000")
# Override for fast/local agents:
client = A2AEx.Client.new("http://remote:4000", receive_timeout: 5_000)

{:ok, card} = A2AEx.Client.get_agent_card(client)

params = %{"message" => %{
  "role" => "user",
  "parts" => [%{"kind" => "text", "text" => "Hello"}]
}}
{:ok, task} = A2AEx.Client.send_message(client, params)

# Streaming: always returns {:ok, stream}; errors surface inside the stream.
{:ok, stream} = A2AEx.Client.stream_message(client, params)
Enum.each(stream, &IO.inspect/1)
```

### Use a remote A2A agent as a local ADK sub-agent

```elixir
remote = A2AEx.RemoteAgent.new(%A2AEx.RemoteAgent.Config{
  name: "remote-helper",
  url: "http://remote:4000",
  description: "Remote helper"
})
# Use as sub-agent inside SequentialAgent/ParallelAgent/etc.
```

### Custom executor (without ADK)

```elixir
defmodule MyExecutor do
  @behaviour A2AEx.AgentExecutor

  @impl true
  def execute(ctx, task_id) do
    A2AEx.EventQueue.enqueue(task_id,
      A2AEx.TaskStatusUpdateEvent.new(task_id, ctx.context_id, :working))

    reply = A2AEx.Message.new(:agent, [%A2AEx.TextPart{text: "Hi"}])
    final = A2AEx.TaskStatusUpdateEvent.new(task_id, ctx.context_id, :completed, reply)
    A2AEx.EventQueue.enqueue(task_id, %{final | final: true})
    :ok
  end

  @impl true
  def cancel(_ctx, _task_id), do: :ok
end
```

## Critical Rules

1. **Store references are `{module, server}` tuples.** Pass
   `{A2AEx.TaskStore.InMemory, pid}` — not a bare pid or a bare module.
   Same shape for `push_config_store`.

2. **Executor can be a bare module OR a `{module, config}` tuple.** Bare module
   is called as `execute(ctx, task_id)` (2-arity). A tuple is called as
   `execute(ctx, task_id, config)` (3-arity). `A2AEx.ADKExecutor` *requires*
   the tuple form because it needs runner + app_name config.

3. **Default client timeout is 120s (`receive_timeout: 120_000`).** Req's
   default of 15s is too short for LLM-backed agents. The server's
   `collect_events` timeout in `RequestHandler` also defaults to 120s.
   Override via `A2AEx.Client.new/2` opts if you need faster failures.

4. **`Client.stream_message/2` always returns `{:ok, stream}`.** Do not
   pattern-match on `{:error, _}` at the call site — errors surface inside the
   stream as it is enumerated.

5. **JSON uses camelCase on the wire, snake_case in Elixir.** All A2A types
   implement `Jason.Encoder` + `from_map/1` to translate. Never hand-roll
   JSON — go through the type constructors.

6. **Every polymorphic type has a `"kind"` discriminator.** Parts
   (`text`/`file`/`data`), events (`status-update`/`artifact-update`), tasks
   (`task`/`message`). Use `A2AEx.Part.from_map/1`, `A2AEx.Event.from_map/1`
   to decode — they dispatch on `"kind"`.

7. **No Phoenix, no Plug.Router.** `A2AEx.Server` implements `@behaviour Plug`
   directly with manual routing. Mount it with Bandit or Plug.Cowboy:
   `Bandit.start_link(plug: {A2AEx.Server, handler: handler}, port: 4000)`.

8. **Terminal task states are absorbing.** `:completed`, `:canceled`,
   `:failed`, `:rejected` cannot transition further. `A2AEx.Converter` tests
   terminal state when mapping ADK events.

9. **Mark final SSE event with `final: true`.** `%{final_event | final: true}`
   tells the event queue and SSE writer to terminate the stream after
   delivering the event. Forgetting this leaves the client hanging.

10. **Agent card is served at `/.well-known/agent.json`.** Populate at
    minimum: `name`, `url`, `version`. Capabilities (streaming,
    pushNotifications) default to false — set them explicitly if supported.

## Common Gotchas

- `TaskStore.InMemory` is a `GenServer` + ETS — call `start_link/1` and pass
  the returned pid in the tuple. It is not automatically started by the
  application supervisor.
- `EventQueue` uses `Registry` + `DynamicSupervisor`; these *are* started by
  the `:a2a_elixir_sdk` application supervisor, so just call `EventQueue.enqueue/2`.
- Push notifications are opt-in. Only wire `push_config_store` + `push_sender`
  into the `RequestHandler` if you actually want webhook delivery.
- Bandit has no public `stop/1`. In tests use
  `Process.exit(pid, :normal)` + `Process.sleep(10)` for cleanup.
- `defstruct` keyword defaults must come last: `[:a, :b, c: default]`, never
  `[:a, c: default, :b]`.

## Sub-rules

For deeper guidance on specific topics, see the `usage-rules/` directory:

- `a2a_elixir_sdk:server` — building a server, custom executors, stores, push
- `a2a_elixir_sdk:client` — client + RemoteAgent, streaming, timeouts
- `a2a_elixir_sdk:adk_bridge` — ADKExecutor and Converter semantics
- `a2a_elixir_sdk:types` — message/part/task/event encode/decode conventions
