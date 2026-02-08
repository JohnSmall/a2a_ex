# A2AEx Implementation Plan

## Overview

Implementation phases for the A2A protocol Elixir package. Each phase builds on the previous. The A2A Go SDK (`/workspace/a2a-go/`) is the primary reference.

---

## Phase 1: Core Types + JSON-RPC

Foundation types and JSON-RPC encode/decode layer.

### Tasks

- [x] **A2AEx.Types** — Core A2A protocol types
  - [x] `A2AEx.Part` — Tagged union: Text, File, Data (with FileContent sub-struct)
  - [x] `A2AEx.Message` — role (:user/:agent) + parts + metadata
  - [x] `A2AEx.TaskStatus` — state enum + message + timestamp
  - [x] `A2AEx.Task` — id, context_id, status, artifacts, metadata
  - [x] `A2AEx.Artifact` — artifact_id, name, description, parts, metadata
  - [x] `A2AEx.AgentCard` — name, description, url, version, capabilities, skills
  - [x] `A2AEx.Capabilities` — streaming, push_notifications, state_transition_history
  - [x] `A2AEx.Skill` — id, name, description, tags, examples
  - [x] `A2AEx.TaskStatusUpdateEvent` — id, status, final flag
  - [x] `A2AEx.TaskArtifactUpdateEvent` — id, artifact
  - [x] `A2AEx.PushNotificationConfig` — url, token, authentication
  - [x] JSON encoding for all types (custom Jason.Encoder implementations)

- [x] **A2AEx.JSONRPC** — JSON-RPC 2.0 layer
  - [x] `Request` map — jsonrpc, method, params, id
  - [x] `Response` map — jsonrpc, result, id
  - [x] `Error` struct — type, message, details + error_map for JSON-RPC format
  - [x] `decode_request/1` — parse JSON string → request map
  - [x] `encode_response/2` — result + id → JSON string
  - [x] Standard error codes: -32700 (parse), -32600 (invalid), -32601 (not found), -32602 (params), -32603 (internal)
  - [x] A2A-specific error codes: -32001 through -32007 + -31401 (unauth) + -31403 (unauthorized)

- [x] **Tests** — 83 tests: types serialization round-trip, JSON-RPC encode/decode, error codes

### Reference Files (Read During Phase 1)
- `/workspace/a2a-go/a2a/core.go` — Core types (Task, Message, Part, Artifact, events, params)
- `/workspace/a2a-go/a2a/agent.go` — AgentCard, AgentCapabilities, AgentSkill, AgentProvider
- `/workspace/a2a-go/a2a/push.go` — Push notification types (PushConfig, PushAuthInfo, param types)
- `/workspace/a2a-go/a2a/auth.go` — Security scheme types (OpenAPI 3.0 style)
- `/workspace/a2a-go/a2a/errors.go` — Error sentinel values
- `/workspace/a2a-go/internal/jsonrpc/jsonrpc.go` — Error codes, method names, error conversion
- `/workspace/a2a-go/a2asrv/jsonrpc.go` — JSON-RPC request/response structs, handler dispatch

---

## Phase 2: TaskStore + EventQueue + AgentExecutor

Storage and execution behaviours with in-memory implementations.

### Tasks

- [x] **A2AEx.TaskStore** — Behaviour for task persistence
  - [x] `@callback get(store, task_id) :: {:ok, Task.t()} | {:error, :not_found}`
  - [x] `@callback save(store, Task.t()) :: :ok | {:error, term()}`
  - [x] `@callback delete(store, task_id) :: :ok`

- [x] **A2AEx.TaskStore.InMemory** — GenServer + ETS implementation
  - [x] GenServer for serialized writes
  - [x] ETS table for concurrent reads
  - [x] Keyed by task_id

- [x] **A2AEx.EventQueue** — Per-task event delivery
  - [x] GenServer per task (started on demand via DynamicSupervisor)
  - [x] `enqueue(task_id, event)` — send event to all subscribers
  - [x] `subscribe(task_id)` — subscribers receive `{:a2a_event, task_id, event}` messages
  - [x] `close(task_id)` — signal completion via `{:a2a_done, task_id}`, clean up
  - [x] Registry-based lookup (Elixir Registry)
  - [x] `get_or_create(task_id)` — start or return existing queue

- [x] **A2AEx.AgentExecutor** — Behaviour for agent execution
  - [x] `@callback execute(context, task_id) :: :ok | {:error, term()}`
  - [x] `@callback cancel(context, task_id) :: :ok | {:error, term()}`
  - [x] `A2AEx.RequestContext` struct (task_id, context_id, message, task, metadata)

- [x] **Tests** — TaskStore CRUD, EventQueue pub/sub, AgentExecutor mock (31 new tests)

### Reference Files
- `/workspace/a2a-go/a2asrv/tasks.go` — TaskStore interface
- `/workspace/a2a-go/a2asrv/eventqueue/` — EventQueue, Manager, InMemory implementations
- `/workspace/a2a-go/a2asrv/agentexec.go` — AgentExecutor interface

---

## Phase 3: RequestHandler + Server

JSON-RPC method handlers and Plug-based HTTP server.

