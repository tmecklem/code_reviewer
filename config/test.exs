import Config

# Test environment configuration
# Start the MCP HTTP server in test mode for integration testing
config :code_reviewer,
  start_mcp_server: true,
  mcp_port: 4568  # Use a different port for tests to avoid conflicts