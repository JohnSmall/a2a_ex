# A2AEx - Claude CLI Instructions

## Project Overview

Elixir implementation of the Agent-to-Agent (A2A) protocol. Full server+client: exposes ADK agents as A2A-compatible HTTP endpoints and consumes remote A2A agents as local ADK agents. Depends on the `adk_ex` package (path dep: `../adk_ex`).

## Quick Start

```bash
cd /workspace/elixir_code/a2a_ex
mix deps.get
mix test          # Run tests (231 passing)
mix credo         # Static analysis (0 issues)
mix dialyzer      # Type checking (0 errors)
```

## Key Documentation

- **PRD**: `docs/prd.md` — Requirements, architecture, design decisions
- **Implementation Plan**: `docs/implementation-plan.md` — Phase checklist with detailed tasks
- **Onboarding**: `docs/onboarding.md` — Full context (architecture, reference files, patterns, gotchas)

## Reference Codebases

- **A2A Go SDK (PRIMARY)**: `/workspace/samples/a2a-go/` — Read corresponding Go file before implementing any module
- **ADK Go source**: `/workspace/samples/adk-go/`
- **ADK-A2A bridge (Go)**: `/workspace/samples/adk-go/server/adka2a/` — Reference for Phase 4
- **ADK RemoteAgent (Go)**: `/workspace/samples/adk-go/agent/remoteagent/` — Reference for Phase 5
- **A2A Samples**: `/workspace/samples/a2a-samples/`
- **ADK (Elixir dependency)**: `/workspace/elixir_code/adk_ex/`
- **A2A Examples**: `/workspace/elixir_code/a2a_ex_examples/` — Example apps using A2A protocol

## Current Status

**All 6 phases COMPLETE (231 tests, credo clean, dialyzer clean).**

See `docs/implementation-plan.md` for the full 6-phase plan.

## Architecture Overview

```
Server Side:
  A2AEx.Server (@behaviour Plug)
      → A2AEx.JSONRPC (parse/encode)
          → A2AEx.RequestHandler (dispatch tables + apply/3 for 10 methods)
              → A2AEx.AgentExecutor behaviour (execute/cancel)
              → {A2AEx.ADKExecutor, config} — bridges ADK.Runner into A2A
                  → A2AEx.Converter (ADK ↔ A2A type conversion)
              → A2AEx.TaskStore behaviour (CRUD tasks)
              → A2AEx.EventQueue (SSE delivery)
              → A2AEx.PushConfigStore behaviour (webhook config)
              → A2AEx.PushSender behaviour (webhook delivery)

Client Side:
  A2AEx.Client (Req HTTP + SSE streaming)
      → A2AEx.Client.SSE (SSE line parser with buffering)
      → A2AEx.RemoteAgent (ADK agent backed by remote A2A)
          → ADK.Agent.CustomAgent (wraps run function)
          → A2AEx.Converter (A2A → ADK event conversion)
```

### Modules

#### Phase 1 (Done — 83 tests)
| Module | File | Purpose |
|--------|------|---------|
| `A2AEx.TextPart` / `FilePart` / `DataPart` | `part.ex` | Content part types |
| `A2AEx.FileBytes` / `FileURI` | `part.ex` | File content variants |
| `A2AEx.Part` | `part.ex` | Part union encode/decode |
| `A2AEx.Message` | `message.ex` | Messages with role, parts, IDs |
| `A2AEx.TaskState` / `TaskStatus` / `Task` | `task.ex` | Task lifecycle |
| `A2AEx.Artifact` | `artifact.ex` | Agent output artifacts |
| `A2AEx.TaskStatusUpdateEvent` / `TaskArtifactUpdateEvent` | `event.ex` | Streaming events |
| `A2AEx.Event` | `event.ex` | Event union decoder |
| `A2AEx.AgentCard` / `AgentCapabilities` / `AgentSkill` | `agent_card.ex` | Agent metadata |
| `A2AEx.Error` | `error.ex` | 15 error types |
| `A2AEx.JSONRPC` | `jsonrpc.ex` | JSON-RPC 2.0 layer |
| `A2AEx.TaskIDParams` / `TaskQueryParams` / `MessageSendParams` | `params.ex` | Request params |
| `A2AEx.PushConfig` / `PushAuthInfo` / `TaskPushConfig` | `push.ex` | Push notification types |
| `A2AEx.ID` | `id.ex` | UUID v4 generation |

