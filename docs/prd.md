# Product Requirements Document: A2AEx (Agent-to-Agent Protocol for Elixir)

## Document Info
- **Project**: A2AEx - Elixir implementation of the A2A protocol
- **Version**: 0.1.0
- **Date**: 2026-02-07
- **Status**: Scaffolded, ready for Phase 1 implementation
- **GitHub**: github.com/JohnSmall/a2a_ex
- **Depends on**: ADK (github.com/JohnSmall/adk)

---

## 1. Executive Summary

A2AEx implements the Agent-to-Agent (A2A) protocol in Elixir, enabling AI agents to communicate over HTTP using JSON-RPC. It builds on top of the ADK (Agent Development Kit) package, exposing ADK agents as A2A-compatible endpoints and allowing consumption of remote A2A agents as local ADK agents.

The A2A protocol is an open standard (https://github.com/a2aproject/A2A) for agent interoperability. A2AEx provides both server (expose agents) and client (consume agents) implementations.

---

## 2. Background

### 2.1 What is A2A?

The Agent-to-Agent (A2A) protocol defines a standard HTTP-based interface for AI agent communication. Key concepts:

- **Agent Card**: JSON metadata describing an agent's capabilities, skills, and endpoint URL
- **Task**: A unit of work with a lifecycle (submitted → working → completed/failed/canceled)
- **Message**: Communication unit containing Parts (text, file, data)
- **JSON-RPC 2.0**: Transport protocol over HTTP POST
- **SSE (Server-Sent Events)**: Streaming for long-running tasks

### 2.2 A2A Protocol Methods (JSON-RPC)

| Method | Purpose |
|--------|---------|
| `message/send` | Send message, get synchronous response |
| `message/stream` | Send message, get SSE stream of updates |
| `tasks/get` | Get current task state |
| `tasks/cancel` | Cancel a running task |
| `tasks/resubscribe` | Re-subscribe to SSE stream for existing task |
| `tasks/pushNotificationConfig/set` | Register push notification webhook |
| `tasks/pushNotificationConfig/get` | Get push config for a task |
| `tasks/pushNotificationConfig/delete` | Remove push config |
| `tasks/pushNotificationConfig/list` | List all push configs for a task |
| `agent/getAuthenticatedExtendedCard` | Get extended agent card (authenticated) |

### 2.3 Reference Materials

- **A2A Protocol Spec**: https://github.com/a2aproject/A2A
- **A2A Go SDK (PRIMARY reference)**: `/workspace/a2a-go/`
- **A2A Samples**: `/workspace/a2a-samples/` (Python, Go, Java, JS/TS, C#)
- **ADK-A2A Bridge (Go)**: `/workspace/adk-go/server/adka2a/`

### 2.4 Architecture of A2A Go SDK

The Go SDK uses a layered architecture:

```
HTTP Transport (net/http)
    → JSON-RPC Handler (parses method, dispatches)
        → RequestHandler (business logic, task lifecycle)
            → AgentExecutor (Execute/Cancel - the actual agent)
            → TaskStore (CRUD for tasks)
            → EventQueue (SSE event delivery)
            → PushConfigStore + PushSender (webhooks)
```

Key interfaces:
- `AgentExecutor`: `Execute(ctx, reqParams, eventQueue) error` + `Cancel(ctx, reqParams) error`
- `TaskStore`: `Get/Save/Delete` tasks
- `EventQueue`: `Enqueue(event)`, `Subscribe(taskID) <-chan Event`, `Close(taskID)`
- `RequestHandler`: Implements all 10 JSON-RPC methods

---

## 3. Goals and Non-Goals

### 3.1 Goals
1. **Full A2A protocol support** — All 10 JSON-RPC methods
2. **Server**: Expose any ADK agent as an A2A endpoint via Plug
3. **Client**: Consume remote A2A agents, optionally wrapping as ADK agents
4. **Streaming**: SSE support for `message/stream` and `tasks/resubscribe`
5. **Agent Card**: Build, serve, and parse agent cards
6. **Push notifications**: Webhook-based task update delivery
7. **Idiomatic Elixir/OTP** — GenServer for task store, processes for event queues
8. **ADK integration** — Convert ADK Events ↔ A2A Messages/Tasks seamlessly

### 3.2 Non-Goals
- Authentication/authorization (pluggable, not built-in)
- Agent discovery/registry beyond serving agent cards
- Multi-node distribution (single-node first)
- Google Cloud-specific integrations
- Protocol buffers / gRPC

---

## 4. Core Architecture

```
┌─────────────────────────────────────────┐
│              A2AEx.Server               │
│  (Plug Router - HTTP + JSON-RPC)        │
│                                         │
│  POST /  → JSON-RPC dispatch            │
│  GET /.well-known/agent.json → card     │
│  POST / (stream) → SSE response         │
└─────────┬───────────────────────────────┘
          │
┌─────────▼───────────────────────────────┐
│          A2AEx.RequestHandler           │
│  (Business logic for all 10 methods)    │
│                                         │
│  message/send → Execute + collect       │
│  message/stream → Execute + SSE         │
│  tasks/get → TaskStore.get              │
│  tasks/cancel → AgentExecutor.cancel    │
└────┬──────────┬──────────┬──────────────┘
     │          │          │
┌────▼───┐ ┌───▼────┐ ┌───▼──────────┐
│TaskStore│ │EventQ  │ │AgentExecutor │
│(ETS/DB)│ │(Process)│ │(ADK Runner)  │
└────────┘ └────────┘ └──────────────┘
```

### Component Mapping (Go SDK → Elixir)

| Go SDK | Elixir A2AEx | Pattern |
|--------|-------------|---------|
| `AgentExecutor` interface | `A2AEx.AgentExecutor` behaviour | `@callback execute/3`, `@callback cancel/2` |
| `TaskStore` interface | `A2AEx.TaskStore` behaviour | `@callback get/2`, `@callback save/2` |
| `InMemoryTaskStore` | `A2AEx.TaskStore.InMemory` | GenServer + ETS |
| `EventQueue` + `EventQueueManager` | `A2AEx.EventQueue` | GenServer per task, Registry for lookup |
| `RequestHandler` | `A2AEx.RequestHandler` | Module with functions for each method |
| `A2AServer` (net/http) | `A2AEx.Server` (Plug.Router) | Plug pipeline |
| `JSONRPCHandler` | `A2AEx.JSONRPC` | JSON-RPC 2.0 encode/decode |
| `Client` + `Transport` | `A2AEx.Client` | Req-based HTTP client |
| ADK Executor wrapper | `A2AEx.ADKExecutor` | Wraps ADK.Runner as AgentExecutor |
| Part converters | `A2AEx.Converter` | ADK.Types.Part ↔ A2A Part |
| Event converters | `A2AEx.Converter` | ADK.Event ↔ A2A TaskStatus/Artifact |
| `AgentCard` | `A2AEx.AgentCard` | Struct + JSON serialization |
| `RemoteAgent` (ADK agent) | `A2AEx.RemoteAgent` | ADK agent backed by A2A client |
| `PushNotificationSender` | `A2AEx.PushSender` | Req-based webhook delivery |
| `PushNotificationConfigStore` | `A2AEx.PushConfigStore` behaviour | InMemory impl |

---

## 5. Data Types

### 5.1 A2A Protocol Types

```elixir
# Task — the core work unit
%A2AEx.Task{
  id: String.t(),
  context_id: String.t(),       # groups related tasks
  status: TaskStatus.t(),
  artifacts: [Artifact.t()],
  metadata: map()
}

# TaskStatus — current state
%A2AEx.TaskStatus{
  state: :submitted | :working | :input_required | :completed | :failed | :canceled,
  message: Message.t() | nil,
  timestamp: DateTime.t()
}

# Message — communication unit
%A2AEx.Message{
  role: :user | :agent,
  parts: [Part.t()],
  metadata: map()
}

# Part — tagged union
%A2AEx.Part.Text{text: String.t()}
%A2AEx.Part.File{file: FileContent.t()}
%A2AEx.Part.Data{data: map()}

# Artifact — output produced by agent
%A2AEx.Artifact{
  artifact_id: String.t(),
  name: String.t() | nil,
  description: String.t() | nil,
  parts: [Part.t()],
  metadata: map()
}

# AgentCard — agent metadata
%A2AEx.AgentCard{
  name: String.t(),
  description: String.t(),
  url: String.t(),
  version: String.t(),
  capabilities: Capabilities.t(),
  skills: [Skill.t()],
  default_input_modes: [String.t()],
  default_output_modes: [String.t()]
}

# JSON-RPC
%A2AEx.JSONRPC.Request{jsonrpc: "2.0", method: String.t(), params: map(), id: term()}
%A2AEx.JSONRPC.Response{jsonrpc: "2.0", result: term(), id: term()}
%A2AEx.JSONRPC.Error{jsonrpc: "2.0", error: %{code: integer(), message: String.t()}, id: term()}
```

### 5.2 SSE Event Types

| Event Type | Payload | When |
|------------|---------|------|
| `TaskStatusUpdateEvent` | `%{id, status, final}` | Task state changes |
| `TaskArtifactUpdateEvent` | `%{id, artifact}` | New artifact produced |

---

## 6. Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Separate package from ADK | ADK is transport-agnostic; A2A adds HTTP/Plug deps |
| Plug (not Phoenix) for server | Lightweight, composable, no full framework needed |
| Req for HTTP client | Same as ADK, modern Elixir HTTP client |
| GenServer + ETS for TaskStore | Serialized writes, concurrent reads (same as ADK sessions) |
| Process per EventQueue | Natural backpressure, automatic cleanup on disconnect |
| Registry for EventQueue lookup | Built-in Elixir process registry, no external deps |
| Behaviours for AgentExecutor/TaskStore | Pluggable implementations (in-memory, database, custom) |
| ADKExecutor wraps ADK.Runner | Bridge between ADK's Stream-based execution and A2A's event-queue model |
| JSON-RPC as separate module | Reusable encode/decode, clean separation from business logic |
| Struct-based types | Consistent with ADK, dialyzer-friendly |

---

## 7. Technical Constraints

- **Elixir version**: >= 1.17
- **OTP version**: >= 26
- **Dependencies**: adk, plug, jason, req (runtime); ex_doc, dialyxir, credo (dev)
- **No Phoenix**: Use Plug.Router directly
- **No WebSocket**: A2A uses SSE for streaming, not WebSocket
- **ADK dependency**: Pull from GitHub (github.com/JohnSmall/adk)

---

## 8. Success Criteria

1. Server exposes ADK agent via A2A protocol (all 10 methods)
2. Client can call remote A2A agents
3. SSE streaming works for long-running tasks
4. Agent card served at `/.well-known/agent.json`
5. ADK Events convert to/from A2A Messages/Tasks correctly
6. RemoteAgent wraps remote A2A agent as local ADK agent
7. Test suite passes, dialyzer clean, credo clean
8. Interoperable with A2A Go SDK sample server/client
