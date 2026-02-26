Mix.install([
  {:plug_cowboy, "~> 2.7"},
  {:jason, "~> 1.4"}
])

# Add the lib directory to the code path
Code.append_path("_build/dev/lib/code_reviewer/ebin")

# Start the HTTP server
{:ok, _} = Plug.Cowboy.http(CodeReviewer.MCPHttpServer, [], port: 4567)

IO.puts("MCP HTTP Server started on port 4567")
Process.sleep(:infinity)