#### Phase 2 (Done — 31 new tests, 114 total)
| Module | File | Purpose |
|--------|------|---------|
| `A2AEx.TaskStore` | `task_store.ex` | Task persistence behaviour (get/save/delete) |
| `A2AEx.TaskStore.InMemory` | `task_store/in_memory.ex` | GenServer + ETS implementation |
| `A2AEx.EventQueue` | `event_queue.ex` | Per-task event delivery (GenServer + Registry + DynamicSupervisor) |
| `A2AEx.RequestContext` | `agent_executor.ex` | Execution request context struct |
| `A2AEx.AgentExecutor` | `agent_executor.ex` | Agent execution behaviour (execute/cancel) |

#### Phase 3 (Done — 48 new tests, 158 total)
| Module | File | Purpose |
|--------|------|---------|
| `A2AEx.PushConfigStore` | `push_config_store.ex` | Push config persistence behaviour (save/get/list/delete) |
| `A2AEx.PushConfigStore.InMemory` | `push_config_store/in_memory.ex` | GenServer + ETS, composite key `{task_id, config_id}` |
| `A2AEx.PushSender` / `PushSender.HTTP` | `push_sender.ex` | Webhook delivery behaviour + Req HTTP impl |
| `A2AEx.RequestHandler` | `request_handler.ex` | Struct config + dispatch tables for all 10 methods |
| `A2AEx.Server` | `server.ex` | `@behaviour Plug` — agent card + JSON-RPC sync + SSE streaming |

#### Phase 4 (Done — 33 new tests, 191 total)
| Module | File | Purpose |
|--------|------|---------|
| `A2AEx.Converter` | `converter.ex` | Pure ADK ↔ A2A type conversion (parts, content/messages, terminal state) |
| `A2AEx.ADKExecutor.Config` | `adk_executor.ex` | Config struct (runner, app_name) for ADK executor |
| `A2AEx.ADKExecutor` | `adk_executor.ex` | Bridges ADK.Runner into A2A — used as `{ADKExecutor, config}` tuple |

#### Phase 5 (Done — 26 new tests, 217 total)
| Module | File | Purpose |
|--------|------|---------|
| `A2AEx.Client.SSE` | `client/sse.ex` | SSE line parser with cross-chunk buffering |
| `A2AEx.Client` | `client.ex` | HTTP client for all 10 JSON-RPC methods + SSE streaming |
| `A2AEx.RemoteAgent.Config` | `remote_agent.ex` | Config struct (name, url, description, client_opts) |
| `A2AEx.RemoteAgent` | `remote_agent.ex` | ADK agent backed by remote A2A server (wraps CustomAgent) |

#### Phase 6 (Done — 14 new tests, 231 total)
| Module | File | Purpose |
|--------|------|---------|
| Integration tests | `test/a2a_ex/integration_test.exs` | 14 end-to-end tests: full ADK→Server→Client pipeline over real HTTP |

## Key Patterns

### Store References

All stores use `{module, server}` tuples for pluggable implementations:
```elixir
task_store: {A2AEx.TaskStore.InMemory, store_pid}
push_config_store: {A2AEx.PushConfigStore.InMemory, push_store_pid}
```

### RequestHandler Config

```elixir
# With a bare executor module (implements AgentExecutor behaviour):
%A2AEx.RequestHandler{
  executor: MyExecutor,                              # AgentExecutor module
  task_store: {A2AEx.TaskStore.InMemory, store_pid}, # Required
  agent_card: %A2AEx.AgentCard{...},                 # For /.well-known/agent.json
  push_config_store: {PushConfigStore.InMemory, pid}, # Optional
  push_sender: A2AEx.PushSender.HTTP,                # Optional
  extended_card: %A2AEx.AgentCard{...}               # Optional
}

# With ADKExecutor (wraps ADK.Runner — 3-arity via {module, config} tuple):
config = %A2AEx.ADKExecutor.Config{runner: runner, app_name: "my-app"}
%A2AEx.RequestHandler{
  executor: {A2AEx.ADKExecutor, config},
  task_store: {A2AEx.TaskStore.InMemory, store_pid}
}
```

### Client Usage

```elixir
# Create client (default receive_timeout: 120s for LLM-backed agents)
client = A2AEx.Client.new("http://remote-host:4000")

# Override timeout for fast/local agents
client = A2AEx.Client.new("http://remote-host:4000", receive_timeout: 5_000)

# Sync: send message and get task result
{:ok, task} = A2AEx.Client.send_message(client, %{"message" => msg_map})

# Streaming: get lazy event stream
{:ok, stream} = A2AEx.Client.stream_message(client, %{"message" => msg_map})
Enum.each(stream, fn event -> IO.inspect(event) end)

# Agent card
{:ok, card} = A2AEx.Client.get_agent_card(client)
```

