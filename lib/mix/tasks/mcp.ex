defmodule Mix.Tasks.Mcp do
  @moduledoc """
  Run the CodeReviewer MCP server.

  Usage:
    mix mcp <working_directory>

  The server reads JSON-RPC requests from stdin and writes responses to stdout.
  """
  @shortdoc "Start the MCP server for code review tools"

  use Mix.Task

  @impl Mix.Task
  def run([working_dir]) do
    # Ensure the application is started for logging
    Application.ensure_all_started(:logger)

    CodeReviewer.MCPServer.start(working_dir)
  end

  def run([]) do
    Mix.shell().error("Usage: mix mcp <working_directory>")
    exit({:shutdown, 1})
  end
end
