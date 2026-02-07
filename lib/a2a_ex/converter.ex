defmodule A2AEx.Converter do
  @moduledoc """
  Pure functions for converting between ADK and A2A types.

  Handles bidirectional conversion of parts, content/messages, and
  terminal state determination from ADK events.
  """

  alias ADK.Types.{Blob, Content, FunctionCall, FunctionResponse, Part}

  @adk_type "adk_type"
  @adk_thought "adk_thought"
  @function_call "function_call"
  @function_response "function_response"

  # --- ADK Part → A2A Part ---

  @doc "Convert an ADK Part to an A2A Part."
  @spec adk_part_to_a2a(Part.t()) :: {:ok, A2AEx.Part.t()}
  def adk_part_to_a2a(%Part{text: text, thought: true}) when is_binary(text) do
    {:ok, %A2AEx.TextPart{text: text, metadata: %{@adk_thought => true}}}
  end

  def adk_part_to_a2a(%Part{text: text}) when is_binary(text) do
    {:ok, %A2AEx.TextPart{text: text}}
  end

  def adk_part_to_a2a(%Part{inline_data: %Blob{data: data, mime_type: mt}}) do
    {:ok, %A2AEx.FilePart{file: %A2AEx.FileBytes{bytes: Base.encode64(data), mime_type: mt}}}
  end

  def adk_part_to_a2a(%Part{function_call: %FunctionCall{} = fc}) do
    data = %{"name" => fc.name, "id" => fc.id, "args" => fc.args}
    {:ok, %A2AEx.DataPart{data: data, metadata: %{@adk_type => @function_call}}}
  end

  def adk_part_to_a2a(%Part{function_response: %FunctionResponse{} = fr}) do
    data = %{"name" => fr.name, "id" => fr.id, "response" => fr.response}
    {:ok, %A2AEx.DataPart{data: data, metadata: %{@adk_type => @function_response}}}
  end

  @doc "Convert a list of ADK Parts to A2A Parts."
  @spec adk_parts_to_a2a([Part.t()]) :: {:ok, [A2AEx.Part.t()]}
  def adk_parts_to_a2a(parts) when is_list(parts) do
    a2a_parts =
      Enum.map(parts, fn part ->
        {:ok, p} = adk_part_to_a2a(part)
        p
      end)

    {:ok, a2a_parts}
  end

  # --- A2A Part → ADK Part ---

  @doc "Convert an A2A Part to an ADK Part."
  @spec a2a_part_to_adk(A2AEx.Part.t()) :: {:ok, Part.t()}
  def a2a_part_to_adk(%A2AEx.TextPart{text: text, metadata: %{@adk_thought => true}}) do
    {:ok, %Part{text: text, thought: true}}
  end

  def a2a_part_to_adk(%A2AEx.TextPart{text: text}) do
    {:ok, %Part{text: text}}
  end

  def a2a_part_to_adk(%A2AEx.FilePart{file: %A2AEx.FileBytes{bytes: b64, mime_type: mt}}) do
    {:ok, decoded} = Base.decode64(b64)
    {:ok, %Part{inline_data: %Blob{data: decoded, mime_type: mt}}}
  end

  def a2a_part_to_adk(%A2AEx.FilePart{file: %A2AEx.FileURI{uri: uri}}) do
    {:ok, %Part{text: uri}}
  end

  def a2a_part_to_adk(%A2AEx.DataPart{data: data, metadata: %{@adk_type => @function_call}}) do
    fc = %FunctionCall{name: data["name"], id: data["id"], args: data["args"] || %{}}
    {:ok, %Part{function_call: fc}}
  end

  def a2a_part_to_adk(%A2AEx.DataPart{data: data, metadata: %{@adk_type => @function_response}}) do
    fr = %FunctionResponse{name: data["name"], id: data["id"], response: data["response"] || %{}}
    {:ok, %Part{function_response: fr}}
  end

  def a2a_part_to_adk(%A2AEx.DataPart{data: data}) do
    {:ok, %Part{text: Jason.encode!(data)}}
  end

  @doc "Convert a list of A2A Parts to ADK Parts."
  @spec a2a_parts_to_adk([A2AEx.Part.t()]) :: {:ok, [Part.t()]}
  def a2a_parts_to_adk(parts) when is_list(parts) do
    adk_parts =
      Enum.map(parts, fn part ->
        {:ok, p} = a2a_part_to_adk(part)
        p
      end)

    {:ok, adk_parts}
  end

  # --- Message ↔ Content ---

  @doc "Convert an A2A Message to ADK Content."
  @spec a2a_message_to_content(A2AEx.Message.t()) :: {:ok, Content.t()} | {:error, String.t()}
  def a2a_message_to_content(%A2AEx.Message{role: role, parts: parts}) do
    {:ok, adk_parts} = a2a_parts_to_adk(parts)
    adk_role = a2a_role_to_adk(role)
    {:ok, %Content{role: adk_role, parts: adk_parts}}
  end

  @doc "Convert ADK Content to an A2A Message."
  @spec adk_content_to_message(Content.t()) :: A2AEx.Message.t()
  def adk_content_to_message(%Content{} = content) do
    adk_content_to_message(content, [])
  end

  @doc "Convert ADK Content to an A2A Message with context IDs."
  @spec adk_content_to_message(Content.t(), keyword()) :: A2AEx.Message.t()
  def adk_content_to_message(%Content{role: role, parts: parts}, opts) do
    {:ok, a2a_parts} = adk_parts_to_a2a(parts)
    a2a_role = adk_role_to_a2a(role)

    msg = A2AEx.Message.new(a2a_role, a2a_parts)

    msg
    |> maybe_set_context_id(Keyword.get(opts, :context_id))
    |> maybe_set_task_id(Keyword.get(opts, :task_id))
  end

  # --- Terminal state ---

  @doc "Determine the terminal A2A task state from an ADK event."
  @spec terminal_state(ADK.Event.t()) :: A2AEx.TaskState.t()
  def terminal_state(%ADK.Event{} = event) do
    cond do
      is_binary(event.error_code) or is_binary(event.error_message) -> :failed
      event.long_running_tool_ids != [] -> :input_required
      event.actions.escalate -> :input_required
      true -> :completed
    end
  end

  # --- Private helpers ---

  defp a2a_role_to_adk(:user), do: "user"
  defp a2a_role_to_adk(:agent), do: "model"
  defp a2a_role_to_adk(_), do: "user"

  defp adk_role_to_a2a("user"), do: :user
  defp adk_role_to_a2a(_), do: :agent

  defp maybe_set_context_id(msg, nil), do: msg
  defp maybe_set_context_id(msg, id), do: %{msg | context_id: id}

  defp maybe_set_task_id(msg, nil), do: msg
  defp maybe_set_task_id(msg, id), do: %{msg | task_id: id}
end
