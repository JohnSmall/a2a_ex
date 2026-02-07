defmodule A2AEx.PartTest do
  use ExUnit.Case, async: true

  describe "TextPart" do
    test "to_map/1 includes kind discriminator" do
      part = %A2AEx.TextPart{text: "hello"}
      map = A2AEx.Part.to_map(part)
      assert map == %{"kind" => "text", "text" => "hello"}
    end

    test "to_map/1 includes metadata when present" do
      part = %A2AEx.TextPart{text: "hello", metadata: %{"key" => "val"}}
      map = A2AEx.Part.to_map(part)
      assert map["metadata"] == %{"key" => "val"}
    end

    test "from_map/1 decodes text part" do
      assert {:ok, %A2AEx.TextPart{text: "hello"}} =
               A2AEx.Part.from_map(%{"kind" => "text", "text" => "hello"})
    end

    test "JSON round-trip" do
      part = %A2AEx.TextPart{text: "test"}
      json = Jason.encode!(part)
      decoded = Jason.decode!(json)
      assert {:ok, %A2AEx.TextPart{text: "test"}} = A2AEx.Part.from_map(decoded)
    end
  end

  describe "FilePart with FileBytes" do
    test "to_map/1 encodes bytes file" do
      part = %A2AEx.FilePart{
        file: %A2AEx.FileBytes{bytes: "dGVzdA==", mime_type: "text/plain", name: "test.txt"}
      }

      map = A2AEx.Part.to_map(part)
      assert map["kind"] == "file"
      assert map["file"]["bytes"] == "dGVzdA=="
      assert map["file"]["mimeType"] == "text/plain"
      assert map["file"]["name"] == "test.txt"
    end

    test "from_map/1 decodes bytes file" do
      map = %{
        "kind" => "file",
        "file" => %{"bytes" => "dGVzdA==", "mimeType" => "text/plain", "name" => "test.txt"}
      }

      assert {:ok, %A2AEx.FilePart{file: %A2AEx.FileBytes{} = file}} = A2AEx.Part.from_map(map)
      assert file.bytes == "dGVzdA=="
      assert file.mime_type == "text/plain"
      assert file.name == "test.txt"
    end

    test "JSON round-trip" do
      part = %A2AEx.FilePart{
        file: %A2AEx.FileBytes{bytes: "dGVzdA==", mime_type: "application/pdf"}
      }

      json = Jason.encode!(part)
      decoded = Jason.decode!(json)
      assert {:ok, %A2AEx.FilePart{file: %A2AEx.FileBytes{bytes: "dGVzdA=="}}} = A2AEx.Part.from_map(decoded)
    end
  end

  describe "FilePart with FileURI" do
    test "to_map/1 encodes URI file" do
      part = %A2AEx.FilePart{file: %A2AEx.FileURI{uri: "https://example.com/file.pdf"}}
      map = A2AEx.Part.to_map(part)
      assert map["file"]["uri"] == "https://example.com/file.pdf"
    end

    test "from_map/1 decodes URI file" do
      map = %{"kind" => "file", "file" => %{"uri" => "https://example.com/file.pdf"}}

      assert {:ok, %A2AEx.FilePart{file: %A2AEx.FileURI{uri: "https://example.com/file.pdf"}}} =
               A2AEx.Part.from_map(map)
    end
  end

  describe "DataPart" do
    test "to_map/1 encodes data part" do
      part = %A2AEx.DataPart{data: %{"key" => "value"}}
      map = A2AEx.Part.to_map(part)
      assert map == %{"kind" => "data", "data" => %{"key" => "value"}}
    end

    test "from_map/1 decodes data part" do
      map = %{"kind" => "data", "data" => %{"key" => "value"}}
      assert {:ok, %A2AEx.DataPart{data: %{"key" => "value"}}} = A2AEx.Part.from_map(map)
    end

    test "JSON round-trip" do
      part = %A2AEx.DataPart{data: %{"count" => 42}}
      json = Jason.encode!(part)
      decoded = Jason.decode!(json)
      assert {:ok, %A2AEx.DataPart{data: %{"count" => 42}}} = A2AEx.Part.from_map(decoded)
    end
  end

  describe "from_map_list/1" do
    test "decodes multiple parts" do
      list = [
        %{"kind" => "text", "text" => "hello"},
        %{"kind" => "data", "data" => %{"x" => 1}}
      ]

      assert {:ok, [%A2AEx.TextPart{text: "hello"}, %A2AEx.DataPart{data: %{"x" => 1}}]} =
               A2AEx.Part.from_map_list(list)
    end

    test "returns error for invalid part in list" do
      list = [%{"kind" => "text", "text" => "ok"}, %{"kind" => "unknown"}]
      assert {:error, _} = A2AEx.Part.from_map_list(list)
    end
  end

  describe "error cases" do
    test "unknown kind returns error" do
      assert {:error, "unknown part kind: foo"} = A2AEx.Part.from_map(%{"kind" => "foo"})
    end

    test "missing kind returns error" do
      assert {:error, "missing or invalid part kind"} = A2AEx.Part.from_map(%{"text" => "hi"})
    end

    test "invalid file (no bytes or uri) returns error" do
      map = %{"kind" => "file", "file" => %{}}
      assert {:error, "invalid file part: either bytes or uri must be set"} = A2AEx.Part.from_map(map)
    end
  end
end
