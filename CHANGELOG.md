# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] - 2026-04-19

### Changed

- Documentation: recommend [Bandit](https://hex.pm/packages/bandit) (pure-Elixir)
  over Plug.Cowboy for mounting `A2AEx.Server`. The server itself is a plain
  Plug and does not depend on either — this is a docs-only change.

## [1.0.0] - 2026-04-19

First public release on hex.pm.

### Added

- Full A2A protocol server: all 10 JSON-RPC methods
  (`message/send`, `message/stream`, `tasks/get`, `tasks/cancel`,
  `tasks/pushNotificationConfig/{set,get,list,delete}`,
  `tasks/resubscribe`, `agent/authenticatedExtendedCard`)
- Plug-based HTTP endpoint (mount under [Bandit](https://hex.pm/packages/bandit)
  or any Plug-compatible server) with JSON-RPC dispatch and SSE streaming
- HTTP client for consuming remote A2A agents (sync + SSE streaming)
- `A2AEx.ADKExecutor` — bridge from `ADK.Runner` into the A2A protocol
- `A2AEx.Converter` — ADK `Event`/`Content` ↔ A2A `Message`/`Part` conversion
- `A2AEx.RemoteAgent` — wrap a remote A2A agent as a local ADK agent
- Agent card served at `/.well-known/agent.json`
- Webhook-based push notifications
- Pluggable `TaskStore` and `PushConfigStore` behaviours with in-memory
  (ETS + GenServer) default implementations
- A2A TCK compliance: Mandatory 30/30, Capabilities 32/32, Features 15/15,
  Quality 13/14
- 231 tests (unit + integration over real HTTP), credo clean, dialyzer clean
- LLM usage-rules (`usage-rules.md`) for agent-assisted development
