defmodule A2AEx.PushSender do
  @moduledoc """
  Behaviour for sending push notifications about task state changes.
  """

  @doc "Send a push notification with the task state to the configured endpoint."
  @callback send_push(A2AEx.PushConfig.t(), A2AEx.Task.t()) :: :ok | {:error, term()}
end

defmodule A2AEx.PushSender.HTTP do
  @moduledoc """
  HTTP-based push notification sender using Req.

  Sends task state as JSON POST to the push config URL,
  with optional authentication headers.
  """

  @behaviour A2AEx.PushSender

  @impl A2AEx.PushSender
  def send_push(%A2AEx.PushConfig{} = config, %A2AEx.Task{} = task) do
    headers = build_headers(config)

    case Req.post(config.url, json: A2AEx.Task.to_map(task), headers: headers) do
      {:ok, %{status: status}} when status >= 200 and status < 300 -> :ok
      {:ok, %{status: status}} -> {:error, "push endpoint returned #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_headers(config) do
    headers = [{"content-type", "application/json"}]

    headers =
      if config.token && config.token != "" do
        [{"x-a2a-notification-token", config.token} | headers]
      else
        headers
      end

    add_auth_headers(headers, config.authentication)
  end

  defp add_auth_headers(headers, nil), do: headers

  defp add_auth_headers(headers, %A2AEx.PushAuthInfo{} = auth) do
    if auth.credentials && auth.credentials != "" do
      add_scheme_header(headers, auth.schemes, auth.credentials)
    else
      headers
    end
  end

  defp add_scheme_header(headers, schemes, credentials) do
    scheme = Enum.find(schemes || [], &(&1 in ["bearer", "Bearer", "basic", "Basic"]))

    case scheme && String.downcase(scheme) do
      "bearer" -> [{"authorization", "Bearer #{credentials}"} | headers]
      "basic" -> [{"authorization", "Basic #{credentials}"} | headers]
      _ -> headers
    end
  end
end
