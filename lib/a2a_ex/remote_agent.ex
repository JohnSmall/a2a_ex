defmodule A2AEx.RemoteAgent.Config do
  @moduledoc """
  Configuration for creating a remote A2A agent.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          url: String.t(),
          agent_card: A2AEx.AgentCard.t() | nil,
          client_opts: keyword()
        }

  @enforce_keys [:name, :url]
  defstruct [
    :name,
    :url,
    :agent_card,
    description: "",
    client_opts: []
  ]
end

defmodule A2AEx.RemoteAgent do
  @moduledoc """
  An ADK agent backed by a remote A2A server.

  Wraps `A2AEx.Client` as an `ADK.Agent` implementation, enabling remote
  A2A agents to participate in ADK orchestration (Sequential, Parallel, etc.).

  Converts the invocation context's user content to an A2A message, sends it
  to the remote agent via streaming, and converts the A2A events back to ADK events.

  ## Usage

      config = %A2AEx.RemoteAgent.Config{
        name: "remote-helper",
        url: "http://remote-host:4000",
        description: "A remote helper agent"
      }

      agent = A2AEx.RemoteAgent.new(config)

      # Use as a sub-agent in a SequentialAgent, ParallelAgent, etc.
      # Or run directly via ADK.Runner
  """

  alias A2AEx.{Client, Converter}
  alias ADK.Agent.{Config, CustomAgent, InvocationContext}
  alias ADK.Event
  alias ADK.Types.Content

  @doc """
  Creates a new remote agent from a RemoteAgent.Config.

  Returns an `ADK.Agent.CustomAgent` struct that can be used anywhere
  an ADK agent is expected.
  """
  @spec new(A2AEx.RemoteAgent.Config.t()) :: CustomAgent.t()
  def new(%A2AEx.RemoteAgent.Config{} = remote_config) do
    CustomAgent.new(%Config{
      name: remote_config.name,
      description: remote_config.description,
      run: fn ctx -> run(ctx, remote_config) end
    })
  end

  # --- Private: run logic ---

  defp run(%InvocationContext{} = ctx, remote_config) do
    client = Client.new(remote_config.url, remote_config.client_opts)

    case build_message(ctx) do
      {:ok, params} ->
        dispatch_request(client, ctx, params)

      {:error, reason} ->
        [make_error_event(ctx, reason)]
    end
  end

  defp build_message(%InvocationContext{user_content: %Content{} = content}) do
    message = Converter.adk_content_to_message(content)
    params = %{"message" => A2AEx.Message.to_map(message)}
    {:ok, params}
  end

  defp build_message(_ctx) do
    {:error, "no user content in invocation context"}
  end

  defp dispatch_request(client, ctx, params) do
    if ctx.run_config.streaming_mode == :sse do
      stream_request(client, ctx, params)
    else
      sync_request(client, ctx, params)
    end
  end

  # --- Streaming path ---

  defp stream_request(client, ctx, params) do
    {:ok, stream} = Client.stream_message(client, params)
    Stream.flat_map(stream, &convert_a2a_event(&1, ctx))
  end

  # --- Sync path ---

  defp sync_request(client, ctx, params) do
    case Client.send_message(client, params) do
      {:ok, result} ->
        convert_task_result(result, ctx)

      {:error, reason} ->
        [make_error_event(ctx, "send failed: #{inspect(reason)}")]
    end
  end

  defp convert_task_result(result, ctx) when is_map(result) do
    events = convert_status_message(result["status"], ctx)

    artifact_events =
      (result["artifacts"] || [])
      |> Enum.flat_map(&convert_artifact_map(&1, ctx))

    artifact_events ++ events
  end

  defp convert_status_message(%{"state" => state, "message" => msg}, ctx) when is_map(msg) do
    case parse_parts_from_map(msg) do
      {:ok, adk_parts} when adk_parts != [] ->
        content = %Content{role: "model", parts: adk_parts}
        event = Event.new(invocation_id: ctx.invocation_id, branch: ctx.branch, author: agent_name(ctx), content: content)
        [apply_state_metadata(event, state)]

      _ ->
        []
    end
  end

  defp convert_status_message(_, _ctx), do: []

  defp convert_artifact_map(%{"parts" => parts}, ctx) when is_list(parts) and parts != [] do
    case parse_raw_parts(parts) do
      {:ok, adk_parts} when adk_parts != [] ->
        content = %Content{role: "model", parts: adk_parts}
        [Event.new(invocation_id: ctx.invocation_id, branch: ctx.branch, author: agent_name(ctx), content: content)]

      _ ->
        []
    end
  end

  defp convert_artifact_map(_, _ctx), do: []

  # --- A2A event → ADK event conversion (streaming) ---

  defp convert_a2a_event(%A2AEx.Task{} = task, ctx) do
    task_map = A2AEx.Task.to_map(task)
    status_events = convert_status_message(task_map["status"], ctx)

    artifact_events =
      (task_map["artifacts"] || [])
      |> Enum.flat_map(&convert_artifact_map(&1, ctx))
      |> Enum.map(&%{&1 | partial: true})

    artifact_events ++ status_events
  end

  defp convert_a2a_event(%A2AEx.TaskStatusUpdateEvent{} = event, ctx) do
    convert_streaming_status(event, ctx)
  end

  defp convert_a2a_event(%A2AEx.TaskArtifactUpdateEvent{} = event, ctx) do
    convert_streaming_artifact(event, ctx)
  end

  defp convert_a2a_event(_event, _ctx), do: []

  defp convert_streaming_status(%A2AEx.TaskStatusUpdateEvent{status: status}, ctx) do
    case status.message do
      %A2AEx.Message{parts: parts} when is_list(parts) and parts != [] ->
        {:ok, adk_parts} = Converter.a2a_parts_to_adk(parts)
        content = %Content{role: "model", parts: adk_parts}

        event =
          Event.new(
            invocation_id: ctx.invocation_id,
            branch: ctx.branch,
            author: agent_name(ctx),
            content: content
          )

        [apply_state_metadata(event, status.state)]

      _ ->
        []
    end
  end

  defp convert_streaming_artifact(%A2AEx.TaskArtifactUpdateEvent{artifact: artifact}, ctx) do
    case artifact.parts do
      parts when is_list(parts) and parts != [] ->
        {:ok, adk_parts} = Converter.a2a_parts_to_adk(parts)
        content = %Content{role: "model", parts: adk_parts}

        [
          Event.new(
            invocation_id: ctx.invocation_id,
            branch: ctx.branch,
            author: agent_name(ctx),
            content: content,
            partial: true
          )
        ]

      _ ->
        []
    end
  end

  # --- Helpers ---

  defp make_error_event(ctx, reason) do
    Event.new(
      invocation_id: ctx.invocation_id,
      branch: ctx.branch,
      author: agent_name(ctx),
      error_message: to_string(reason)
    )
  end

  defp apply_state_metadata(event, :failed) do
    %{event | error_code: "remote_agent_error", error_message: "remote agent failed"}
  end

  defp apply_state_metadata(event, "failed") do
    %{event | error_code: "remote_agent_error", error_message: "remote agent failed"}
  end

  defp apply_state_metadata(event, :input_required) do
    %{event | long_running_tool_ids: ["remote_input_required"]}
  end

  defp apply_state_metadata(event, "input_required") do
    %{event | long_running_tool_ids: ["remote_input_required"]}
  end

  defp apply_state_metadata(event, _state), do: event

  defp agent_name(%InvocationContext{agent: agent}) when agent != nil do
    agent.__struct__.name(agent)
  end

  defp agent_name(_), do: nil

  defp parse_parts_from_map(%{"parts" => parts}) when is_list(parts) do
    parse_raw_parts(parts)
  end

  defp parse_parts_from_map(_), do: {:ok, []}

  defp parse_raw_parts(parts) do
    a2a_parts =
      Enum.flat_map(parts, fn raw ->
        case A2AEx.Part.from_map(raw) do
          {:ok, part} -> [part]
          _ -> []
        end
      end)

    Converter.a2a_parts_to_adk(a2a_parts)
  end
end
