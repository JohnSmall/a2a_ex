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

**Phase 1 COMPLETE — 83 tests, credo clean, dialyzer clean. Ready for Phase 2.**

### What's Built (Phase 1: Core Types + JSON-RPC)

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

### A2A Go SDK Architecture (Reference)

```
HTTP Transport (net/http)
    → JSON-RPC Handler (parse method, dispatch)
        → RequestHandler (task lifecycle, business logic)
            → AgentExecutor (Execute/Cancel)
            → TaskStore (CRUD tasks)
            → EventQueue (SSE delivery)
            → PushConfigStore + PushSender (webhooks)
```

### Elixir Mapping

| Go SDK Component | Elixir Module | OTP Pattern |
|-----------------|---------------|-------------|
| `AgentExecutor` interface | `A2AEx.AgentExecutor` behaviour | `@callback` |
| `TaskStore` interface | `A2AEx.TaskStore` behaviour | `@callback` |
| `InMemoryTaskStore` | `A2AEx.TaskStore.InMemory` | GenServer + ETS |
| `EventQueue` + Manager | `A2AEx.EventQueue` | GenServer + Registry |
| `RequestHandler` | `A2AEx.RequestHandler` | Module functions |
| `A2AServer` | `A2AEx.Server` | Plug.Router |
| `JSONRPCHandler` | `A2AEx.JSONRPC` | Module functions |
| `Client` | `A2AEx.Client` | Req HTTP client |
| ADK Executor | `A2AEx.ADKExecutor` | Wraps ADK.Runner |
| Part/Event converters | `A2AEx.Converter` | Pure functions |
| `AgentCard` | `A2AEx.AgentCard` | Struct |
| `RemoteAgent` | `A2AEx.RemoteAgent` | `@behaviour ADK.Agent` |

### ADK-A2A Bridge

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

### Phase 2: Storage + Execution
- `/workspace/a2a-go/a2asrv/tasks.go` — TaskStore interface
- `/workspace/a2a-go/a2asrv/eventqueue/` — EventQueue, Manager, InMemory implementations
- `/workspace/a2a-go/a2asrv/agentexec.go` — AgentExecutor interface

### Phase 3: Server
- `/workspace/a2a-go/a2asrv/jsonrpc.go` — JSONRPC handler + method dispatch
- `/workspace/a2a-go/a2asrv/handler.go` — RequestHandler interface + implementation
- `/workspace/a2a-go/a2asrv/push/` — PushConfigStore + PushSender

### Phase 4: ADK Bridge
- `/workspace/adk-go/server/adka2a/executor.go` — ADK Runner → AgentExecutor wrapper
- `/workspace/adk-go/server/adka2a/part_converter.go` — Part type conversion
- `/workspace/adk-go/server/adka2a/event_converter.go` — Event → A2A event conversion

### Phase 5: Client
- `/workspace/a2a-go/a2aclient/client.go` — Client implementation
- `/workspace/a2a-go/a2aclient/transport.go` — HTTP transport
- `/workspace/a2a-go/a2aclient/jsonrpc.go` — Client-side JSON-RPC helpers

---

## 7. Development Workflow

### Running Tests
```bash
cd /workspace/a2a_ex
mix test                    # Run all tests
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

---

## 8. Quick Commands

```bash
cd /workspace/a2a_ex
mix deps.get       # Fetch dependencies (including ADK from GitHub)
mix test           # Run tests
mix credo          # Static analysis
mix dialyzer       # Type checking
iex -S mix         # Interactive shell
mix clean && mix compile  # Clean build
```

---

## 9. Key Contacts / Context

- **Project owner**: John Small (jds340@gmail.com)
- **A2AEx project**: `/workspace/a2a_ex/` (github.com/JohnSmall/a2a_ex)
- **ADK project**: `/workspace/adk/` (github.com/JohnSmall/adk)
