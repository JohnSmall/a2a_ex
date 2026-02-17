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

**This package depends on the ADK package** (`adk_ex` at `/workspace/elixir_code/adk_ex/`), which provides the agent framework (agents, runner, sessions, tools, LLM abstraction).

**Example applications** demonstrating A2A agent cooperation are in `/workspace/elixir_code/a2a_ex_examples/`.

---

## 2. Current Status

**All 6 phases COMPLETE — 231 tests, credo clean, dialyzer clean.**

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

### What's Built (Phase 4: ADK Integration Bridge — 33 tests)

| Module | File | Purpose |
|--------|------|---------|
| `A2AEx.Converter` | `lib/a2a_ex/converter.ex` | Pure bidirectional ADK ↔ A2A type conversion (parts, content/messages, terminal state) |
| `A2AEx.ADKExecutor.Config` | `lib/a2a_ex/adk_executor.ex` | Config struct (runner, app_name) for ADK executor |
| `A2AEx.ADKExecutor` | `lib/a2a_ex/adk_executor.ex` | Bridges ADK.Runner into A2A protocol via `{module, config}` tuple pattern |

**Key changes to existing modules:**
- `A2AEx.RequestHandler` — Broadened `executor` type to support `{module, config}` tuples alongside bare modules. Added `call_execute/3` + `call_cancel/3` dispatch helpers.

### What's Built (Phase 5: Client + RemoteAgent — 26 tests)

| Module | File | Purpose |
|--------|------|---------|
| `A2AEx.Client.SSE` | `lib/a2a_ex/client/sse.ex` | SSE line parser with cross-chunk buffering |
| `A2AEx.Client` | `lib/a2a_ex/client.ex` | HTTP client — all 10 JSON-RPC methods, sync + SSE streaming |
| `A2AEx.RemoteAgent.Config` | `lib/a2a_ex/remote_agent.ex` | Config struct (name, url, description, client_opts) |
| `A2AEx.RemoteAgent` | `lib/a2a_ex/remote_agent.ex` | ADK agent backed by remote A2A server (wraps CustomAgent) |

### What's Built (Phase 6: Integration Testing — 14 tests)

| Test Group | Tests | Coverage |
|------------|-------|----------|
| Server-Client with ADK Agent | 6 | Sync, streaming, multi-event append, error→failed, escalation→input-required, agent card |
| Task Lifecycle | 2 | Get task after completion, multi-turn context resume |
| Task Cancellation | 1 | Cancel streaming task → canceled state |
| Push Notifications | 2 | Push config CRUD over HTTP, PushSender.HTTP to real webhook |
| Remote Agent | 2 | Sync and streaming modes |
| Multi-Agent Orchestration | 1 | SequentialAgent with local + RemoteAgent sub-agents |

All tests run over real HTTP (Bandit) exercising the full pipeline: ADK agent → ADKExecutor → Server → Client.

### What's Built in ADK (Dependency)

The ADK package at `/workspace/elixir_code/adk_ex/` has Phases 1-5 complete (240 tests):
- All agent types (LLM, Loop, Sequential, Parallel, Custom)
- Runner, Flow engine, Tool system
- Session management (in-memory + Ecto via adk_ex_ecto)
- Model providers (Gemini, Claude, Mock)
- Agent transfer, Plugins, Toolsets
- Memory service, Artifact service, Telemetry

### Examples Project

The examples project at `/workspace/elixir_code/a2a_ex_examples/` demonstrates A2A agent cooperation:
- **Example 1** (`mix example.research_report`): Pipeline — Researcher → Writer
- **Example 2** (`mix example.code_review`): Review loop — Developer ↔ Reviewer (max 3 rounds)
- **Example 3** (`mix example.data_viz`): Data pipeline — Analyst → Visualizer (with embedded CSV)

Each example runs two Claude-powered LlmAgent agents as separate A2A HTTP servers.
Requires `ANTHROPIC_API_KEY` env var. Future work: mix Codex, Gemini, and Claude agents.

---

## 3. Key Resources

### Local Files

