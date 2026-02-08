defmodule A2AEx.JSONRPCTest do
  use ExUnit.Case, async: true

  describe "decode_request/1" do
    test "decodes valid request" do
      json = Jason.encode!(%{
        "jsonrpc" => "2.0",
        "method" => "message/send",
        "params" => %{"key" => "value"},
        "id" => 1
      })

      assert {:ok, req} = A2AEx.JSONRPC.decode_request(json)
      assert req.jsonrpc == "2.0"
      assert req.method == "message/send"
      assert req.params == %{"key" => "value"}
      assert req.id == 1
    end

    test "decodes request with string id" do
      json = Jason.encode!(%{"jsonrpc" => "2.0", "method" => "tasks/get", "id" => "abc-123"})
      assert {:ok, req} = A2AEx.JSONRPC.decode_request(json)
      assert req.id == "abc-123"
    end

    test "decodes notification (null id)" do
      json = Jason.encode!(%{"jsonrpc" => "2.0", "method" => "tasks/get", "id" => nil})
      assert {:ok, req} = A2AEx.JSONRPC.decode_request(json)
      assert req.id == nil
    end

    test "rejects malformed JSON" do
      assert {:error, %A2AEx.Error{type: :parse_error}, nil} =
               A2AEx.JSONRPC.decode_request("not json")
    end

    test "rejects wrong jsonrpc version" do
      json = Jason.encode!(%{"jsonrpc" => "1.0", "method" => "test", "id" => 1})
      assert {:error, %A2AEx.Error{type: :invalid_request}, 1} = A2AEx.JSONRPC.decode_request(json)
    end

    test "rejects missing method" do
      json = Jason.encode!(%{"jsonrpc" => "2.0", "id" => 1})
      assert {:error, %A2AEx.Error{type: :invalid_request}, 1} = A2AEx.JSONRPC.decode_request(json)
    end

    test "rejects empty method" do
      json = Jason.encode!(%{"jsonrpc" => "2.0", "method" => "", "id" => 1})
      assert {:error, %A2AEx.Error{type: :invalid_request}, 1} = A2AEx.JSONRPC.decode_request(json)
    end

    test "rejects invalid id type (array)" do
      json = Jason.encode!(%{"jsonrpc" => "2.0", "method" => "test", "id" => [1, 2]})
      assert {:error, %A2AEx.Error{type: :invalid_request}, nil} =
               A2AEx.JSONRPC.decode_request(json)
    end
  end

  describe "encode_response/2" do
    test "encodes successful response" do
      json = A2AEx.JSONRPC.encode_response(%{"task" => "data"}, 1)
      decoded = Jason.decode!(json)
      assert decoded["jsonrpc"] == "2.0"
      assert decoded["id"] == 1
      assert decoded["result"] == %{"task" => "data"}
      refute Map.has_key?(decoded, "error")
    end

    test "response_map/2 returns a map" do
      map = A2AEx.JSONRPC.response_map("ok", "req-1")
      assert map == %{"jsonrpc" => "2.0", "id" => "req-1", "result" => "ok"}
    end
  end

  describe "encode_error/2" do
    test "encodes error response with code" do
      error = A2AEx.Error.new(:task_not_found, "task xyz not found")
      json = A2AEx.JSONRPC.encode_error(error, 42)
      decoded = Jason.decode!(json)

      assert decoded["jsonrpc"] == "2.0"
      assert decoded["id"] == 42
      assert decoded["error"]["code"] == -32_001
      assert decoded["error"]["message"] == "task xyz not found"
      refute Map.has_key?(decoded, "result")
    end

    test "encodes error with details" do
      error = A2AEx.Error.new(:invalid_params, "bad param", %{"field" => "name"})
      json = A2AEx.JSONRPC.encode_error(error, 1)
      decoded = Jason.decode!(json)
      assert decoded["error"]["data"] == %{"field" => "name"}
    end

    test "encodes error from type atom and message" do
      json = A2AEx.JSONRPC.encode_error(:method_not_found, "no such method", 1)
      decoded = Jason.decode!(json)
      assert decoded["error"]["code"] == -32_601
      assert decoded["error"]["message"] == "no such method"
    end
  end

  describe "error codes" do
    test "standard JSON-RPC error codes" do
      assert A2AEx.JSONRPC.error_code(:parse_error) == -32_700
      assert A2AEx.JSONRPC.error_code(:invalid_request) == -32_600
      assert A2AEx.JSONRPC.error_code(:method_not_found) == -32_601
      assert A2AEx.JSONRPC.error_code(:invalid_params) == -32_602
      assert A2AEx.JSONRPC.error_code(:internal_error) == -32_603
    end

    test "A2A-specific error codes" do
      assert A2AEx.JSONRPC.error_code(:task_not_found) == -32_001
      assert A2AEx.JSONRPC.error_code(:task_not_cancelable) == -32_002
      assert A2AEx.JSONRPC.error_code(:push_notification_not_supported) == -32_003
      assert A2AEx.JSONRPC.error_code(:unsupported_operation) == -32_004
      assert A2AEx.JSONRPC.error_code(:unsupported_content_type) == -32_005
      assert A2AEx.JSONRPC.error_code(:invalid_agent_response) == -32_006
      assert A2AEx.JSONRPC.error_code(:extended_card_not_configured) == -32_007
    end

    test "auth error codes" do
      assert A2AEx.JSONRPC.error_code(:unauthenticated) == -31_401
      assert A2AEx.JSONRPC.error_code(:unauthorized) == -31_403
    end

    test "error_type/1 reverse lookup" do
      assert A2AEx.JSONRPC.error_type(-32_700) == :parse_error
      assert A2AEx.JSONRPC.error_type(-32_001) == :task_not_found
      assert A2AEx.JSONRPC.error_type(-31_401) == :unauthenticated
    end

    test "unknown code defaults to internal_error" do
      assert A2AEx.JSONRPC.error_type(-99_999) == :internal_error
    end
  end

  describe "parse_error/1" do
    test "parses error from response map" do
      error_map = %{"code" => -32_001, "message" => "task not found"}
      error = A2AEx.JSONRPC.parse_error(error_map)
      assert error.type == :task_not_found
      assert error.message == "task not found"
    end

    test "parses error with data" do
      error_map = %{
        "code" => -32_602,
        "message" => "invalid params",
        "data" => %{"field" => "id"}
      }

      error = A2AEx.JSONRPC.parse_error(error_map)
      assert error.type == :invalid_params
      assert error.details == %{"field" => "id"}
    end
  end

  describe "to_error_map/2" do
    test "wraps A2AEx.Error" do
      error = A2AEx.Error.new(:task_not_found, "not found")
      map = A2AEx.JSONRPC.to_error_map(error, 1)
      assert map["error"]["code"] == -32_001
    end

    test "wraps error type atom" do
      map = A2AEx.JSONRPC.to_error_map(:method_not_found, 1)
      assert map["error"]["code"] == -32_601
    end

    test "wraps unknown error as internal_error" do
      map = A2AEx.JSONRPC.to_error_map("some string error", 1)
      assert map["error"]["code"] == -32_603
    end
  end

  describe "methods/0" do
    test "returns all 10 A2A methods" do
      methods = A2AEx.JSONRPC.methods()
      assert length(methods) == 10
      assert "message/send" in methods
      assert "message/stream" in methods
      assert "tasks/get" in methods
      assert "tasks/cancel" in methods
      assert "tasks/resubscribe" in methods
      assert "tasks/pushNotificationConfig/set" in methods
      assert "tasks/pushNotificationConfig/get" in methods
      assert "tasks/pushNotificationConfig/list" in methods
      assert "tasks/pushNotificationConfig/delete" in methods
      assert "agent/getAuthenticatedExtendedCard" in methods
    end
  end

  describe "streaming_method?/1" do
    test "message/stream is streaming" do
      assert A2AEx.JSONRPC.streaming_method?("message/stream")
    end

    test "tasks/resubscribe is streaming" do
      assert A2AEx.JSONRPC.streaming_method?("tasks/resubscribe")
    end

    test "message/send is not streaming" do
      refute A2AEx.JSONRPC.streaming_method?("message/send")
    end

    test "tasks/get is not streaming" do
      refute A2AEx.JSONRPC.streaming_method?("tasks/get")
    end
  end
end
