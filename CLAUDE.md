# A2AEx - Claude CLI Instructions

## Project Overview

Elixir implementation of the Agent-to-Agent (A2A) protocol. Exposes ADK agents as A2A-compatible HTTP endpoints and consumes remote A2A agents. Depends on the `adk` package (github.com/JohnSmall/adk).

## Quick Start

```bash
cd /workspace/a2a_ex
mix deps.get
mix test          # Run tests
mix credo         # Static analysis
mix dialyzer      # Type checking
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

**Phase 1 COMPLETE (83 tests, credo clean, dialyzer clean). Ready for Phase 2 (TaskStore + EventQueue + AgentExecutor).**

See `docs/implementation-plan.md` for the full 6-phase plan.

## Architecture Overview

```
A2AEx.Server (Plug.Router)
    → A2AEx.JSONRPC (parse/encode)
        → A2AEx.RequestHandler (10 methods)
            → A2AEx.AgentExecutor behaviour (execute/cancel)
            → A2AEx.TaskStore behaviour (CRUD tasks)
            → A2AEx.EventQueue (SSE delivery)
```

### Key Modules (Planned)

| Module | Purpose | Phase |
|--------|---------|-------|
| `A2AEx.Types` | A2A protocol types (Task, Message, Part, etc.) | 1 |
| `A2AEx.JSONRPC` | JSON-RPC 2.0 encode/decode | 1 |
| `A2AEx.TaskStore` | Task persistence behaviour + InMemory | 2 |
| `A2AEx.EventQueue` | Per-task SSE event delivery | 2 |
| `A2AEx.AgentExecutor` | Agent execution behaviour | 2 |
| `A2AEx.RequestHandler` | Business logic for all 10 methods | 3 |
| `A2AEx.Server` | Plug.Router HTTP endpoint | 3 |
| `A2AEx.ADKExecutor` | Wraps ADK.Runner as AgentExecutor | 4 |
| `A2AEx.Converter` | ADK ↔ A2A type conversion | 4 |
| `A2AEx.RemoteAgent` | ADK agent backed by A2A client | 4 |
| `A2AEx.Client` | HTTP client for remote A2A agents | 5 |
| `A2AEx.AgentCard` | Agent card struct + serialization | 1 |

## Critical Rules

1. **Read Go reference first**: Before implementing any module, read the corresponding file in `/workspace/a2a-go/`
2. **Compile order**: Define nested modules BEFORE parent modules in the same file
3. **Avoid MapSet**: Use `%{key => true}` maps (dialyzer opaque type issues)
4. **Credo nesting**: Max depth 2 — extract inner logic into helper functions
5. **Test module names**: Use unique names to avoid cross-file collisions
6. **Verify all changes**: Always run `mix test && mix credo && mix dialyzer`
7. **No Phoenix**: Use Plug.Router directly — keep dependencies minimal
8. **Struct-based types**: Match ADK conventions (defstruct + @type)

## Go Reference File Map

| A2AEx Module | Read This Go File |
|-------------|-------------------|
| Types | `/workspace/a2a-go/a2a.go` |
| JSONRPC | `/workspace/a2a-go/jsonrpc.go` |
| TaskStore | `/workspace/a2a-go/server/task_store.go` |
| EventQueue | `/workspace/a2a-go/server/event_queue.go` |
| AgentExecutor | `/workspace/a2a-go/server/server.go` |
| RequestHandler | `/workspace/a2a-go/server/request_handler.go` |
| Server | `/workspace/a2a-go/server/server.go` |
| ADKExecutor | `/workspace/adk-go/server/adka2a/executor.go` |
| Converter | `/workspace/adk-go/server/adka2a/part_converter.go` + `event_converter.go` |
| Client | `/workspace/a2a-go/client/client.go` |
