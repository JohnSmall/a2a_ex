defmodule A2AEx.AgentProvider do
  @moduledoc "Information about the agent's service provider."

  @type t :: %__MODULE__{
          organization: String.t(),
          url: String.t()
        }

  @enforce_keys [:organization, :url]
  defstruct [:organization, :url]
end

defmodule A2AEx.AgentCapabilities do
  @moduledoc "Optional capabilities supported by an agent."

  @type t :: %__MODULE__{
          streaming: boolean(),
          push_notifications: boolean(),
          state_transition_history: boolean()
        }

  defstruct streaming: false, push_notifications: false, state_transition_history: false

  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      streaming: map["streaming"] || false,
      push_notifications: map["pushNotifications"] || false,
      state_transition_history: map["stateTransitionHistory"] || false
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = caps) do
    map = %{}
    map = if caps.streaming, do: Map.put(map, "streaming", true), else: map

    map =
      if caps.push_notifications, do: Map.put(map, "pushNotifications", true), else: map

    if caps.state_transition_history,
      do: Map.put(map, "stateTransitionHistory", true),
      else: map
  end
end

defmodule A2AEx.AgentSkill do
  @moduledoc "A distinct capability or function that an agent can perform."

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          description: String.t(),
          tags: [String.t()],
          examples: [String.t()] | nil,
          input_modes: [String.t()] | nil,
          output_modes: [String.t()] | nil
        }

  @enforce_keys [:id, :name, :description]
  defstruct [:id, :name, :description, :examples, :input_modes, :output_modes, tags: []]

  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      id: map["id"],
      name: map["name"],
      description: map["description"],
      tags: map["tags"] || [],
      examples: map["examples"],
      input_modes: map["inputModes"],
      output_modes: map["outputModes"]
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = skill) do
    %{
      "id" => skill.id,
      "name" => skill.name,
      "description" => skill.description,
      "tags" => skill.tags
    }
    |> maybe_put("examples", skill.examples)
    |> maybe_put("inputModes", skill.input_modes)
    |> maybe_put("outputModes", skill.output_modes)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

defmodule A2AEx.AgentCard do
  @moduledoc """
  A self-describing manifest for an agent. Provides essential metadata including
  the agent's identity, capabilities, skills, and supported communication methods.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          url: String.t(),
          version: String.t(),
          protocol_version: String.t(),
          capabilities: A2AEx.AgentCapabilities.t(),
          skills: [A2AEx.AgentSkill.t()],
          default_input_modes: [String.t()],
          default_output_modes: [String.t()],
          provider: A2AEx.AgentProvider.t() | nil,
          documentation_url: String.t() | nil,
          icon_url: String.t() | nil,
          supports_authenticated_extended_card: boolean(),
          security_schemes: map() | nil,
          security: [map()] | nil,
          preferred_transport: String.t() | nil
        }

  @enforce_keys [:name, :description, :url, :version]
  defstruct [
    :name,
    :description,
    :url,
    :version,
    :provider,
    :documentation_url,
    :icon_url,
    protocol_version: "0.3.0",
    capabilities: %A2AEx.AgentCapabilities{},
    skills: [],
    default_input_modes: ["text/plain"],
    default_output_modes: ["text/plain"],
    supports_authenticated_extended_card: false,
    security_schemes: nil,
    security: nil,
    preferred_transport: nil
  ]

  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(map) when is_map(map) do
    provider =
      case map["provider"] do
        %{"organization" => org, "url" => url} ->
          %A2AEx.AgentProvider{organization: org, url: url}

        _ ->
          nil
      end

    {:ok,
     %__MODULE__{
       name: map["name"],
       description: map["description"],
       url: map["url"],
       version: map["version"],
       protocol_version: map["protocolVersion"] || "0.3.0",
       capabilities: A2AEx.AgentCapabilities.from_map(map["capabilities"] || %{}),
       skills: Enum.map(map["skills"] || [], &A2AEx.AgentSkill.from_map/1),
       default_input_modes: map["defaultInputModes"] || ["text/plain"],
       default_output_modes: map["defaultOutputModes"] || ["text/plain"],
       provider: provider,
       documentation_url: map["documentationUrl"],
       icon_url: map["iconUrl"],
       supports_authenticated_extended_card:
         map["supportsAuthenticatedExtendedCard"] || false,
       security_schemes: map["securitySchemes"],
       security: map["security"],
       preferred_transport: map["preferredTransport"]
     }}
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = card) do
    %{
      "name" => card.name,
      "description" => card.description,
      "url" => card.url,
      "version" => card.version,
      "protocolVersion" => card.protocol_version,
      "capabilities" => A2AEx.AgentCapabilities.to_map(card.capabilities),
      "skills" => Enum.map(card.skills, &A2AEx.AgentSkill.to_map/1),
      "defaultInputModes" => card.default_input_modes,
      "defaultOutputModes" => card.default_output_modes
    }
    |> maybe_put_provider(card.provider)
    |> maybe_put("documentationUrl", card.documentation_url)
    |> maybe_put("iconUrl", card.icon_url)
    |> maybe_put_bool(
      "supportsAuthenticatedExtendedCard",
      card.supports_authenticated_extended_card
    )
    |> maybe_put("securitySchemes", card.security_schemes)
    |> maybe_put("security", card.security)
    |> maybe_put("preferredTransport", card.preferred_transport)
  end

  defp maybe_put_provider(map, nil), do: map

  defp maybe_put_provider(map, %A2AEx.AgentProvider{} = p) do
    Map.put(map, "provider", %{"organization" => p.organization, "url" => p.url})
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_bool(map, _key, false), do: map
  defp maybe_put_bool(map, key, true), do: Map.put(map, key, true)
end

defimpl Jason.Encoder, for: A2AEx.AgentCard do
  def encode(card, opts) do
    A2AEx.AgentCard.to_map(card) |> Jason.Encode.map(opts)
  end
end
