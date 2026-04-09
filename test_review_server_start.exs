#!/usr/bin/env elixir

# Quick test to see if mix review can connect to MCP server
Mix.install([
  {:req, "~> 0.5"}
])

# First check if server is already running
case Req.get("http://localhost:4567/health", connect_options: [timeout: 1000]) do
  {:ok, %{status: 200}} ->
    IO.puts("❌ MCP server is already running, can't test auto-start")
    System.halt(1)
  _ ->
    IO.puts("✅ MCP server is not running, good for testing")
end

IO.puts("\nNow run: MIX_ENV=dev mix review tmecklem/code_reviewer 1 --groups blocking")
IO.puts("It should automatically start the MCP server")