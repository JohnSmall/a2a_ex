defmodule A2AEx do
  @moduledoc """
  Elixir implementation of the Agent-to-Agent (A2A) protocol.

  A2AEx provides a server and client for the A2A protocol, enabling
  interoperability between AI agents over HTTP using JSON-RPC.

  Built on top of the ADK (Agent Development Kit) framework, A2AEx can
  expose any ADK agent as an A2A-compatible endpoint and consume remote
  A2A agents as if they were local ADK agents.

  ## Key Modules

  - `A2AEx.Server` - Plug-based A2A server endpoint
  - `A2AEx.Client` - HTTP client for remote A2A agents
  - `A2AEx.AgentCard` - Agent card builder and parser
  - `A2AEx.Converter` - ADK Event <-> A2A Message conversion
  - `A2AEx.RemoteAgent` - ADK agent backed by a remote A2A server
  """
end
