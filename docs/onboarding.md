# Onboarding Guide: A2AEx (Agent-to-Agent Protocol for Elixir)

## For New AI Agents / Developers

This document provides everything needed to pick up the A2AEx project.

---

## 1. What Is This Project?

A2AEx is an **Elixir implementation of the Agent-to-Agent (A2A) protocol**. A2A is an open standard for AI agent interoperability over HTTP using JSON-RPC.

A2AEx provides:
- **Server**: Expose any ADK agent as an A2A-compatible HTTP endpoint
- **Client**: Consume remote A2A agents
- **Bridge**: Convert between ADK events and A2A messages/tasks
- **RemoteAgent**: Wrap a remote A2A agent as a local ADK agent

**This package depends on the ADK package** (github.com/JohnSmall/adk), which provides the agent framework (agents, runner, sessions, tools, LLM abstraction).

---

## 2. Current Status

**Phase 3 COMPLETE — 158 tests, credo clean, dialyzer clean. Ready for Phase 4.**

### What's Built (Phase 1: Core Types + JSON-RPC — 83 tests)

| Module | File | Purpose |
|--------|------|---------|
| `A2AEx.TextPart` / `FilePart` / `DataPart` | `lib/a2a_ex/part.ex` | Content part union types |
| `A2AEx.FileBytes` / `FileURI` | `lib/a2a_ex/part.ex` | File content variants |
| `A2AEx.Part` | `lib/a2a_ex/part.ex` | Part union: `from_map/1`, `to_map/1`, `from_map_list/1` |
| `A2AEx.Message` | `lib/a2a_ex/message.ex` | Messages with role, parts, IDs |
| `A2AEx.TaskState` | `lib/a2a_ex/task.ex` | 10 task states + `terminal?/1` |
| `A2AEx.TaskStatus` | `lib/a2a_ex/task.ex` | State + message + timestamp |
| `A2AEx.Task` | `lib/a2a_ex/task.ex` | Core work unit + `new_submitted/1` |
| `A2AEx.Artifact` | `lib/a2a_ex/artifact.ex` | Agent output artifacts |
| `A2AEx.TaskStatusUpdateEvent` | `lib/a2a_ex/event.ex` | Task state change event |
| `A2AEx.TaskArtifactUpdateEvent` | `lib/a2a_ex/event.ex` | Artifact update event |
| `A2AEx.Event` | `lib/a2a_ex/event.ex` | Event union decoder (`from_map/1`) |
| `A2AEx.AgentCard` | `lib/a2a_ex/agent_card.ex` | Agent metadata manifest |
| `A2AEx.AgentCapabilities` | `lib/a2a_ex/agent_card.ex` | Streaming, push, history flags |
| `A2AEx.AgentSkill` | `lib/a2a_ex/agent_card.ex` | Skill definition |
| `A2AEx.AgentProvider` | `lib/a2a_ex/agent_card.ex` | Provider info |
| `A2AEx.TaskIDParams` / `TaskQueryParams` | `lib/a2a_ex/params.ex` | Request parameter types |
| `A2AEx.MessageSendParams` / `MessageSendConfig` | `lib/a2a_ex/params.ex` | Send request params |
| `A2AEx.PushConfig` / `PushAuthInfo` / `TaskPushConfig` | `lib/a2a_ex/push.ex` | Push notification config |
| `A2AEx.GetTaskPushConfigParams` + 2 more | `lib/a2a_ex/push.ex` | Push config request params |
| `A2AEx.Error` | `lib/a2a_ex/error.ex` | 15 error types with messages |
| `A2AEx.JSONRPC` | `lib/a2a_ex/jsonrpc.ex` | JSON-RPC 2.0 encode/decode |
| `A2AEx.ID` | `lib/a2a_ex/id.ex` | UUID v4 generation |

### What's Built (Phase 2: TaskStore + EventQueue + AgentExecutor — 31 tests)