### Tasks

- [x] **A2AEx.RequestHandler** — Business logic for all A2A methods
  - [x] `handle_message_send/2` — Create/resume task, execute agent, collect result
  - [x] `handle_message_stream/2` — Create/resume task, execute agent, return SSE stream
  - [x] `handle_tasks_get/2` — Lookup task in TaskStore
  - [x] `handle_tasks_cancel/2` — Cancel running task via AgentExecutor
  - [x] `handle_tasks_resubscribe/2` — Re-subscribe to existing task's event stream
  - [x] `handle_push_config_set/2` — Store push notification config
  - [x] `handle_push_config_get/2` — Retrieve push config
  - [x] `handle_push_config_delete/2` — Remove push config
  - [x] `handle_push_config_list/2` — List push configs for task
  - [x] `handle_get_extended_card/2` — Return extended agent card
  - [x] Task lifecycle: create if new context_id, resume if existing

- [x] **A2AEx.PushConfigStore** — Behaviour + InMemory implementation
  - [x] Store/retrieve/delete push notification configs keyed by task_id

- [x] **A2AEx.PushSender** — Webhook delivery
  - [x] POST task events to configured webhook URLs
  - [x] Authentication token in headers

- [x] **A2AEx.Server** — Plug-based HTTP endpoint (@behaviour Plug)
  - [x] `POST /` — JSON-RPC dispatch (parse request, route to handler, return response)
  - [x] `GET /.well-known/agent.json` — Serve agent card
  - [x] SSE response support for streaming methods
  - [x] Content-type validation (application/json)
  - [x] Error handling (malformed requests, unknown methods)

- [x] **Tests** — RequestHandler unit tests (mock executor), Server integration tests (Plug.Test), PushConfigStore tests (158 total)

### Reference Files
- `/workspace/a2a-go/a2asrv/jsonrpc.go` — JSONRPC handler + method dispatch
- `/workspace/a2a-go/a2asrv/handler.go` — RequestHandler interface + implementation
- `/workspace/a2a-go/a2asrv/push/` — PushConfigStore + PushSender

---

## Phase 4: ADK Integration (Bridge)

Connect A2AEx to ADK — expose ADK agents as A2A endpoints.

### Tasks

- [x] **A2AEx.Converter** — ADK ↔ A2A type conversion (pure functions)
  - [x] `adk_part_to_a2a/1` — ADK.Types.Part → A2AEx.Part (text, thought, inline_data, function_call, function_response)
  - [x] `a2a_part_to_adk/1` — A2AEx.Part → ADK.Types.Part (TextPart, FilePart w/ bytes/uri, DataPart w/ metadata dispatch)
  - [x] `adk_parts_to_a2a/1` + `a2a_parts_to_adk/1` — batch list conversion
  - [x] `a2a_message_to_content/1` — A2AEx.Message → ADK.Types.Content (role mapping: :user→"user", :agent→"model")
  - [x] `adk_content_to_message/1,2` — ADK.Types.Content → A2AEx.Message (role mapping + optional context_id/task_id)
  - [x] `terminal_state/1` — ADK.Event → A2AEx.TaskState (error→:failed, escalate/long_running→:input_required, else→:completed)

- [x] **A2AEx.RequestHandler update** — Support `{module, config}` executor tuples
  - [x] Broadened `executor` type to `executor_ref()` = `module() | {module(), term()}`
  - [x] `call_execute/3` + `call_cancel/3` dispatch helpers with guards
  - [x] Backward-compatible: existing bare-module executors still work

- [x] **A2AEx.ADKExecutor** — Bridges ADK.Runner into A2A protocol
  - [x] `A2AEx.ADKExecutor.Config` struct (runner, app_name)
  - [x] `execute/3` — Convert A2A message → ADK Content, run agent via Runner, stream events
  - [x] Emit working status → artifact events (with append tracking) → last_chunk → final status
  - [x] `cancel/3` — Enqueue :canceled status with final: true
  - [x] Terminal state detection: error→:failed, escalate/long_running→:input_required

- [ ] **A2AEx.RemoteAgent** — ADK agent backed by A2A client *(deferred to Phase 5 — requires Client)*
  - [ ] `@behaviour ADK.Agent`
  - [ ] `run/2` — Send message via A2AEx.Client, convert response to ADK Events

- [x] **Tests** — 33 new tests (23 converter + 10 executor), 191 total
  - [x] Converter: part conversion round-trip (all 5 part types both directions), message/content conversion, terminal state
  - [x] ADKExecutor: text response flow, multi-event append, error/escalation states, cancel, last_chunk, integration via RequestHandler

### Reference Files
- `/workspace/adk-go/server/adka2a/executor.go` — ADK Executor wrapper
- `/workspace/adk-go/server/adka2a/part_converter.go` — Part conversion
- `/workspace/adk-go/server/adka2a/event_converter.go` — Event conversion

---

## Phase 5: Client + RemoteAgent

HTTP client for consuming remote A2A agents, and RemoteAgent (ADK agent backed by A2A client).

### Tasks

