defmodule A2AEx.AgentCardTest do
  use ExUnit.Case, async: true

  describe "AgentCapabilities" do
    test "from_map/1 defaults to false" do
      caps = A2AEx.AgentCapabilities.from_map(%{})
      refute caps.streaming
      refute caps.push_notifications
      refute caps.state_transition_history
    end

    test "from_map/1 reads booleans" do
      caps = A2AEx.AgentCapabilities.from_map(%{
        "streaming" => true,
        "pushNotifications" => true,
        "stateTransitionHistory" => true
      })

      assert caps.streaming
      assert caps.push_notifications
      assert caps.state_transition_history
    end

    test "to_map/1 omits false values" do
      caps = %A2AEx.AgentCapabilities{}
      assert A2AEx.AgentCapabilities.to_map(caps) == %{}
    end

    test "to_map/1 includes true values" do
      caps = %A2AEx.AgentCapabilities{streaming: true, push_notifications: true}
      map = A2AEx.AgentCapabilities.to_map(caps)
      assert map["streaming"] == true
      assert map["pushNotifications"] == true
      refute Map.has_key?(map, "stateTransitionHistory")
    end
  end

  describe "AgentSkill" do
    test "from_map/1 and to_map/1 round-trip" do
      map = %{
        "id" => "search",
        "name" => "Web Search",
        "description" => "Searches the web",
        "tags" => ["search", "web"],
        "examples" => ["Search for cats"]
      }

      skill = A2AEx.AgentSkill.from_map(map)
      assert skill.id == "search"
      assert skill.name == "Web Search"
      assert skill.tags == ["search", "web"]
      assert skill.examples == ["Search for cats"]

      result = A2AEx.AgentSkill.to_map(skill)
      assert result["id"] == "search"
      assert result["tags"] == ["search", "web"]
    end
  end

  describe "AgentCard" do
    @valid_card_map %{
      "name" => "TestAgent",
      "description" => "A test agent",
      "url" => "https://example.com/agent",
      "version" => "1.0.0",
      "protocolVersion" => "0.3.0",
      "capabilities" => %{"streaming" => true},
      "skills" => [
        %{
          "id" => "echo",
          "name" => "Echo",
          "description" => "Echoes input",
          "tags" => ["echo"]
        }
      ],
      "defaultInputModes" => ["text/plain"],
      "defaultOutputModes" => ["text/plain"],
      "provider" => %{"organization" => "TestOrg", "url" => "https://testorg.com"}
    }

    test "from_map/1 decodes full card" do
      assert {:ok, card} = A2AEx.AgentCard.from_map(@valid_card_map)
      assert card.name == "TestAgent"
      assert card.url == "https://example.com/agent"
      assert card.version == "1.0.0"
      assert card.capabilities.streaming == true
      assert length(card.skills) == 1
      assert card.provider.organization == "TestOrg"
    end

    test "to_map/1 produces camelCase keys" do
      assert {:ok, card} = A2AEx.AgentCard.from_map(@valid_card_map)
      map = A2AEx.AgentCard.to_map(card)
      assert map["name"] == "TestAgent"
      assert map["protocolVersion"] == "0.3.0"
      assert map["defaultInputModes"] == ["text/plain"]
      assert is_map(map["capabilities"])
      assert is_list(map["skills"])
      assert map["provider"]["organization"] == "TestOrg"
    end

    test "JSON round-trip" do
      assert {:ok, card} = A2AEx.AgentCard.from_map(@valid_card_map)
      json = Jason.encode!(card)
      decoded = Jason.decode!(json)
      assert {:ok, card2} = A2AEx.AgentCard.from_map(decoded)
      assert card2.name == card.name
      assert card2.version == card.version
      assert card2.capabilities.streaming == true
    end

    test "from_map/1 with minimal fields" do
      map = %{
        "name" => "Minimal",
        "description" => "A minimal agent",
        "url" => "https://example.com",
        "version" => "0.1.0"
      }

      assert {:ok, card} = A2AEx.AgentCard.from_map(map)
      assert card.name == "Minimal"
      assert card.capabilities.streaming == false
      assert card.skills == []
      assert card.provider == nil
    end

    test "omits nil optional fields in to_map" do
      card = %A2AEx.AgentCard{
        name: "Test",
        description: "Test",
        url: "https://example.com",
        version: "1.0"
      }

      map = A2AEx.AgentCard.to_map(card)
      refute Map.has_key?(map, "provider")
      refute Map.has_key?(map, "documentationUrl")
      refute Map.has_key?(map, "iconUrl")
      refute Map.has_key?(map, "supportsAuthenticatedExtendedCard")
    end
  end
end
