#!/usr/bin/env elixir

# Test script to verify MCP server integration
Mix.install([
  {:req, "~> 0.5"},
  {:jason, "~> 1.4"}
])

defmodule TestMCP do
  def run do
    port = 4567

    IO.puts("Testing MCP server on port #{port}...")

    # Test 1: Health check
    case Req.get("http://localhost:#{port}/health") do
      {:ok, %{status: 200}} ->
        IO.puts("✅ Health check passed")
      error ->
        IO.puts("❌ Health check failed: #{inspect(error)}")
        System.halt(1)
    end

    # Test 2: Initialize RPC
    init_request = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "initialize",
      "params" => %{
        "protocolVersion" => "2024-11-05",
        "capabilities" => %{},
        "clientInfo" => %{
          "name" => "test-client",
          "version" => "1.0.0"
        }
      }
    }

    case Req.post("http://localhost:#{port}/rpc", json: init_request) do
      {:ok, %{status: 200, body: %{"result" => result}}} ->
        IO.puts("✅ Initialize RPC passed")
        IO.puts("   Server info: #{inspect(result["serverInfo"])}")
      error ->
        IO.puts("❌ Initialize RPC failed: #{inspect(error)}")
        System.halt(1)
    end

    # Test 3: List tools
    list_tools_request = %{
      "jsonrpc" => "2.0",
      "id" => 2,
      "method" => "tools/list",
      "params" => %{}
    }

    case Req.post("http://localhost:#{port}/rpc", json: list_tools_request) do
      {:ok, %{status: 200, body: %{"result" => %{"tools" => tools}}}} ->
        IO.puts("✅ List tools RPC passed")
        IO.puts("   Available tools:")
        Enum.each(tools, fn tool ->
          IO.puts("     - #{tool["name"]}: #{tool["description"]}")
        end)
      error ->
        IO.puts("❌ List tools RPC failed: #{inspect(error)}")
        System.halt(1)
    end

    IO.puts("\n✅ All MCP server tests passed!")
  end
end

TestMCP.run()