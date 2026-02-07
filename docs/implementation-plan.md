# A2AEx Implementation Plan

## Overview

Implementation phases for the A2A protocol Elixir package. Each phase builds on the previous. The A2A Go SDK (`/workspace/a2a-go/`) is the primary reference.

---

## Phase 1: Core Types + JSON-RPC

Foundation types and JSON-RPC encode/decode layer.

### Tasks

- [ ] **A2AEx.Types** — Core A2A protocol types
  - [ ] `A2AEx.Part` — Tagged union: Text, File, Data (with FileContent sub-struct)
  - [ ] `A2AEx.Message` — role (:user/:agent) + parts + metadata
  - [ ] `A2AEx.TaskStatus` — state enum + message + timestamp
  - [ ] `A2AEx.Task` — id, context_id, status, artifacts, metadata
  - [ ] `A2AEx.Artifact` — artifact_id, name, description, parts, metadata
  - [ ] `A2AEx.AgentCard` — name, description, url, version, capabilities, skills
  - [ ] `A2AEx.Capabilities` — streaming, push_notifications, state_transition_history
  - [ ] `A2AEx.Skill` — id, name, description, tags, examples
  - [ ] `A2AEx.TaskStatusUpdateEvent` — id, status, final flag
  - [ ] `A2AEx.TaskArtifactUpdateEvent` — id, artifact
  - [ ] `A2AEx.PushNotificationConfig` — url, token, authentication
  - [ ] JSON encoding for all types (derive Jason.Encoder or custom)

- [ ] **A2AEx.JSONRPC** — JSON-RPC 2.0 layer
  - [ ] `Request` struct — jsonrpc, method, params, id
  - [ ] `Response` struct — jsonrpc, result, id
  - [ ] `Error` struct — jsonrpc, error (code + message + data), id
  - [ ] `decode_request/1` — parse JSON string → Request struct
  - [ ] `encode_response/1` — Response/Error struct → JSON string
  - [ ] Standard error codes: -32700 (parse), -32600 (invalid), -32601 (not found), -32602 (params), -32603 (internal)
  - [ ] A2A-specific error codes: -32001 (task not found), -32002 (task not cancelable), -32003 (push not supported), -32004 (unsupported operation), -32005 (content type not supported)

- [ ] **Tests** — Types serialization round-trip, JSON-RPC encode/decode, error codes

### Reference Files
- `/workspace/a2a-go/a2a.go` — All type definitions
- `/workspace/a2a-go/jsonrpc.go` — JSON-RPC types and error codes

---

## Phase 2: TaskStore + EventQueue + AgentExecutor

Storage and execution behaviours with in-memory implementations.

### Tasks

- [ ] **A2AEx.TaskStore** — Behaviour for task persistence
  - [ ] `@callback get(store, task_id) :: {:ok, Task.t()} | {:error, :not_found}`
  - [ ] `@callback save(store, Task.t()) :: :ok | {:error, term()}`
  - [ ] `@callback delete(store, task_id) :: :ok`

- [ ] **A2AEx.TaskStore.InMemory** — GenServer + ETS implementation
  - [ ] GenServer for serialized writes
  - [ ] ETS table for concurrent reads
  - [ ] Keyed by task_id

- [ ] **A2AEx.EventQueue** — Per-task event delivery
  - [ ] GenServer per task (started on demand)
  - [ ] `enqueue(task_id, event)` — send event to all subscribers
  - [ ] `subscribe(task_id)` — returns a stream or callback-based subscription
  - [ ] `close(task_id)` — signal completion, clean up
  - [ ] Registry-based lookup (Elixir Registry)

- [ ] **A2AEx.AgentExecutor** — Behaviour for agent execution
  - [ ] `@callback execute(executor, request_params, event_queue) :: :ok | {:error, term()}`
  - [ ] `@callback cancel(executor, request_params) :: :ok | {:error, term()}`

- [ ] **Tests** — TaskStore CRUD, EventQueue pub/sub, AgentExecutor mock

### Reference Files
- `/workspace/a2a-go/server/task_store.go` — TaskStore interface + InMemoryTaskStore
- `/workspace/a2a-go/server/event_queue.go` — EventQueue + EventQueueManager
- `/workspace/a2a-go/server/server.go` — AgentExecutor interface

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
- `/workspace/a2a-go/server/server.go` — A2AServer + handlers
- `/workspace/a2a-go/server/request_handler.go` — RequestHandler implementation

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
- `/workspace/a2a-go/client/client.go` — Client implementation
- `/workspace/a2a-go/client/transport.go` — Transport interface

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
