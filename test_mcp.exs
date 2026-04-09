#!/usr/bin/env elixir

# Test MCP server JSON-RPC communication

# Start the app
Application.ensure_all_started(:code_reviewer)
Process.sleep(2000)

IO.puts("Testing MCP server at http://127.0.0.1:4567/rpc")

# Test JSON-RPC initialize
body = Jason.encode!(%{jsonrpc: "2.0", id: 1, method: "initialize", params: %{}})

case :httpc.request(
  :post,
  {
    ~c"http://127.0.0.1:4567/rpc",
    [],
    ~c"application/json",
    String.to_charlist(body)
  },
  [{:timeout, 5000}],
  []
) do
  {:ok, {{_version, 200, _reason}, _headers, response_body}} ->
    IO.puts("✅ MCP initialize successful")
    IO.puts(to_string(response_body))

  error ->
    IO.puts("❌ MCP initialize failed: #{inspect(error)}")
end
