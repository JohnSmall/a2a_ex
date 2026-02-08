# A2AEx

Elixir implementation of the [Agent-to-Agent (A2A) protocol](https://github.com/a2aproject/A2A). Exposes ADK agents as A2A-compatible HTTP endpoints and enables inter-agent communication over JSON-RPC.

## Features

- **Full A2A protocol support** — All 10 JSON-RPC methods (message/send, message/stream, tasks/get, tasks/cancel, push config CRUD, etc.)
- **Server** — Plug-based HTTP endpoint with JSON-RPC dispatch and SSE streaming
- **Client** — HTTP client for consuming remote A2A agents (sync + streaming via SSE)
- **ADK Integration** — Bridge ADK agents into the A2A protocol via `ADKExecutor` + `Converter`
- **RemoteAgent** — Wrap any remote A2A agent as a local ADK agent for orchestration
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

### Consume a Remote A2A Agent

```elixir
# As a standalone client
client = A2AEx.Client.new("http://remote-host:4000")
{:ok, card} = A2AEx.Client.get_agent_card(client)

params = %{"message" => %{"role" => "user", "parts" => [%{"kind" => "text", "text" => "Hello!"}]}}
{:ok, task} = A2AEx.Client.send_message(client, params)

# Or stream events
{:ok, stream} = A2AEx.Client.stream_message(client, params)
Enum.each(stream, &IO.inspect/1)
```

### Use a Remote Agent in ADK Orchestration

```elixir
# Wrap as an ADK agent for use in Sequential/Parallel/etc.
remote = A2AEx.RemoteAgent.new(%A2AEx.RemoteAgent.Config{
  name: "remote-helper",
  url: "http://remote-host:4000",
  description: "Remote A2A agent"
})

# Use as sub-agent in a SequentialAgent, ParallelAgent, or directly via Runner
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
Server:                                Client:
  A2AEx.Server (Plug)                    A2AEx.Client (Req HTTP)
      -> JSONRPC (parse/encode)              -> Client.SSE (SSE parser)
          -> RequestHandler                  -> RemoteAgent (ADK agent wrapper)
              -> AgentExecutor                   -> Converter (A2A -> ADK)
              -> {ADKExecutor, config}
                  -> Converter (ADK <-> A2A)
              -> TaskStore, EventQueue
              -> PushConfigStore, PushSender
```

## Status

**All 6 phases complete** — 231 tests, credo clean, dialyzer clean.

| Phase | Status | Tests |
|-------|--------|-------|
| 1. Core Types + JSON-RPC | Done | 83 |
| 2. TaskStore + EventQueue + AgentExecutor | Done | 31 |
| 3. RequestHandler + Server | Done | 44 |
| 4. ADK Integration (Converter + ADKExecutor) | Done | 33 |
| 5. Client + RemoteAgent | Done | 26 |
| 6. Integration Testing | Done | 14 |

## Development

```bash
mix deps.get       # Fetch dependencies
mix test           # Run tests (231 passing)
mix credo          # Static analysis (0 issues)
mix dialyzer       # Type checking (0 errors)
```

## Dependencies

- [ADK](https://github.com/JohnSmall/adk) — Agent Development Kit for Elixir
- [Plug](https://hex.pm/packages/plug) — HTTP server interface
- [Jason](https://hex.pm/packages/jason) — JSON encoding/decoding
- [Req](https://hex.pm/packages/req) — HTTP client (for push delivery, A2A client, and RemoteAgent)
- [Bandit](https://hex.pm/packages/bandit) — HTTP server (test-only, for client/RemoteAgent integration tests)

## License

MIT