- [x] **A2AEx.Client.SSE** — SSE line parser
  - [x] `parse_chunk/2` — Parse SSE data with cross-chunk buffering
  - [x] Handles `data: {json}\n\n` format, skips non-data lines

- [x] **A2AEx.Client** — HTTP client for A2A servers
  - [x] `new/1,2` — Create client with base URL and optional Req options
  - [x] `send_message/2` — POST JSON-RPC `message/send`, return Task result map
  - [x] `stream_message/2` — POST JSON-RPC `message/stream`, return `{:ok, stream}` of A2A events
  - [x] `get_task/2` — `tasks/get`
  - [x] `cancel_task/2` — `tasks/cancel`
  - [x] `resubscribe/2` — `tasks/resubscribe`, return SSE stream
  - [x] Push config CRUD: `set_push_config/2`, `get_push_config/2`, `delete_push_config/2`, `list_push_configs/2`
  - [x] `get_agent_card/1` — GET `/.well-known/agent.json`, returns `AgentCard` struct
  - [x] `get_extended_card/1` — `agent/getAuthenticatedExtendedCard`
  - [x] SSE streaming via `spawn_link` + `Stream.resource` + `Req into:` callback

- [x] **A2AEx.RemoteAgent** — ADK agent backed by A2A client
  - [x] `A2AEx.RemoteAgent.Config` struct (name, url, description, client_opts, agent_card)
  - [x] `new/1` — Returns `ADK.Agent.CustomAgent` with run function wrapping A2A client
  - [x] Sync path (`streaming_mode: :none`): `Client.send_message` → convert task result to ADK events
  - [x] Streaming path (`streaming_mode: :sse`): `Client.stream_message` → `Stream.flat_map` to ADK events
  - [x] Converts `TaskStatusUpdateEvent` → `ADK.Event` (with error/input_required metadata)
  - [x] Converts `TaskArtifactUpdateEvent` → `ADK.Event` (partial: true)
  - [x] Error handling: no user content → error event, failed status → error_code on event

- [x] **Tests** — 26 new tests (5 SSE + 11 client + 10 remote_agent), 217 total
  - [x] SSE: single event, multiple events, incomplete buffering, cross-chunk, non-data lines
  - [x] Client: constructor, agent card, send/get/cancel, streaming with status+artifacts, req_options
  - [x] RemoteAgent: constructor, sync echo, streaming echo, artifacts, failed, no content, author, client_opts
  - [x] All tests use real HTTP servers (Bandit) — no mocks

### Reference Files (Read During Phase 5)
- `/workspace/a2a-go/a2aclient/client.go` — Client implementation
- `/workspace/a2a-go/a2aclient/transport.go` — HTTP transport
- `/workspace/a2a-go/a2aclient/jsonrpc.go` — Client-side JSON-RPC helpers
- `/workspace/adk-go/agent/remoteagent/a2a_agent.go` — RemoteAgent implementation
- `/workspace/adk-go/agent/remoteagent/a2a_agent_run_processor.go` — Event processing
- `/workspace/adk-go/agent/remoteagent/utils.go` — Session history utilities

---

## Phase 6: Integration Testing + Polish

End-to-end tests and documentation.

### Tasks

- [x] **Integration tests** — Full server↔client round-trip (14 new tests, 231 total)
  - [x] Sync: ADK agent → ADKExecutor → Server → Client → completed task with artifacts
  - [x] Streaming: SSE events arrive correctly (working → artifacts → completed)
  - [x] Multi-event agent: append tracking, shared artifact_id
  - [x] Error: agent raises → failed task state
  - [x] Escalation: agent escalates → input-required state
  - [x] Agent card served via client
  - [x] Task lifecycle: get task after completion, multi-turn conversation resumes context
  - [x] Task cancellation: cancel streaming task → canceled state
  - [x] Push CRUD: set/get/list/delete push configs over HTTP
  - [x] Push sender: delivers to real webhook (Bandit receiver + Agent collector)
  - [x] RemoteAgent: sync and streaming modes return ADK events
  - [x] Multi-agent orchestration: SequentialAgent with local + remote sub-agents

- [ ] **Interop tests** — Test against A2A Go SDK samples (deferred — requires Go binary builds)
  - [ ] A2AEx client → Go sample server
  - [ ] Go sample client → A2AEx server

- [ ] **Documentation** — Hex docs, examples (deferred)
  - [ ] Module docs for all public modules
  - [ ] Usage examples in README
  - [ ] Getting started guide

---

## Dependency Graph

```
Phase 1: Types + JSONRPC          (foundation)
    ↓
Phase 2: TaskStore + EventQueue   (storage + delivery)
    ↓
Phase 3: RequestHandler + Server  (HTTP endpoint)
    ↓
Phase 4: ADK Integration          (bridge ADK → A2A: Converter + ADKExecutor)
    ↓
Phase 5: Client + RemoteAgent    (consume remote agents, bridge A2A → ADK)
    ↓
Phase 6: Integration + Polish     (end-to-end)
```

Phase 4 (server-side bridge) and Phase 5 (client-side) both depend on Phase 3. Phase 5 RemoteAgent also depends on Phase 4's Converter for A2A→ADK conversion.
