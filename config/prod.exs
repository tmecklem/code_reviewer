import Config

# Production environment configuration
# MCP server is started on demand in production
config :code_reviewer,
  start_mcp_server: false,
  mcp_port: 4567