| Resource | Location |
|----------|----------|
| **This project (A2AEx)** | `/workspace/elixir_code/a2a_ex/` |
| **ADK (dependency)** | `/workspace/elixir_code/adk_ex/` |
| **A2A Examples** | `/workspace/elixir_code/a2a_ex_examples/` |
| **A2A Go SDK (PRIMARY reference)** | `/workspace/samples/a2a-go/` |
| **ADK Go source** | `/workspace/samples/adk-go/` |
| **ADK-A2A bridge (Go)** | `/workspace/samples/adk-go/server/adka2a/` |
| **A2A samples** | `/workspace/samples/a2a-samples/` |
| **PRD** | `/workspace/elixir_code/a2a_ex/docs/prd.md` |
| **Implementation plan** | `/workspace/elixir_code/a2a_ex/docs/implementation-plan.md` |
| **This guide** | `/workspace/elixir_code/a2a_ex/docs/onboarding.md` |

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
| `Client` | `A2AEx.Client` | Req HTTP client + SSE streaming |
| ADK Executor | `A2AEx.ADKExecutor` | Wraps ADK.Runner |
| Part/Event converters | `A2AEx.Converter` | Pure functions |
| `AgentCard` | `A2AEx.AgentCard` | Struct |
| `RemoteAgent` | `A2AEx.RemoteAgent` | Wraps `ADK.Agent.CustomAgent` |
| SSE parser | `A2AEx.Client.SSE` | Line parser with buffering |

### ADK-A2A Bridge (Phases 4 + 5)

The bridge connects ADK's event-sourced model to A2A's task-based model in both directions:

```
Server Side (Phase 4 — ADKExecutor):
  ADK.Runner.run/5                   message/send or message/stream
    → Stream of ADK.Event      →    TaskStatusUpdateEvent (state changes)
    → Events with artifacts     →    TaskArtifactUpdateEvent (outputs)
    → Events with text content  →    Task.status.message (final response)
    → escalate/transfer actions →    Task state = completed/failed

Client Side (Phase 5 — RemoteAgent):
  A2AEx.Client.stream_message        ADK.Agent.CustomAgent.run
    → TaskStatusUpdateEvent     →    ADK.Event with content
    → TaskArtifactUpdateEvent   →    ADK.Event with content (partial: true)
    → failed status             →    ADK.Event with error_code/error_message
    → input_required status     →    ADK.Event with long_running_tool_ids
```

Key conversion rules (implemented in `A2AEx.Converter`):
- ADK text Part → A2A TextPart (with thought metadata if `part.thought` is true)
- ADK inline_data (Blob) → A2A FilePart with FileBytes (base64 encoded)
- ADK function_call → A2A DataPart with `metadata: %{"adk_type" => "function_call"}`
- ADK function_response → A2A DataPart with `metadata: %{"adk_type" => "function_response"}`
- A2A FileURI → ADK text Part fallback (ADK has no FileURI type)
- A2A DataPart (generic) → ADK text Part with JSON-encoded data
- ADK role "user" ↔ A2A role :user; ADK role "model" ↔ A2A role :agent
- ADK event with error_code/error_message → terminal state :failed
- ADK event with escalate or long_running_tool_ids → terminal state :input_required
- ADK normal event → terminal state :completed

---

## 6. Reference: A2A Go SDK Key Files

Read these files in order when implementing each phase:

### Phase 1: Types + JSON-RPC (DONE)
- `/workspace/samples/a2a-go/a2a/core.go` — Core types (Task, Message, Part, Artifact, events, params)
- `/workspace/samples/a2a-go/a2a/agent.go` — AgentCard, AgentCapabilities, AgentSkill, AgentProvider
- `/workspace/samples/a2a-go/a2a/push.go` — Push notification types
- `/workspace/samples/a2a-go/a2a/auth.go` — Security scheme types
- `/workspace/samples/a2a-go/a2a/errors.go` — Error sentinel values
- `/workspace/samples/a2a-go/internal/jsonrpc/jsonrpc.go` — Error codes, method names
- `/workspace/samples/a2a-go/a2asrv/jsonrpc.go` — JSON-RPC handler, request/response structs

### Phase 2: Storage + Execution (DONE)
- `/workspace/samples/a2a-go/a2asrv/tasks.go` — TaskStore interface
- `/workspace/samples/a2a-go/a2asrv/eventqueue/` — EventQueue, Manager, InMemory implementations
- `/workspace/samples/a2a-go/a2asrv/agentexec.go` — AgentExecutor interface

### Phase 3: Server (DONE)
- `/workspace/samples/a2a-go/a2asrv/jsonrpc.go` — JSONRPC handler + method dispatch
- `/workspace/samples/a2a-go/a2asrv/handler.go` — RequestHandler interface + implementation
- `/workspace/samples/a2a-go/a2asrv/push/` — PushConfigStore + PushSender
- `/workspace/samples/a2a-go/internal/sse/sse.go` — SSE writer (WriteHeaders, WriteData, WriteKeepAlive)

### Phase 4: ADK Bridge (DONE)
- `/workspace/samples/adk-go/server/adka2a/executor.go` — ADK Runner → AgentExecutor wrapper
- `/workspace/samples/adk-go/server/adka2a/part_converter.go` — Part type conversion
- `/workspace/samples/adk-go/server/adka2a/event_converter.go` — Event → A2A event conversion

