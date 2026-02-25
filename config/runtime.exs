import Config

# Runtime configuration loaded from environment variables

# LLM provider selection (defaults to OpenAI client)
config :code_reviewer, :llm_provider, System.get_env("LLM_PROVIDER", "openai")

# OpenAI API configuration
config :code_reviewer, :openai,
  api_key: System.get_env("OPENAI_API_KEY"),
  model: System.get_env("OPENAI_MODEL", "gpt-4o")

# Claude Code CLI path
config :code_reviewer, :claude_code_path, System.get_env("CLAUDE_CODE_PATH")