| Module | File | Purpose |
|--------|------|---------|
| `A2AEx.TaskStore` | `lib/a2a_ex/task_store.ex` | Behaviour: `get/2`, `save/2`, `delete/2` |
| `A2AEx.TaskStore.InMemory` | `lib/a2a_ex/task_store/in_memory.ex` | GenServer + ETS (serialized writes, concurrent reads) |
| `A2AEx.EventQueue` | `lib/a2a_ex/event_queue.ex` | Per-task GenServer + Registry; subscribe/enqueue/close |
| `A2AEx.RequestContext` | `lib/a2a_ex/agent_executor.ex` | Execution context (task_id, context_id, message, task) |
| `A2AEx.AgentExecutor` | `lib/a2a_ex/agent_executor.ex` | Behaviour: `execute/2`, `cancel/2` |

### What's Built (Phase 3: RequestHandler + Server — 48 tests)

| Module | File | Purpose |
|--------|------|---------|
| `A2AEx.PushConfigStore` | `lib/a2a_ex/push_config_store.ex` | Behaviour: `save/3`, `get/3`, `list/2`, `delete/3` |
| `A2AEx.PushConfigStore.InMemory` | `lib/a2a_ex/push_config_store/in_memory.ex` | GenServer + ETS, composite key `{task_id, config_id}` |
| `A2AEx.PushSender` | `lib/a2a_ex/push_sender.ex` | Behaviour: `send_push/2` |
| `A2AEx.PushSender.HTTP` | `lib/a2a_ex/push_sender.ex` | Req-based webhook delivery (Bearer/Basic auth) |
| `A2AEx.RequestHandler` | `lib/a2a_ex/request_handler.ex` | Struct config + dispatch for all 10 JSON-RPC methods |
| `A2AEx.Server` | `lib/a2a_ex/server.ex` | `@behaviour Plug` — agent card + JSON-RPC + SSE streaming |

### What's Next (Phase 4: ADK Integration / Bridge)

| Module | Purpose |
|--------|---------|
| `A2AEx.ADKExecutor` | Wraps `ADK.Runner` as `A2AEx.AgentExecutor` |
| `A2AEx.Converter` | ADK ↔ A2A type conversion (parts, events, messages) |
| `A2AEx.RemoteAgent` | ADK agent backed by A2A client |

### What's Built in ADK (Dependency)

The ADK package at `/workspace/adk/` has Phases 1-3 complete (168 tests):
- All agent types (LLM, Loop, Sequential, Parallel, Custom)
- Runner, Flow engine, Tool system
- Session management (in-memory)
- Model providers (Gemini, Claude, Mock)
- Agent transfer

---

## 3. Key Resources

### Local Files

| Resource | Location |
|----------|----------|
| **This project (A2AEx)** | `/workspace/a2a_ex/` |
| **ADK (dependency)** | `/workspace/adk/` |
| **A2A Go SDK (PRIMARY reference)** | `/workspace/a2a-go/` |
| **ADK Go source** | `/workspace/adk-go/` |
| **ADK-A2A bridge (Go)** | `/workspace/adk-go/server/adka2a/` |
| **A2A samples** | `/workspace/a2a-samples/` |
| **PRD** | `/workspace/a2a_ex/docs/prd.md` |
| **Implementation plan** | `/workspace/a2a_ex/docs/implementation-plan.md` |
| **This guide** | `/workspace/a2a_ex/docs/onboarding.md` |

### External Documentation

| Resource | URL |
|----------|-----|
| A2A protocol spec | https://github.com/a2aproject/A2A |
| Google ADK docs | https://google.github.io/adk-docs/ |

---

## 4. A2A Protocol Quick Reference

### Core Concepts

- **Agent Card**: JSON metadata at `/.well-known/agent.json` describing agent capabilities
- **Task**: Unit of work with lifecycle states: `submitted → working → input_required → completed/failed/canceled`
- **Message**: Contains Parts (text, file, data) with a role (:user or :agent)
- **Artifact**: Output produced by an agent during task execution

### JSON-RPC Methods

| Method | Direction | Purpose |
|--------|-----------|---------|
| `message/send` | Client → Server | Send message, get sync response |
| `message/stream` | Client → Server | Send message, get SSE stream |
| `tasks/get` | Client → Server | Get task status + artifacts |
| `tasks/cancel` | Client → Server | Cancel running task |
| `tasks/resubscribe` | Client → Server | Re-subscribe to task SSE |
| `tasks/pushNotificationConfig/set` | Client → Server | Register webhook |
| `tasks/pushNotificationConfig/get` | Client → Server | Get webhook config |
| `tasks/pushNotificationConfig/delete` | Client → Server | Remove webhook |
| `tasks/pushNotificationConfig/list` | Client → Server | List webhooks |
| `agent/getAuthenticatedExtendedCard` | Client → Server | Get extended card |

