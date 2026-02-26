import Config

# Runtime configuration loaded from environment variables

# Claude Code configuration
config :code_reviewer, :claude_code_path, System.get_env("CLAUDE_CODE_PATH")
