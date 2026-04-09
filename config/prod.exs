import Config

# Production environment configuration
# MCP server is started automatically in production
config :code_reviewer,
  start_mcp_server: true,
  mcp_port: 4567