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

- [ ] **A2AEx.RequestHandler** — Business logic for all A2A methods
  - [ ] `handle_message_send/2` — Create/resume task, execute agent, collect result
  - [ ] `handle_message_stream/2` — Create/resume task, execute agent, return SSE stream
  - [ ] `handle_tasks_get/2` — Lookup task in TaskStore
  - [ ] `handle_tasks_cancel/2` — Cancel running task via AgentExecutor
  - [ ] `handle_tasks_resubscribe/2` — Re-subscribe to existing task's event stream
  - [ ] `handle_push_config_set/2` — Store push notification config
  - [ ] `handle_push_config_get/2` — Retrieve push config
  - [ ] `handle_push_config_delete/2` — Remove push config
  - [ ] `handle_push_config_list/2` — List push configs for task
  - [ ] `handle_get_extended_card/2` — Return extended agent card
  - [ ] Task lifecycle: create if new context_id, resume if existing

- [ ] **A2AEx.PushConfigStore** — Behaviour + InMemory implementation
  - [ ] Store/retrieve/delete push notification configs keyed by task_id

- [ ] **A2AEx.PushSender** — Webhook delivery
  - [ ] POST task events to configured webhook URLs
  - [ ] Authentication token in headers

- [ ] **A2AEx.Server** — Plug.Router HTTP endpoint
  - [ ] `POST /` — JSON-RPC dispatch (parse request, route to handler, return response)
  - [ ] `GET /.well-known/agent.json` — Serve agent card
  - [ ] SSE response support for streaming methods
  - [ ] Content-type validation (application/json)
  - [ ] Error handling (malformed requests, unknown methods)

- [ ] **Tests** — RequestHandler unit tests (mock executor), Server integration tests (Plug.Test)

### Reference Files
- `/workspace/a2a-go/a2asrv/jsonrpc.go` — JSONRPC handler + method dispatch
- `/workspace/a2a-go/a2asrv/handler.go` — RequestHandler interface + implementation
- `/workspace/a2a-go/a2asrv/push/` — PushConfigStore + PushSender

---

## Phase 4: ADK Integration (Bridge)

Connect A2AEx to ADK — expose ADK agents as A2A endpoints and consume A2A agents as ADK agents.

### Tasks

- [ ] **A2AEx.ADKExecutor** — AgentExecutor wrapping ADK.Runner
  - [ ] `execute/3` — Run ADK agent via Runner, convert events to A2A, enqueue
  - [ ] `cancel/2` — Signal cancellation (if supported)
  - [ ] Map ADK Event stream → TaskStatusUpdateEvent + TaskArtifactUpdateEvent
  - [ ] Handle ADK state_delta → A2A task metadata

- [ ] **A2AEx.Converter** — ADK ↔ A2A type conversion
  - [ ] `adk_part_to_a2a/1` — ADK.Types.Part → A2AEx.Part
  - [ ] `a2a_part_to_adk/1` — A2AEx.Part → ADK.Types.Part
  - [ ] `adk_event_to_status/1` — ADK.Event → TaskStatusUpdateEvent
  - [ ] `adk_event_to_artifact/1` — ADK.Event → TaskArtifactUpdateEvent (if has artifacts)
  - [ ] `a2a_message_to_content/1` — A2AEx.Message → ADK.Types.Content
  - [ ] `adk_content_to_message/1` — ADK.Types.Content → A2AEx.Message
  - [ ] Map ADK event actions (escalate, transfer) to A2A task states

- [ ] **A2AEx.RemoteAgent** — ADK agent backed by A2A client
  - [ ] `@behaviour ADK.Agent`
  - [ ] `run/2` — Send message via A2AEx.Client, convert response to ADK Events
  - [ ] Support streaming (SSE → ADK Event stream)

- [ ] **Tests** — Converter round-trip, ADKExecutor with mock agent, RemoteAgent with mock server

### Reference Files
- `/workspace/adk-go/server/adka2a/executor.go` — ADK Executor wrapper
- `/workspace/adk-go/server/adka2a/part_converter.go` — Part conversion
- `/workspace/adk-go/server/adka2a/event_converter.go` — Event conversion

---

## Phase 5: Client

HTTP client for consuming remote A2A agents.

### Tasks

- [ ] **A2AEx.Client** — HTTP client for A2A servers
  - [ ] `send_message/3` — POST JSON-RPC `message/send`, return Task
  - [ ] `stream_message/3` — POST JSON-RPC `message/stream`, return SSE event stream
  - [ ] `get_task/2` — `tasks/get`
  - [ ] `cancel_task/2` — `tasks/cancel`
  - [ ] `resubscribe/2` — `tasks/resubscribe`, return SSE stream
  - [ ] Push config CRUD methods
  - [ ] `get_agent_card/1` — GET `/.well-known/agent.json`
  - [ ] SSE parsing (Server-Sent Events line protocol)
  - [ ] Configurable base URL, timeout, headers

- [ ] **Tests** — Client with mock HTTP (Req test adapter or Plug.Test)

### Reference Files
- `/workspace/a2a-go/a2aclient/client.go` — Client implementation
- `/workspace/a2a-go/a2aclient/transport.go` — HTTP transport
- `/workspace/a2a-go/a2aclient/jsonrpc.go` — Client-side JSON-RPC helpers

---

## Phase 6: Integration Testing + Polish

End-to-end tests and documentation.

### Tasks

- [ ] **Integration tests** — Full server↔client round-trip
  - [ ] Start server with ADK agent, call via client
  - [ ] Streaming: SSE events arrive correctly
  - [ ] Task lifecycle: submit → working → completed
  - [ ] Task cancellation
  - [ ] Agent card serving
  - [ ] Push notifications (mock webhook receiver)

- [ ] **Interop tests** — Test against A2A Go SDK samples
  - [ ] A2AEx client → Go sample server
  - [ ] Go sample client → A2AEx server

- [ ] **Documentation** — Hex docs, examples
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
Phase 4: ADK Integration          (bridge ADK ↔ A2A)
    ↓
Phase 5: Client                   (consume remote agents)
    ↓
Phase 6: Integration + Polish     (end-to-end)
```

Phases 4 and 5 are independent of each other (both depend on Phase 3). They can be done in parallel.
