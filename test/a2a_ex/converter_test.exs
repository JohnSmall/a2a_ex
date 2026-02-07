defmodule A2AEx.ConverterTest do
  use ExUnit.Case, async: true

  alias A2AEx.Converter
  alias ADK.Types.{Blob, Content, FunctionCall, FunctionResponse, Part}

  # --- ADK Part → A2A Part ---

  test "adk text part → a2a text part" do
    part = %Part{text: "hello"}
    assert {:ok, %A2AEx.TextPart{text: "hello", metadata: nil}} = Converter.adk_part_to_a2a(part)
  end

  test "adk thought text part → a2a text part with metadata" do
    part = %Part{text: "thinking...", thought: true}
    assert {:ok, %A2AEx.TextPart{text: "thinking...", metadata: meta}} = Converter.adk_part_to_a2a(part)
    assert meta["adk_thought"] == true
  end

  test "adk inline_data part → a2a file part with base64" do
    part = %Part{inline_data: %Blob{data: "raw bytes", mime_type: "image/png"}}
    assert {:ok, %A2AEx.FilePart{file: %A2AEx.FileBytes{bytes: b64, mime_type: "image/png"}}} =
             Converter.adk_part_to_a2a(part)
    assert Base.decode64!(b64) == "raw bytes"
  end

  test "adk function_call part → a2a data part" do
    fc = %FunctionCall{name: "search", id: "fc-1", args: %{"q" => "test"}}
    part = %Part{function_call: fc}
    assert {:ok, %A2AEx.DataPart{data: data, metadata: meta}} = Converter.adk_part_to_a2a(part)
    assert data["name"] == "search"
    assert data["id"] == "fc-1"
    assert data["args"] == %{"q" => "test"}
    assert meta["adk_type"] == "function_call"
  end

  test "adk function_response part → a2a data part" do
    fr = %FunctionResponse{name: "search", id: "fr-1", response: %{"result" => "ok"}}
    part = %Part{function_response: fr}
    assert {:ok, %A2AEx.DataPart{data: data, metadata: meta}} = Converter.adk_part_to_a2a(part)
    assert data["name"] == "search"
    assert data["id"] == "fr-1"
    assert data["response"] == %{"result" => "ok"}
    assert meta["adk_type"] == "function_response"
  end

  # --- A2A Part → ADK Part ---

  test "a2a text part → adk text part" do
    part = %A2AEx.TextPart{text: "hello"}
    assert {:ok, %Part{text: "hello", thought: false}} = Converter.a2a_part_to_adk(part)
  end

  test "a2a text part with thought metadata → adk thought part" do
    part = %A2AEx.TextPart{text: "thinking", metadata: %{"adk_thought" => true}}
    assert {:ok, %Part{text: "thinking", thought: true}} = Converter.a2a_part_to_adk(part)
  end

  test "a2a file part (bytes) → adk inline_data part" do
    b64 = Base.encode64("raw data")
    part = %A2AEx.FilePart{file: %A2AEx.FileBytes{bytes: b64, mime_type: "application/pdf"}}
    assert {:ok, %Part{inline_data: %Blob{data: "raw data", mime_type: "application/pdf"}}} =
             Converter.a2a_part_to_adk(part)
  end

  test "a2a file part (uri) → adk text part fallback" do
    part = %A2AEx.FilePart{file: %A2AEx.FileURI{uri: "https://example.com/file.pdf"}}
    assert {:ok, %Part{text: "https://example.com/file.pdf"}} = Converter.a2a_part_to_adk(part)
  end

  test "a2a data part function_call → adk function_call part" do
    part = %A2AEx.DataPart{
      data: %{"name" => "search", "id" => "fc-1", "args" => %{"q" => "test"}},
      metadata: %{"adk_type" => "function_call"}
    }
    assert {:ok, %Part{function_call: %FunctionCall{name: "search", id: "fc-1", args: %{"q" => "test"}}}} =
             Converter.a2a_part_to_adk(part)
  end

  test "a2a data part function_response → adk function_response part" do
    part = %A2AEx.DataPart{
      data: %{"name" => "search", "id" => "fr-1", "response" => %{"result" => "ok"}},
      metadata: %{"adk_type" => "function_response"}
    }
    assert {:ok, %Part{function_response: %FunctionResponse{name: "search", id: "fr-1", response: %{"result" => "ok"}}}} =
             Converter.a2a_part_to_adk(part)
  end

  test "a2a data part (generic) → adk text part with JSON" do
    part = %A2AEx.DataPart{data: %{"key" => "value"}}
    assert {:ok, %Part{text: json}} = Converter.a2a_part_to_adk(part)
    assert Jason.decode!(json) == %{"key" => "value"}
  end

  # --- Message ↔ Content ---

  test "a2a message (user) → adk content" do
    msg = A2AEx.Message.new(:user, [%A2AEx.TextPart{text: "hello"}])
    assert {:ok, %Content{role: "user", parts: [%Part{text: "hello"}]}} =
             Converter.a2a_message_to_content(msg)
  end

  test "a2a message (agent) → adk content with model role" do
    msg = A2AEx.Message.new(:agent, [%A2AEx.TextPart{text: "hi"}])
    assert {:ok, %Content{role: "model", parts: _}} = Converter.a2a_message_to_content(msg)
  end

  test "adk content (model) → a2a message with agent role" do
    content = Content.new_from_text("model", "Hello!")
    msg = Converter.adk_content_to_message(content)
    assert msg.role == :agent
    assert [%A2AEx.TextPart{text: "Hello!"}] = msg.parts
  end

  test "adk content (user) → a2a message with user role" do
    content = Content.new_from_text("user", "Question?")
    msg = Converter.adk_content_to_message(content)
    assert msg.role == :user
  end

  test "adk_content_to_message with opts sets context_id and task_id" do
    content = Content.new_from_text("model", "Reply")
    msg = Converter.adk_content_to_message(content, context_id: "ctx-1", task_id: "task-1")
    assert msg.context_id == "ctx-1"
    assert msg.task_id == "task-1"
  end

  # --- Terminal state ---

  test "terminal_state with error_code → :failed" do
    event = ADK.Event.new(error_code: "500", error_message: "server error")
    assert Converter.terminal_state(event) == :failed
  end

  test "terminal_state with only error_message → :failed" do
    event = ADK.Event.new(error_message: "something broke")
    assert Converter.terminal_state(event) == :failed
  end

  test "terminal_state with long_running_tool_ids → :input_required" do
    event = ADK.Event.new(long_running_tool_ids: ["tool-1"])
    assert Converter.terminal_state(event) == :input_required
  end

  test "terminal_state with escalate → :input_required" do
    event = ADK.Event.new(actions: %ADK.Event.Actions{escalate: true})
    assert Converter.terminal_state(event) == :input_required
  end

  test "terminal_state normal event → :completed" do
    event = ADK.Event.new(content: Content.new_from_text("model", "done"))
    assert Converter.terminal_state(event) == :completed
  end

  # --- Batch conversion ---

  test "adk_parts_to_a2a converts list" do
    parts = [%Part{text: "a"}, %Part{text: "b"}]
    assert {:ok, [%A2AEx.TextPart{text: "a"}, %A2AEx.TextPart{text: "b"}]} =
             Converter.adk_parts_to_a2a(parts)
  end

  test "a2a_parts_to_adk converts list" do
    parts = [%A2AEx.TextPart{text: "a"}, %A2AEx.TextPart{text: "b"}]
    assert {:ok, [%Part{text: "a"}, %Part{text: "b"}]} = Converter.a2a_parts_to_adk(parts)
  end
end
