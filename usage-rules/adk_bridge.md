# A2AEx ADK Bridge Usage Rules

Two modules bridge ADK and A2A:

- `A2AEx.ADKExecutor` — an `AgentExecutor` implementation that runs an ADK agent
- `A2AEx.Converter` — pure functions that translate types in both directions

## ADKExecutor

Configured with a runner + app name, passed as a `{module, config}` executor tuple to `RequestHandler`:

```elixir
config = %A2AEx.ADKExecutor.Config{
  runner: runner,          # from ADK.Runner.new/1
  app_name: "my-app"       # must match the runner's app_name
}

handler = %A2AEx.RequestHandler{
  executor: {A2AEx.ADKExecutor, config},
  task_store: {A2AEx.TaskStore.InMemory, store_pid}
}
```

Under the hood, `execute/3`:

1. Converts the incoming A2A `Message` → ADK `Content` via `Converter.message_to_content/1`.
2. Calls `ADK.Runner.run(runner, user_id, session_id, content)` — yields a stream of ADK `Event` structs.
3. Translates each ADK event back to A2A (`TaskStatusUpdateEvent` or `TaskArtifactUpdateEvent`) and enqueues via `EventQueue.enqueue/2`.
4. When the ADK stream ends, enqueues a final status event with `final: true`.

`cancel/3` cooperates with ADK's cancellation mechanism and enqueues a `:canceled` terminal event.

## Converter

Pure module — no processes or state. Use these functions directly when building custom bridges:

### Parts

```elixir
A2AEx.Converter.adk_part_to_a2a_part(%ADK.Types.Part{...})   # -> A2AEx.{Text,File,Data}Part
A2AEx.Converter.a2a_part_to_adk_part(%A2AEx.TextPart{...})   # -> ADK.Types.Part
```

A2A has three part kinds (`text`/`file`/`data`); ADK `Part` carries any of them as tagged fields. The converter handles all three.

### Messages / Content

```elixir
A2AEx.Converter.content_to_message(%ADK.Types.Content{...})   # -> A2AEx.Message
A2AEx.Converter.message_to_content(%A2AEx.Message{...})       # -> ADK.Types.Content
```

Roles map directly: `user` ↔ `user`, `model` ↔ `agent`.

### Events

ADK emits a single `ADK.Event` stream carrying content + actions + metadata. A2A has two event kinds: `TaskStatusUpdateEvent` and `TaskArtifactUpdateEvent`. The converter decides which to emit based on the ADK event content — e.g. tool results with artifacts become `TaskArtifactUpdateEvent`, plain text replies become status updates.

### Terminal state detection

```elixir
A2AEx.Converter.terminal_state?(:completed)  # true
A2AEx.Converter.terminal_state?(:working)    # false
```

Used internally to decide when to set `final: true` on a status event.

## When to go direct vs use ADKExecutor

Use `ADKExecutor` when you already have an ADK agent and runner — you get full A2A protocol support for free.

Write a custom `AgentExecutor` when:
- You don't use ADK at all
- You want fine-grained control over event emission (e.g. batching artifacts)
- You're bridging to a non-ADK agent runtime

Even then, reach for `A2AEx.Converter` when your executor needs to produce A2A `Message`/`Part` structs from Elixir data — it handles all the type construction.