### SSE Event Types

| Event | Payload | When |
|-------|---------|------|
| `TaskStatusUpdateEvent` | `{id, status, final}` | Task state changes |
| `TaskArtifactUpdateEvent` | `{id, artifact}` | New artifact produced |

---

## 5. Architecture

### Server Stack

```
A2AEx.Server (@behaviour Plug)
    → Routes: GET /.well-known/agent.json, POST /
    → JSON-RPC: A2AEx.JSONRPC.decode_request/1
        → Sync methods: RequestHandler.handle → send_jsonrpc_response
        → Stream methods: RequestHandler.handle → {:stream, task_id} → SSE
            → A2AEx.RequestHandler (dispatch tables + apply/3)
                → message/send: parse → validate → prepare_execution → EventQueue → spawn_executor → collect → result
                → message/stream: same but returns {:stream, task_id} for SSE
                → tasks/get: TaskStore.get + optional history truncation
                → tasks/cancel: validate cancelable + update status
                → tasks/resubscribe: EventQueue.subscribe for existing queue
                → push config: PushConfigStore CRUD (save/get/list/delete)
                → extended card: return configured AgentCard
                    → A2AEx.AgentExecutor (execute/cancel — the actual agent)
                    → A2AEx.TaskStore (get/save/delete — task persistence)
                    → A2AEx.EventQueue (subscribe/enqueue/close — SSE delivery)
                    → A2AEx.PushConfigStore (save/get/list/delete — webhook config)
                    → A2AEx.PushSender (send_push — webhook delivery)
```

### Elixir Mapping

| Go SDK Component | Elixir Module | OTP Pattern |
|-----------------|---------------|-------------|
| `AgentExecutor` interface | `A2AEx.AgentExecutor` behaviour | `@callback` |
| `TaskStore` interface | `A2AEx.TaskStore` behaviour | `@callback` |
| `InMemoryTaskStore` | `A2AEx.TaskStore.InMemory` | GenServer + ETS |
| `EventQueue` + Manager | `A2AEx.EventQueue` | GenServer + Registry + DynamicSupervisor |
| `RequestHandler` | `A2AEx.RequestHandler` | Struct config + dispatch tables |
| `A2AServer` | `A2AEx.Server` | `@behaviour Plug` (manual routing) |
| `JSONRPCHandler` | `A2AEx.JSONRPC` | Module functions |
| `PushConfigStore` | `A2AEx.PushConfigStore` | Behaviour + InMemory (GenServer + ETS) |
| `PushSender` | `A2AEx.PushSender.HTTP` | Req-based HTTP |
| `Client` | `A2AEx.Client` | Req HTTP client (Phase 5) |
| ADK Executor | `A2AEx.ADKExecutor` | Wraps ADK.Runner (Phase 4) |
| Part/Event converters | `A2AEx.Converter` | Pure functions (Phase 4) |
| `AgentCard` | `A2AEx.AgentCard` | Struct |
| `RemoteAgent` | `A2AEx.RemoteAgent` | `@behaviour ADK.Agent` (Phase 4) |

### ADK-A2A Bridge (Phase 4)

The bridge connects ADK's event-sourced model to A2A's task-based model:

```
ADK Side:                          A2A Side:
ADK.Runner.run/5                   message/send or message/stream
  → Stream of ADK.Event      →    TaskStatusUpdateEvent (state changes)
  → Events with artifacts     →    TaskArtifactUpdateEvent (outputs)
  → Events with text content  →    Task.status.message (final response)
  → escalate/transfer actions →    Task state = completed/failed
```

Key conversion rules:
- ADK text event → A2A Message with Text part
- ADK blob part → A2A File part
- ADK function_call/function_response → internal (not exposed in A2A)
- ADK escalate action → A2A task state = `completed` or `input_required`
- ADK final_response event → A2A task state = `completed`

---

## 6. Reference: A2A Go SDK Key Files

