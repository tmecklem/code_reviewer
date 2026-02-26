defmodule CodeReviewer.MCPHttpSupervisor do
  @moduledoc """
  Supervisor for the MCP HTTP server.
  Manages the Plug.Cowboy HTTP server lifecycle.
  """

  use Supervisor
  require Logger

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    port = Application.get_env(:code_reviewer, :mcp_port, 4567)

    children = [
      {Plug.Cowboy, scheme: :http, plug: CodeReviewer.MCPHttpServer, options: [port: port]}
    ]

    Logger.info("Starting MCP HTTP Server on port #{port}")

    Supervisor.init(children, strategy: :one_for_one)
  end
end
