#!/usr/bin/env elixir

# Test ACP session WITHOUT MCP server to isolate the issue

Code.require_file("lib/code_reviewer/acp_client.ex")
Code.require_file("lib/code_reviewer/logger_config.ex")

defmodule TestACPNoMCP do
  require Logger

  def test do
    IO.puts("Testing ACP session WITHOUT MCP server...")

    temp_dir = System.tmp_dir!() <> "/test_acp_no_mcp_#{:rand.uniform(10000)}"
    File.mkdir_p!(temp_dir)

    IO.puts("Using temp dir: #{temp_dir}")

    opts = [
      working_dir: temp_dir,
      env: [],
      temperature: 0.2,
      mcp_servers: []  # NO MCP servers
    ]

    IO.puts("\nCreating persistent session WITHOUT MCP...")

    case CodeReviewer.ACPClient.run_persistent_session("Just say 'Hello'", opts) do
      {:ok, session} ->
        IO.puts("\n✅ SUCCESS! Session created: #{session.session_id}")
        CodeReviewer.ACPClient.close_session(session)

      {:error, reason} ->
        IO.puts("\n❌ FAILED: #{inspect(reason)}")
        System.halt(1)
    end

    File.rm_rf!(temp_dir)
  end
end

TestACPNoMCP.test()
