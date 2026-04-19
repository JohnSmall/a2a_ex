# A2AEx Type Encoding Rules

## snake_case Elixir, camelCase JSON

A2A wire format is camelCase; Elixir structs use snake_case. Every type that crosses the boundary implements a custom `Jason.Encoder` + a `from_map/1` constructor that translates both directions.

- Encoding: `Jason.encode!(struct)` yields camelCase JSON.
- Decoding: `Module.from_map(parsed_map)` accepts camelCase string keys.

Never hand-roll the JSON — always go through the struct + `from_map`.

## "kind" discriminator on polymorphic types

All polymorphic types include a `"kind"` field in JSON for tagged decode:

| Parent         | `"kind"` values                                 |
|----------------|-------------------------------------------------|
| `A2AEx.Part`   | `"text"`, `"file"`, `"data"`                    |
| `A2AEx.Event`  | `"status-update"`, `"artifact-update"`          |
| `A2AEx.Task`   | `"task"`, `"message"`                           |
| `A2AEx.FilePart` body | `"bytes"` (FileBytes), `"uri"` (FileURI) |

Decode dispatches on `"kind"`:

```elixir
A2AEx.Part.from_map(%{"kind" => "text", "text" => "hi"})
# -> %A2AEx.TextPart{text: "hi"}

A2AEx.Event.from_map(%{"kind" => "status-update", ...})
# -> %A2AEx.TaskStatusUpdateEvent{...}
```

Forgetting `"kind"` when constructing JSON by hand causes silent decode failures.

## Key types

### `A2AEx.Message`

```elixir
%A2AEx.Message{
  role: :user | :agent,                  # atoms internally, strings on wire
  parts: [A2AEx.Part.t()],
  message_id: String.t(),                # UUID v4 via A2AEx.ID.generate/0
  context_id: String.t() | nil,
  task_id: String.t() | nil,
  kind: "message"
}
```

Use `A2AEx.Message.new(role, parts)` — it auto-fills `message_id`.

### `A2AEx.Task`

```elixir
%A2AEx.Task{
  id: String.t(),
  context_id: String.t(),
  status: %A2AEx.TaskStatus{state: TaskState.t(), message: Message.t() | nil, timestamp: DateTime.t()},
  artifacts: [A2AEx.Artifact.t()],
  history: [A2AEx.Message.t()],
  kind: "task"
}
```

`TaskState`:
`:submitted | :working | :input_required | :completed | :canceled | :failed | :rejected | :auth_required | :unknown`

Terminal (absorbing): `:completed`, `:canceled`, `:failed`, `:rejected`.

### Events

```elixir
A2AEx.TaskStatusUpdateEvent.new(task_id, context_id, state, message \\ nil)
A2AEx.TaskArtifactUpdateEvent.new(task_id, context_id, artifact)
```

Both have a `final: boolean` field. Set `final: true` on the last event in a task lifecycle — the SSE writer uses it to close the stream.

```elixir
event = %{event | final: true}
```

### `A2AEx.AgentCard`

```elixir
%A2AEx.AgentCard{
  name: String.t(),
  url: String.t(),
  version: String.t(),
  description: String.t() | nil,
  capabilities: %A2AEx.AgentCapabilities{
    streaming: boolean,
    push_notifications: boolean,
    state_transition_history: boolean
  },
  skills: [A2AEx.AgentSkill.t()],
  default_input_modes: [String.t()],   # e.g. ["text"]
  default_output_modes: [String.t()],
  supports_authenticated_extended_card: boolean
}
```

Capabilities default to all-false — set them explicitly if your executor supports streaming or push notifications, otherwise clients will not attempt those calls.

### `A2AEx.Error`

15 predefined errors. Construct via constructors, not raw maps:

```elixir
A2AEx.Error.task_not_found(task_id)
A2AEx.Error.task_not_cancelable(task_id)
A2AEx.Error.push_notification_not_supported()
A2AEx.Error.invalid_params("missing 'message'")
# etc.
```

Errors are returned as `{:error, A2AEx.Error.t()}` from handler methods and encoded into JSON-RPC error responses by `A2AEx.JSONRPC`.

## ID generation

`A2AEx.ID.generate/0` returns a UUID v4 string. Use it for `message_id`, `task_id`, `context_id`, `config_id`. Do not hand-roll IDs — stores and queues assume the uniqueness guarantee.

## defstruct ordering gotcha

Keyword-with-default fields must come **last** in `defstruct`:

```elixir
# Correct
defstruct [:a, :b, c: "default"]

# Invalid — compile error
defstruct [:a, c: "default", :b]
```

Affects every type module in A2AEx. If you add a new field with a default, move it to the end.