Read these files in order when implementing each phase:

### Phase 1: Types + JSON-RPC (DONE)
- `/workspace/a2a-go/a2a/core.go` — Core types (Task, Message, Part, Artifact, events, params)
- `/workspace/a2a-go/a2a/agent.go` — AgentCard, AgentCapabilities, AgentSkill, AgentProvider
- `/workspace/a2a-go/a2a/push.go` — Push notification types
- `/workspace/a2a-go/a2a/auth.go` — Security scheme types
- `/workspace/a2a-go/a2a/errors.go` — Error sentinel values
- `/workspace/a2a-go/internal/jsonrpc/jsonrpc.go` — Error codes, method names
- `/workspace/a2a-go/a2asrv/jsonrpc.go` — JSON-RPC handler, request/response structs

### Phase 2: Storage + Execution (DONE)
- `/workspace/a2a-go/a2asrv/tasks.go` — TaskStore interface
- `/workspace/a2a-go/a2asrv/eventqueue/` — EventQueue, Manager, InMemory implementations
- `/workspace/a2a-go/a2asrv/agentexec.go` — AgentExecutor interface

### Phase 3: Server (DONE)
- `/workspace/a2a-go/a2asrv/jsonrpc.go` — JSONRPC handler + method dispatch
- `/workspace/a2a-go/a2asrv/handler.go` — RequestHandler interface + implementation
- `/workspace/a2a-go/a2asrv/push/` — PushConfigStore + PushSender
- `/workspace/a2a-go/internal/sse/sse.go` — SSE writer (WriteHeaders, WriteData, WriteKeepAlive)

### Phase 4: ADK Bridge (NEXT)
- `/workspace/adk-go/server/adka2a/executor.go` — ADK Runner → AgentExecutor wrapper
- `/workspace/adk-go/server/adka2a/part_converter.go` — Part type conversion
- `/workspace/adk-go/server/adka2a/event_converter.go` — Event → A2A event conversion

### Phase 5: Client
- `/workspace/a2a-go/a2aclient/client.go` — Client implementation
- `/workspace/a2a-go/a2aclient/transport.go` — HTTP transport
- `/workspace/a2a-go/a2aclient/jsonrpc.go` — Client-side JSON-RPC helpers

---

## 7. How Phase 3 Works (RequestHandler + Server)

### RequestHandler Design

The `A2AEx.RequestHandler` is a struct (not a GenServer) containing pluggable configuration:

```elixir
%A2AEx.RequestHandler{
  executor: MyExecutor,                              # AgentExecutor module
  task_store: {A2AEx.TaskStore.InMemory, store_pid}, # {module, server} tuple
  agent_card: %A2AEx.AgentCard{...},                 # For /.well-known/agent.json
  push_config_store: {PushConfigStore.InMemory, pid}, # Optional
  push_sender: A2AEx.PushSender.HTTP,                # Optional
  extended_card: %A2AEx.AgentCard{...}               # Optional
}
```

Method dispatch uses module attribute maps + `apply/3`:
```elixir
@sync_methods %{
  "message/send" => :handle_message_send,
  "tasks/get" => :handle_tasks_get,
  ...
}
@stream_methods %{
  "message/stream" => :handle_message_stream,
  "tasks/resubscribe" => :handle_tasks_resubscribe
}
```

### message/send Flow

1. `parse_send_params/1` — Parse raw map → `MessageSendParams`
2. `validate_message/1` — Check non-empty parts
3. `prepare_execution/2` — Create or resume task (check context_id match)
4. `EventQueue.get_or_create/1` — Start or get existing queue
5. `EventQueue.subscribe/1` — Calling process receives events
6. `spawn_executor/3` — Spawned process: try executor.execute, rescue → failed status, always close queue
7. `collect_events/2` — Receive loop: apply status/artifact events to task, stop on `final: true`
8. `load_task_result/2` — Reload from TaskStore, return as map

### message/stream Flow

Same as message/send through step 6, but returns `{:stream, task_id}` immediately. The Server process then receives events via its mailbox and sends them as SSE chunks.

### Server SSE

