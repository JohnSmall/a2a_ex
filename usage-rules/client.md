# A2AEx Client Usage Rules

## Creating a client

```elixir
client = A2AEx.Client.new("http://remote:4000")
# With options:
client = A2AEx.Client.new("http://remote:4000",
  receive_timeout: 5_000,       # default 120_000 — tuned for LLM agents
  headers: [{"authorization", "Bearer ..."}]
)
```

`A2AEx.Client` is a thin wrapper around `Req`. The default `receive_timeout` of 120 s is deliberate — Req's 15 s default is too short for LLM-backed agents. Override when calling fast local services.

## All 10 JSON-RPC methods

```elixir
{:ok, card}   = A2AEx.Client.get_agent_card(client)
{:ok, task}   = A2AEx.Client.send_message(client, params)
{:ok, stream} = A2AEx.Client.stream_message(client, params)
{:ok, task}   = A2AEx.Client.get_task(client, task_id)
{:ok, task}   = A2AEx.Client.cancel_task(client, task_id)

{:ok, cfg}    = A2AEx.Client.set_push_config(client, task_id, config)
{:ok, cfg}    = A2AEx.Client.get_push_config(client, task_id, config_id)
{:ok, list}   = A2AEx.Client.list_push_configs(client, task_id)
:ok           = A2AEx.Client.delete_push_config(client, task_id, config_id)

{:ok, stream} = A2AEx.Client.resubscribe(client, task_id)
{:ok, card}   = A2AEx.Client.get_extended_card(client)
```

## Streaming semantics

`stream_message/2` and `resubscribe/2` return a lazy `Enumerable`. Errors during streaming surface as you enumerate — not at the call site. Do NOT pattern-match `{:error, _}` on these calls — they always return `{:ok, stream}`:

```elixir
# Correct
{:ok, stream} = A2AEx.Client.stream_message(client, params)
try do
  Enum.each(stream, &handle_event/1)
rescue
  e -> Logger.error("stream failed: #{inspect(e)}")
end
```

## Message params shape

Use string-keyed maps matching the JSON wire format (camelCase):

```elixir
params = %{
  "message" => %{
    "role" => "user",
    "parts" => [
      %{"kind" => "text", "text" => "Hello"}
    ]
  },
  # Optional: continue an existing context
  "contextId" => existing_context_id,
  # Optional: blocking vs non-blocking
  "blocking" => true
}
```

## RemoteAgent — wrap remote A2A as local ADK agent

```elixir
remote = A2AEx.RemoteAgent.new(%A2AEx.RemoteAgent.Config{
  name: "researcher",
  url: "http://research-agent:4000",
  description: "Remote research agent",
  client_opts: [receive_timeout: 180_000]   # optional — merged into Client
})

# Now usable as a sub-agent inside ADK orchestration:
sequential = %ADK.Agent.SequentialAgent{
  name: "pipeline",
  sub_agents: [remote, local_writer_agent]
}
```

`RemoteAgent` wraps `ADK.Agent.CustomAgent` with a run function that:

1. Converts the incoming ADK `Content` → A2A `Message` params.
2. Opens an SSE stream via `Client.stream_message/2`.
3. Converts each A2A event back into ADK `Event` structs via `A2AEx.Converter`.
4. Yields them through the `ADK.Runner` event stream.

## SSE parser

`A2AEx.Client.SSE` parses SSE lines with cross-chunk buffering. You rarely call it directly — `Client.stream_message/2` wires it up. Useful to know when debugging: it handles the `data:` prefix, blank-line event boundaries, and partial lines that span HTTP response chunks.
