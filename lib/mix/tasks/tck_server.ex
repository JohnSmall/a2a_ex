defmodule Mix.Tasks.Tck.Server do
  @moduledoc """
  Starts the A2A TCK System Under Test (SUT) server.

  ## Usage

      mix tck.server [--port PORT]

  Defaults to port 9999.
  """

  use Mix.Task

  @shortdoc "Starts the TCK SUT server"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    port = parse_port(args)

    {:ok, store} = A2AEx.TaskStore.InMemory.start_link(name: :"tck_task_store_#{port}")
    {:ok, push_store} = A2AEx.PushConfigStore.InMemory.start_link(name: :"tck_push_store_#{port}")

    handler = %A2AEx.RequestHandler{
      executor: A2AEx.TCK.Executor,
      task_store: {A2AEx.TaskStore.InMemory, store},
      push_config_store: {A2AEx.PushConfigStore.InMemory, push_store},
      push_sender: A2AEx.PushSender.HTTP,
      agent_card: build_agent_card(port)
    }

    {:ok, _} = Bandit.start_link(plug: {A2AEx.Server, [handler: handler]}, port: port)

    Mix.shell().info("TCK SUT running on http://localhost:#{port}")
    Mix.shell().info("Agent card at http://localhost:#{port}/.well-known/agent-card.json")
    Mix.shell().info("Press Ctrl+C to stop.")

    Process.sleep(:infinity)
  end

  defp parse_port(args) do
    case OptionParser.parse(args, strict: [port: :integer]) do
      {opts, _, _} -> Keyword.get(opts, :port, 9999)
    end
  end

  defp build_agent_card(port) do
    %A2AEx.AgentCard{
      name: "A2AEx TCK Agent",
      description: "Elixir A2A agent for TCK compliance testing",
      url: "http://localhost:#{port}/",
      version: "1.0.0",
      protocol_version: "0.3.0",
      capabilities: %A2AEx.AgentCapabilities{
        streaming: true,
        push_notifications: true,
        state_transition_history: true
      },
      skills: [
        %A2AEx.AgentSkill{
          id: "tck_echo",
          name: "TCK Echo Agent",
          description: "Echo agent for TCK compliance testing",
          tags: ["tck", "testing", "echo"]
        }
      ],
      default_input_modes: ["text"],
      default_output_modes: ["text"],
      preferred_transport: "jsonrpc"
    }
  end
end