### RemoteAgent Usage

```elixir
# Wrap a remote A2A agent as a local ADK agent
config = %A2AEx.RemoteAgent.Config{
  name: "remote-helper",
  url: "http://remote-host:4000",
  description: "A remote helper agent"
}
agent = A2AEx.RemoteAgent.new(config)

# Use as sub-agent in orchestration, or run directly via ADK.Runner
```

### Server Usage

```elixir
# With Plug.Cowboy:
Plug.Cowboy.http(A2AEx.Server, [handler: handler], port: 4000)

# Or as a plug in your app:
plug A2AEx.Server, handler: handler
```

## Critical Rules

1. **Read Go reference first**: Before implementing any module, read the corresponding file in `/workspace/samples/a2a-go/`
2. **Compile order**: Define nested modules BEFORE parent modules in the same file
3. **Avoid MapSet**: Use `%{key => true}` maps (dialyzer opaque type issues)
4. **Credo nesting**: Max depth 2 — extract inner logic into helper functions
5. **Test module names**: Use unique names to avoid cross-file collisions
6. **Verify all changes**: Always run `mix test && mix credo && mix dialyzer`
7. **No Phoenix, no Plug.Router**: Use `@behaviour Plug` directly with manual routing
8. **Struct-based types**: Match ADK conventions (defstruct + @type)
9. **defstruct ordering**: Keyword defaults must come LAST — `[:a, :b, c: default]` not `[:a, c: default, :b]`
10. **JSON camelCase**: Use custom `Jason.Encoder` + `from_map/1` for camelCase ↔ snake_case conversion
11. **Kind discriminator**: All events/parts/tasks include `"kind"` field in JSON for polymorphic decode
12. **Dispatch tables**: Use module attribute maps + `apply/3` for method dispatch to keep cyclomatic complexity low
13. **Dialyzer strict types**: If type spec says `String.t()` but runtime value can be nil, use catch-all guards
14. **Bandit test cleanup**: Bandit has no public `stop/1`; use `Process.exit(server_pid, :normal)` + `Process.sleep(10)` in `on_exit`
15. **Client.stream_message always succeeds**: Returns `{:ok, stream}` always — errors surface inside the stream; don't add unreachable `{:error, _}` clause
16. **Client default timeout is 120s**: `Client.new/2` sets `receive_timeout: 120_000` by default (Req's default of 15s is too short for LLM-backed agents). Callers can override via opts. The server-side `collect_events` timeout in `RequestHandler` is also 120s to match.
17. **TCK mix task uses `apply/3` for Bandit**: `tck_server.ex` calls `apply(Bandit, :start_link, [...])` instead of `Bandit.start_link(...)` to avoid compile warnings when Bandit is unavailable (it's `only: [:dev, :test]` and not present when `a2a_ex` is compiled as a path dependency)

## Go Reference File Map

| A2AEx Module | Read This Go File |
|-------------|-------------------|
| Types (Part, Message, Task, etc.) | `/workspace/samples/a2a-go/a2a/core.go` |
| AgentCard, Skills, Capabilities | `/workspace/samples/a2a-go/a2a/agent.go` |
| Push notification types | `/workspace/samples/a2a-go/a2a/push.go` |
| Error definitions | `/workspace/samples/a2a-go/a2a/errors.go` |
| JSONRPC (error codes, methods) | `/workspace/samples/a2a-go/internal/jsonrpc/jsonrpc.go` |
| JSONRPC handler (dispatch) | `/workspace/samples/a2a-go/a2asrv/jsonrpc.go` |
| TaskStore | `/workspace/samples/a2a-go/a2asrv/tasks.go` |
| EventQueue | `/workspace/samples/a2a-go/a2asrv/eventqueue/` |
| AgentExecutor | `/workspace/samples/a2a-go/a2asrv/agentexec.go` |
| RequestHandler | `/workspace/samples/a2a-go/a2asrv/handler.go` |
| PushConfigStore + Sender | `/workspace/samples/a2a-go/a2asrv/push/` |
| SSE writer | `/workspace/samples/a2a-go/internal/sse/sse.go` |
| ADKExecutor | `/workspace/samples/adk-go/server/adka2a/executor.go` |
| Converter | `/workspace/samples/adk-go/server/adka2a/part_converter.go` + `event_converter.go` |
| Client | `/workspace/samples/a2a-go/a2aclient/client.go` |
| RemoteAgent | `/workspace/samples/adk-go/agent/remoteagent/a2a_agent.go` |
