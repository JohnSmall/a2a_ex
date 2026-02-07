defmodule A2AEx.TypesTest do
  use ExUnit.Case, async: true

  describe "A2AEx.ID" do
    test "generates valid UUID v4 format" do
      id = A2AEx.ID.new()
      assert Regex.match?(~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/, id)
    end

    test "generates unique IDs" do
      ids = for _ <- 1..100, do: A2AEx.ID.new()
      assert length(Enum.uniq(ids)) == 100
    end
  end

  describe "A2AEx.Message" do
    test "new/2 creates message with random id" do
      msg = A2AEx.Message.new(:user, [%A2AEx.TextPart{text: "hello"}])
      assert msg.role == :user
      assert msg.id != nil
      assert length(msg.parts) == 1
    end

    test "to_map/1 produces camelCase keys" do
      msg = %A2AEx.Message{
        id: "msg-1",
        role: :agent,
        parts: [%A2AEx.TextPart{text: "hi"}],
        context_id: "ctx-1",
        task_id: "task-1"
      }

      map = A2AEx.Message.to_map(msg)
      assert map["kind"] == "message"
      assert map["messageId"] == "msg-1"
      assert map["role"] == "agent"
      assert map["contextId"] == "ctx-1"
      assert map["taskId"] == "task-1"
      assert length(map["parts"]) == 1
    end

    test "from_map/1 decodes camelCase map" do
      map = %{
        "messageId" => "msg-1",
        "role" => "user",
        "parts" => [%{"kind" => "text", "text" => "hello"}],
        "contextId" => "ctx-1"
      }

      assert {:ok, msg} = A2AEx.Message.from_map(map)
      assert msg.id == "msg-1"
      assert msg.role == :user
      assert msg.context_id == "ctx-1"
      assert [%A2AEx.TextPart{text: "hello"}] = msg.parts
    end

    test "JSON round-trip" do
      msg = A2AEx.Message.new(:user, [%A2AEx.TextPart{text: "test"}])
      json = Jason.encode!(msg)
      decoded = Jason.decode!(json)
      assert {:ok, msg2} = A2AEx.Message.from_map(decoded)
      assert msg2.role == :user
      assert [%A2AEx.TextPart{text: "test"}] = msg2.parts
    end

    test "omits nil optional fields" do
      msg = %A2AEx.Message{id: "m1", role: :user, parts: []}
      map = A2AEx.Message.to_map(msg)
      refute Map.has_key?(map, "contextId")
      refute Map.has_key?(map, "taskId")
      refute Map.has_key?(map, "metadata")
    end
  end

  describe "A2AEx.TaskState" do
    test "round-trip all states" do
      states = [
        :submitted,
        :working,
        :input_required,
        :completed,
        :failed,
        :canceled,
        :rejected,
        :auth_required,
        :unknown
      ]

      for state <- states do
        str = A2AEx.TaskState.to_string(state)
        assert A2AEx.TaskState.from_string(str) == state
      end
    end

    test "terminal? returns true for terminal states" do
      assert A2AEx.TaskState.terminal?(:completed)
      assert A2AEx.TaskState.terminal?(:canceled)
      assert A2AEx.TaskState.terminal?(:failed)
      assert A2AEx.TaskState.terminal?(:rejected)
    end

    test "terminal? returns false for non-terminal states" do
      refute A2AEx.TaskState.terminal?(:submitted)
      refute A2AEx.TaskState.terminal?(:working)
      refute A2AEx.TaskState.terminal?(:input_required)
    end

    test "hyphenated string encoding" do
      assert A2AEx.TaskState.to_string(:input_required) == "input-required"
      assert A2AEx.TaskState.to_string(:auth_required) == "auth-required"
    end
  end

  describe "A2AEx.TaskStatus" do
    test "from_map/1 and to_map/1 round-trip" do
      map = %{"state" => "working"}
      assert {:ok, status} = A2AEx.TaskStatus.from_map(map)
      assert status.state == :working
      result = A2AEx.TaskStatus.to_map(status)
      assert result["state"] == "working"
    end

    test "with message and timestamp" do
      now = DateTime.utc_now()

      map = %{
        "state" => "completed",
        "message" => %{
          "messageId" => "m1",
          "role" => "agent",
          "parts" => [%{"kind" => "text", "text" => "done"}]
        },
        "timestamp" => DateTime.to_iso8601(now)
      }

      assert {:ok, status} = A2AEx.TaskStatus.from_map(map)
      assert status.state == :completed
      assert status.message.role == :agent
      assert status.timestamp != nil
    end
  end

  describe "A2AEx.Task" do
    test "new_submitted/1 creates task in submitted state" do
      msg = A2AEx.Message.new(:user, [%A2AEx.TextPart{text: "hi"}])
      task = A2AEx.Task.new_submitted(msg)
      assert task.status.state == :submitted
      assert task.id != nil
      assert task.context_id != nil
      assert [^msg] = task.history
    end

    test "to_map/1 produces camelCase keys with kind" do
      task = %A2AEx.Task{
        id: "t1",
        context_id: "c1",
        status: %A2AEx.TaskStatus{state: :working}
      }

      map = A2AEx.Task.to_map(task)
      assert map["kind"] == "task"
      assert map["id"] == "t1"
      assert map["contextId"] == "c1"
      assert map["status"]["state"] == "working"
    end

    test "JSON round-trip" do
      msg = A2AEx.Message.new(:user, [%A2AEx.TextPart{text: "hello"}])
      task = A2AEx.Task.new_submitted(msg)
      json = Jason.encode!(task)
      decoded = Jason.decode!(json)
      assert {:ok, task2} = A2AEx.Task.from_map(decoded)
      assert task2.id == task.id
      assert task2.status.state == :submitted
    end
  end

  describe "A2AEx.Artifact" do
    test "from_map/1 and to_map/1 round-trip" do
      map = %{
        "artifactId" => "a1",
        "name" => "result.txt",
        "description" => "The output",
        "parts" => [%{"kind" => "text", "text" => "output data"}]
      }

      assert {:ok, artifact} = A2AEx.Artifact.from_map(map)
      assert artifact.id == "a1"
      assert artifact.name == "result.txt"

      result = A2AEx.Artifact.to_map(artifact)
      assert result["artifactId"] == "a1"
      assert result["name"] == "result.txt"
    end

    test "JSON round-trip" do
      artifact = %A2AEx.Artifact{
        id: "a1",
        parts: [%A2AEx.TextPart{text: "data"}],
        name: "test"
      }

      json = Jason.encode!(artifact)
      decoded = Jason.decode!(json)
      assert {:ok, a2} = A2AEx.Artifact.from_map(decoded)
      assert a2.id == "a1"
      assert a2.name == "test"
    end
  end

  describe "A2AEx.TaskStatusUpdateEvent" do
    test "new/3 creates event with timestamp" do
      event = A2AEx.TaskStatusUpdateEvent.new("t1", "c1", :working)
      assert event.task_id == "t1"
      assert event.context_id == "c1"
      assert event.status.state == :working
      assert %DateTime{} = event.status.timestamp
    end

    test "to_map/1 includes kind" do
      event = A2AEx.TaskStatusUpdateEvent.new("t1", "c1", :completed)
      map = A2AEx.TaskStatusUpdateEvent.to_map(event)
      assert map["kind"] == "status-update"
      assert map["taskId"] == "t1"
      assert map["status"]["state"] == "completed"
    end

    test "JSON round-trip" do
      event = A2AEx.TaskStatusUpdateEvent.new("t1", "c1", :working)
      json = Jason.encode!(event)
      decoded = Jason.decode!(json)
      assert {:ok, e2} = A2AEx.TaskStatusUpdateEvent.from_map(decoded)
      assert e2.task_id == "t1"
      assert e2.status.state == :working
    end
  end

  describe "A2AEx.TaskArtifactUpdateEvent" do
    test "from_map/1 and to_map/1 round-trip" do
      event = %A2AEx.TaskArtifactUpdateEvent{
        task_id: "t1",
        context_id: "c1",
        artifact: %A2AEx.Artifact{id: "a1", parts: [%A2AEx.TextPart{text: "data"}]}
      }

      map = A2AEx.TaskArtifactUpdateEvent.to_map(event)
      assert map["kind"] == "artifact-update"
      assert map["taskId"] == "t1"

      assert {:ok, e2} = A2AEx.TaskArtifactUpdateEvent.from_map(map)
      assert e2.task_id == "t1"
      assert e2.artifact.id == "a1"
    end

    test "append and lastChunk flags" do
      event = %A2AEx.TaskArtifactUpdateEvent{
        task_id: "t1",
        context_id: "c1",
        artifact: %A2AEx.Artifact{id: "a1", parts: []},
        append: true,
        last_chunk: true
      }

      map = A2AEx.TaskArtifactUpdateEvent.to_map(event)
      assert map["append"] == true
      assert map["lastChunk"] == true
    end

    test "omits false flags" do
      event = %A2AEx.TaskArtifactUpdateEvent{
        task_id: "t1",
        context_id: "c1",
        artifact: %A2AEx.Artifact{id: "a1", parts: []}
      }

      map = A2AEx.TaskArtifactUpdateEvent.to_map(event)
      refute Map.has_key?(map, "append")
      refute Map.has_key?(map, "lastChunk")
    end
  end

  describe "A2AEx.Event" do
    test "from_map dispatches on kind" do
      assert {:ok, %A2AEx.Message{}} =
               A2AEx.Event.from_map(%{
                 "kind" => "message",
                 "messageId" => "m1",
                 "role" => "user",
                 "parts" => []
               })

      assert {:ok, %A2AEx.Task{}} =
               A2AEx.Event.from_map(%{
                 "kind" => "task",
                 "id" => "t1",
                 "contextId" => "c1",
                 "status" => %{"state" => "submitted"}
               })

      assert {:ok, %A2AEx.TaskStatusUpdateEvent{}} =
               A2AEx.Event.from_map(%{
                 "kind" => "status-update",
                 "taskId" => "t1",
                 "contextId" => "c1",
                 "status" => %{"state" => "working"}
               })

      assert {:ok, %A2AEx.TaskArtifactUpdateEvent{}} =
               A2AEx.Event.from_map(%{
                 "kind" => "artifact-update",
                 "taskId" => "t1",
                 "contextId" => "c1",
                 "artifact" => %{"artifactId" => "a1", "parts" => []}
               })
    end

    test "unknown kind returns error" do
      assert {:error, "unknown event kind: foo"} = A2AEx.Event.from_map(%{"kind" => "foo"})
    end

    test "missing kind returns error" do
      assert {:error, "missing event kind"} = A2AEx.Event.from_map(%{})
    end
  end
end
