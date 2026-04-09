defmodule Mix.Tasks.McpHttp do
  @moduledoc """
  Start the CodeReviewer HTTP MCP server.

  Usage:
    mix mcp_http [--port PORT]

  The server provides an HTTP endpoint at http://localhost:4567/rpc (default)
  for MCP JSON-RPC requests.
  """
  @shortdoc "Start the HTTP MCP server for code review tools"

  use Mix.Task
  require Logger

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [port: :integer])
    port = Keyword.get(opts, :port, 4567)

    # Ensure the application is started
    Application.ensure_all_started(:plug)
    Application.ensure_all_started(:plug_cowboy)
    Application.ensure_all_started(:logger)

    # Start the HTTP server
    case Plug.Cowboy.http(CodeReviewer.MCPHttpServer, [], port: port) do
      {:ok, _} ->
        Logger.info("MCP HTTP Server started on port #{port}")
        Logger.info("Endpoint: http://localhost:#{port}/rpc")
        Logger.info("Press Ctrl+C to stop")

        # Keep the process alive
        Process.sleep(:infinity)

      {:error, reason} ->
        Logger.error("Failed to start MCP HTTP Server: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end
end
