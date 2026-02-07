# A2AEx

Elixir implementation of the [Agent-to-Agent (A2A) protocol](https://github.com/a2aproject/A2A). Exposes ADK agents as A2A-compatible HTTP endpoints and enables inter-agent communication over JSON-RPC.

## Features

- **Full A2A protocol support** — All 10 JSON-RPC methods (message/send, message/stream, tasks/get, tasks/cancel, push config CRUD, etc.)
- **Server** — Plug-based HTTP endpoint with JSON-RPC dispatch and SSE streaming
- **ADK Integration** — Bridge ADK agents into the A2A protocol via `ADKExecutor` + `Converter`
- **Agent Card** — Serve agent metadata at `/.well-known/agent.json`
- **Push Notifications** — Webhook-based task update delivery
- **Pluggable Storage** — Behaviour-based `TaskStore` and `PushConfigStore` with in-memory implementations

## Quick Start

```elixir
# mix.exs
def deps do
  [
    {:a2a_ex, github: "JohnSmall/a2a_ex"}
  ]
end
```

### Expose an ADK Agent as an A2A Endpoint

```elixir
# Build your ADK agent and runner
agent = ADK.Agent.CustomAgent.new(%ADK.Agent.Config{
  name: "my-agent",
  run: fn _ctx -> [ADK.Event.new(content: ADK.Types.Content.new_from_text("model", "Hello!"))] end
})

{:ok, session_svc} = ADK.Session.InMemory.start_link()
{:ok, runner} = ADK.Runner.new(app_name: "my-app", root_agent: agent, session_service: session_svc)

# Configure the A2A handler
{:ok, store} = A2AEx.TaskStore.InMemory.start_link()
config = %A2AEx.ADKExecutor.Config{runner: runner, app_name: "my-app"}

handler = %A2AEx.RequestHandler{
  executor: {A2AEx.ADKExecutor, config},
  task_store: {A2AEx.TaskStore.InMemory, store},
  agent_card: %A2AEx.AgentCard{name: "My Agent", url: "http://localhost:4000"}
}

# Start the server with Plug.Cowboy
Plug.Cowboy.http(A2AEx.Server, [handler: handler], port: 4000)
```

### Custom Executor (without ADK)

```elixir
defmodule MyExecutor do
  @behaviour A2AEx.AgentExecutor

  @impl true
  def execute(ctx, task_id) do
    A2AEx.EventQueue.enqueue(task_id,
      A2AEx.TaskStatusUpdateEvent.new(task_id, ctx.context_id, :working))

    reply = A2AEx.Message.new(:agent, [%A2AEx.TextPart{text: "Hello from my agent!"}])
    final = A2AEx.TaskStatusUpdateEvent.new(task_id, ctx.context_id, :completed, reply)
    A2AEx.EventQueue.enqueue(task_id, %{final | final: true})
    :ok
  end

  @impl true
  def cancel(_ctx, _task_id), do: :ok
end
```

## Architecture

```
A2AEx.Server (@behaviour Plug)
    -> A2AEx.JSONRPC (parse/encode)
        -> A2AEx.RequestHandler (dispatch for 10 methods)
            -> A2AEx.AgentExecutor (execute/cancel)
            -> {A2AEx.ADKExecutor, config} (ADK bridge)
                -> A2AEx.Converter (ADK <-> A2A types)
            -> A2AEx.TaskStore (task persistence)
            -> A2AEx.EventQueue (SSE event delivery)
            -> A2AEx.PushConfigStore (webhook config)
            -> A2AEx.PushSender (webhook delivery)
```

## Status

**Phase 4 complete** — 191 tests, credo clean, dialyzer clean.

| Phase | Status | Tests |
|-------|--------|-------|
| 1. Core Types + JSON-RPC | Done | 83 |
| 2. TaskStore + EventQueue + AgentExecutor | Done | 31 |
| 3. RequestHandler + Server | Done | 44 |
| 4. ADK Integration (Converter + ADKExecutor) | Done | 33 |
| 5. Client + RemoteAgent | Next | -- |
| 6. Integration Testing | Planned | -- |

## Development

```bash
mix deps.get       # Fetch dependencies
mix test           # Run tests (191 passing)
mix credo          # Static analysis (0 issues)
mix dialyzer       # Type checking (0 errors)
```

## Dependencies

- [ADK](https://github.com/JohnSmall/adk) — Agent Development Kit for Elixir
- [Plug](https://hex.pm/packages/plug) — HTTP server interface
- [Jason](https://hex.pm/packages/jason) — JSON encoding/decoding
- [Req](https://hex.pm/packages/req) — HTTP client (for push notification delivery)

## License

MIT