### Phase 5: Client + RemoteAgent (DONE)
- `/workspace/samples/a2a-go/a2aclient/client.go` — Client implementation
- `/workspace/samples/a2a-go/a2aclient/transport.go` — HTTP transport
- `/workspace/samples/a2a-go/a2aclient/jsonrpc.go` — Client-side JSON-RPC helpers
- `/workspace/samples/adk-go/agent/remoteagent/a2a_agent.go` — RemoteAgent implementation
- `/workspace/samples/adk-go/agent/remoteagent/a2a_agent_run_processor.go` — Event processing
- `/workspace/samples/adk-go/agent/remoteagent/utils.go` — Session history utilities

---

## 7. How Phase 3 Works (RequestHandler + Server)

### RequestHandler Design

The `A2AEx.RequestHandler` is a struct (not a GenServer) containing pluggable configuration:

```elixir
# With a bare executor module:
%A2AEx.RequestHandler{
  executor: MyExecutor,                              # AgentExecutor module
  task_store: {A2AEx.TaskStore.InMemory, store_pid}, # {module, server} tuple
  agent_card: %A2AEx.AgentCard{...},                 # For /.well-known/agent.json
  push_config_store: {PushConfigStore.InMemory, pid}, # Optional
  push_sender: A2AEx.PushSender.HTTP,                # Optional
  extended_card: %A2AEx.AgentCard{...}               # Optional
}

# With ADKExecutor (wraps ADK.Runner via {module, config} tuple):
config = %A2AEx.ADKExecutor.Config{runner: runner, app_name: "my-app"}
%A2AEx.RequestHandler{
  executor: {A2AEx.ADKExecutor, config},
  task_store: {A2AEx.TaskStore.InMemory, store_pid}
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
cd /workspace/elixir_code/a2a_ex
mix test                    # Run all tests (231)
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
16. **`{module, config}` executor pattern**: ADKExecutor uses 3-arity functions (`execute(config, req_ctx, task_id)`) but AgentExecutor behaviour is 2-arity. The RequestHandler dispatches via `call_execute/call_cancel` helpers with guards (`when is_atom(mod)` for bare modules, `{mod, config}` for tuples).
17. **Converter is pure**: `A2AEx.Converter` has no state — all functions are pure. Use module attribute constants for repeated metadata keys (`@adk_type`, `@adk_thought`).
18. **Base64 for inline_data**: ADK `Blob.data` is raw binary; A2A `FileBytes.bytes` is base64-encoded. The converter handles encoding/decoding automatically.
19. **Bandit test cleanup**: Bandit has no public `stop/1` function. Use `Process.exit(server_pid, :normal)` + `Process.sleep(10)` in `on_exit` callbacks. Do NOT use `Supervisor.stop/1` or `ThousandIsland.stop/1` — both propagate `:shutdown` exit that ExUnit catches as a failure.
20. **`Client.stream_message/2` always returns `{:ok, stream}`**: The streaming function always succeeds at the call site — HTTP and parsing errors surface inside the stream itself. Don't add an unreachable `{:error, _}` clause.
21. **RemoteAgent wraps CustomAgent**: `A2AEx.RemoteAgent.new/1` returns an `ADK.Agent.CustomAgent` struct, not a custom behaviour implementation. This reuses CustomAgent's before/after callback machinery.
22. **Streaming mode dispatch**: RemoteAgent checks `ctx.run_config.streaming_mode` to choose between `Client.send_message` (sync) and `Client.stream_message` (SSE). Default is `:none` (sync).
23. **Dep name must match app name**: The ADK dependency MUST be declared as `{:adk_ex, path: "../adk_ex"}` (not `{:adk, ...}`). Mix fails to resolve code paths when the dep name (`:adk`) differs from the app name (`:adk_ex`). This was changed from the original `{:adk, github: "JohnSmall/adk"}`.
24. **OpenTelemetry dep**: adk_ex's `{:opentelemetry, "~> 1.5"}` must NOT have `only: [:dev, :test]` — it's needed at compile time in all environments.

---

## 9. Quick Commands

```bash
cd /workspace/elixir_code/a2a_ex
mix deps.get       # Fetch dependencies (ADK from local path ../adk_ex)
mix test           # Run tests (231 passing)
mix credo          # Static analysis (0 issues)
mix dialyzer       # Type checking (0 errors)
iex -S mix         # Interactive shell
mix clean && mix compile  # Clean build
```

---

## 10. Key Contacts / Context

- **Project owner**: John Small (jds340@gmail.com)
- **A2AEx project**: `/workspace/elixir_code/a2a_ex/` (github.com/JohnSmall/a2a_ex)
- **ADK project**: `/workspace/elixir_code/adk_ex/` (github.com/JohnSmall/adk_ex)
- **A2A Examples**: `/workspace/elixir_code/a2a_ex_examples/` — Example apps using A2A protocol