```elixir
defp stream_events(conn, task_id, request_id) do
  receive do
    {:a2a_event, ^task_id, event} ->
      event_map = A2AEx.Event.to_map(event)
      resp = A2AEx.JSONRPC.response_map(event_map, request_id)
      case send_sse_event(conn, resp) do
        {:ok, conn} -> stream_events(conn, task_id, request_id)
        {:error, _} -> conn
      end
    {:a2a_done, ^task_id} -> conn
  after
    60_000 -> # timeout
  end
end
```

### Executor Error Handling

Executors run in a spawned process with try/rescue/after:
- On success: executor returns `:ok`, events already enqueued
- On crash: rescue catches exception, enqueues a `TaskStatusUpdateEvent` with `:failed` state
- Always: `EventQueue.close(task_id)` in `after` block (sends `{:a2a_done, task_id}`)

---

## 8. Development Workflow

### Running Tests
```bash
cd /workspace/a2a_ex
mix test                    # Run all tests (158)
mix test --trace            # Verbose output
mix credo                   # Static analysis
mix dialyzer                # Type checking
```

### Conventions (same as ADK)
- Module names: `A2AEx.Component.SubComponent`
- Behaviours: Define in dedicated files
- Structs: `defstruct` + `@type t :: %__MODULE__{}`
- Errors: `{:ok, result}` / `{:error, reason}` tuples
- Tests: Mirror `lib/` structure under `test/`; use `async: true`
- Store references: `{module, GenServer.server()}` tuples for pluggable stores
- Verify: `mix test && mix credo && mix dialyzer`

### Gotchas (from ADK + A2AEx experience)
1. **Compile order**: Define nested/referenced modules BEFORE parent modules in the same file
2. **Avoid MapSet**: Use `%{key => true}` maps (dialyzer opaque type issues)
3. **Credo nesting**: Max depth 2 — extract helpers
4. **Test module names**: Use unique names to avoid cross-file collisions
5. **Behaviour dispatch**: No module functions on behaviour modules — call implementing module directly
6. **defstruct ordering**: Keyword defaults MUST come last — `[:a, :b, c: default]` not `[:a, c: default, :b]`
7. **JSON camelCase**: A2A protocol uses camelCase JSON keys (e.g., `contextId`, `taskId`, `messageId`). Elixir structs use snake_case atoms. Implement custom `Jason.Encoder` + `from_map/1` for conversion.
8. **Kind discriminator**: All A2A events/parts/tasks use a `"kind"` field in JSON for polymorphic decode. Always include it in `to_map/1` output.
9. **Go SDK restructured**: The A2A Go SDK moved from flat files to packages: `a2a/` (types), `a2asrv/` (server), `a2aclient/` (client). Check actual file locations before reading.
10. **Plug.Router conflict**: Do NOT use `Plug.Router` — its generated `call/2` conflicts with custom overrides. Use `@behaviour Plug` with manual routing via `{conn.method, conn.path_info}` pattern matching.
11. **`use Plug.Test` deprecated**: Use `import Plug.Test` + `import Plug.Conn` in tests.
12. **Multi-clause defaults**: For multi-clause functions with defaults, Elixir requires a header: `def foo(a, b \\ nil)` then clauses without defaults.
13. **Dialyzer strict types**: If type spec says `String.t()` but runtime value can be nil (e.g., from `from_map`), use catch-all guards: `defp f(id) when is_binary(id) and id != "", do: :ok; defp f(_), do: :error`.
14. **Registry cleanup is async**: After `GenServer.stop`, `Process.sleep(10)` before checking Registry in tests.
15. **Cyclomatic complexity**: Use module attribute maps + `apply/3` for dispatch instead of large case statements.

---

## 9. Quick Commands

```bash
cd /workspace/a2a_ex
mix deps.get       # Fetch dependencies (including ADK from GitHub)
mix test           # Run tests (158 passing)
mix credo          # Static analysis (0 issues)
mix dialyzer       # Type checking (0 errors)
iex -S mix         # Interactive shell
mix clean && mix compile  # Clean build
```

---

## 10. Key Contacts / Context

- **Project owner**: John Small (jds340@gmail.com)
- **A2AEx project**: `/workspace/a2a_ex/` (github.com/JohnSmall/a2a_ex)
- **ADK project**: `/workspace/adk/` (github.com/JohnSmall/adk)
