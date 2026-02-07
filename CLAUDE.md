# A2AEx - Claude CLI Instructions

## Project Overview

Elixir implementation of the Agent-to-Agent (A2A) protocol. Exposes ADK agents as A2A-compatible HTTP endpoints and consumes remote A2A agents. Depends on the `adk` package (github.com/JohnSmall/adk).

## Quick Start

```bash
cd /workspace/a2a_ex
mix deps.get
mix test          # Run tests (158 passing)
mix credo         # Static analysis (0 issues)
mix dialyzer      # Type checking (0 errors)
```

## Key Documentation

- **PRD**: `docs/prd.md` — Requirements, architecture, design decisions
- **Implementation Plan**: `docs/implementation-plan.md` — Phase checklist with detailed tasks
- **Onboarding**: `docs/onboarding.md` — Full context (architecture, reference files, patterns, gotchas)

## Reference Codebases

- **A2A Go SDK (PRIMARY)**: `/workspace/a2a-go/` — Read corresponding Go file before implementing any module
- **ADK Go source**: `/workspace/adk-go/`
- **ADK-A2A bridge (Go)**: `/workspace/adk-go/server/adka2a/` — Critical for Phase 4
- **A2A Samples**: `/workspace/a2a-samples/`
- **ADK (Elixir dependency)**: `/workspace/adk/`

## Current Status

**Phase 3 COMPLETE (158 tests, credo clean, dialyzer clean). Ready for Phase 4 (ADK Integration / Bridge).**

See `docs/implementation-plan.md` for the full 6-phase plan.

## Architecture Overview

```
A2AEx.Server (@behaviour Plug)
    → A2AEx.JSONRPC (parse/encode)
        → A2AEx.RequestHandler (dispatch tables + apply/3 for 10 methods)
            → A2AEx.AgentExecutor behaviour (execute/cancel)
            → A2AEx.TaskStore behaviour (CRUD tasks)
            → A2AEx.EventQueue (SSE delivery)
            → A2AEx.PushConfigStore behaviour (webhook config)
            → A2AEx.PushSender behaviour (webhook delivery)
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

#### Phase 4+ (Planned)
| Module | Purpose | Phase |
|--------|---------|-------|
| `A2AEx.ADKExecutor` | Wraps ADK.Runner as AgentExecutor | 4 |
| `A2AEx.Converter` | ADK ↔ A2A type conversion (parts, events, messages) | 4 |
| `A2AEx.RemoteAgent` | ADK agent backed by A2A client | 4 |
| `A2AEx.Client` | HTTP client for remote A2A agents | 5 |

## Key Patterns

### Store References

All stores use `{module, server}` tuples for pluggable implementations:
```elixir
task_store: {A2AEx.TaskStore.InMemory, store_pid}
push_config_store: {A2AEx.PushConfigStore.InMemory, push_store_pid}
```

### RequestHandler Config

```elixir
%A2AEx.RequestHandler{
  executor: MyExecutor,                              # AgentExecutor module
  task_store: {A2AEx.TaskStore.InMemory, store_pid}, # Required
  agent_card: %A2AEx.AgentCard{...},                 # For /.well-known/agent.json
  push_config_store: {PushConfigStore.InMemory, pid}, # Optional
  push_sender: A2AEx.PushSender.HTTP,                # Optional
  extended_card: %A2AEx.AgentCard{...}               # Optional
}
```

### Server Usage

```elixir
# With Plug.Cowboy:
Plug.Cowboy.http(A2AEx.Server, [handler: handler], port: 4000)

# Or as a plug in your app:
plug A2AEx.Server, handler: handler
```

## Critical Rules

1. **Read Go reference first**: Before implementing any module, read the corresponding file in `/workspace/a2a-go/`
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

## Go Reference File Map

| A2AEx Module | Read This Go File |
|-------------|-------------------|
| Types (Part, Message, Task, etc.) | `/workspace/a2a-go/a2a/core.go` |
| AgentCard, Skills, Capabilities | `/workspace/a2a-go/a2a/agent.go` |
| Push notification types | `/workspace/a2a-go/a2a/push.go` |
| Error definitions | `/workspace/a2a-go/a2a/errors.go` |
| JSONRPC (error codes, methods) | `/workspace/a2a-go/internal/jsonrpc/jsonrpc.go` |
| JSONRPC handler (dispatch) | `/workspace/a2a-go/a2asrv/jsonrpc.go` |
| TaskStore | `/workspace/a2a-go/a2asrv/tasks.go` |
| EventQueue | `/workspace/a2a-go/a2asrv/eventqueue/` |
| AgentExecutor | `/workspace/a2a-go/a2asrv/agentexec.go` |
| RequestHandler | `/workspace/a2a-go/a2asrv/handler.go` |
| PushConfigStore + Sender | `/workspace/a2a-go/a2asrv/push/` |
| SSE writer | `/workspace/a2a-go/internal/sse/sse.go` |
| ADKExecutor | `/workspace/adk-go/server/adka2a/executor.go` |
| Converter | `/workspace/adk-go/server/adka2a/part_converter.go` + `event_converter.go` |
| Client | `/workspace/a2a-go/a2aclient/client.go` |
