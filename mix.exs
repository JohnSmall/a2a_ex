defmodule A2AEx.MixProject do
  use Mix.Project

  @version "1.0.1"
  @source_url "https://github.com/JohnSmall/a2a-elixir-sdk"

  def project do
    [
      app: :a2a_elixir_sdk,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [plt_add_apps: [:mix, :ex_unit]],
      description: description(),
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {A2AEx.Application, []}
    ]
  end

  defp deps do
    [
      {:adk_ex, "~> 1.0"},
      {:plug, "~> 1.16"},
      {:jason, "~> 1.4"},
      {:req, "~> 0.5"},
      {:bandit, "~> 1.0", only: [:dev, :test]},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "Elixir implementation of the Agent-to-Agent (A2A) protocol. " <>
      "Exposes ADK agents as A2A-compatible HTTP endpoints and consumes " <>
      "remote A2A agents as local ADK agents."
  end

  defp package do
    [
      name: "a2a_elixir_sdk",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "A2A Protocol" => "https://github.com/a2aproject/A2A"
      },
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md
           usage-rules.md usage-rules)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "CHANGELOG.md",
        {"usage-rules.md", title: "LLM Usage Rules"}
      ],
      groups_for_modules: [
        "Core Types": [
          A2AEx.AgentCard,
          A2AEx.AgentCapabilities,
          A2AEx.AgentSkill,
          A2AEx.Message,
          A2AEx.Task,
          A2AEx.TaskState,
          A2AEx.TaskStatus,
          A2AEx.Artifact,
          A2AEx.Part,
          A2AEx.TextPart,
          A2AEx.FilePart,
          A2AEx.DataPart,
          A2AEx.FileBytes,
          A2AEx.FileURI,
          A2AEx.Event,
          A2AEx.TaskStatusUpdateEvent,
          A2AEx.TaskArtifactUpdateEvent,
          A2AEx.Error,
          A2AEx.ID
        ],
        "JSON-RPC": [
          A2AEx.JSONRPC,
          A2AEx.TaskIDParams,
          A2AEx.TaskQueryParams,
          A2AEx.MessageSendParams,
          A2AEx.PushConfig,
          A2AEx.PushAuthInfo,
          A2AEx.TaskPushConfig
        ],
        Server: [
          A2AEx.Server,
          A2AEx.RequestHandler,
          A2AEx.RequestContext,
          A2AEx.AgentExecutor,
          A2AEx.TaskStore,
          A2AEx.TaskStore.InMemory,
          A2AEx.EventQueue,
          A2AEx.PushConfigStore,
          A2AEx.PushConfigStore.InMemory,
          A2AEx.PushSender,
          A2AEx.PushSender.HTTP
        ],
        "ADK Bridge": [
          A2AEx.ADKExecutor,
          A2AEx.ADKExecutor.Config,
          A2AEx.Converter
        ],
        Client: [
          A2AEx.Client,
          A2AEx.Client.SSE,
          A2AEx.RemoteAgent,
          A2AEx.RemoteAgent.Config
        ]
      ]
    ]
  end
end
