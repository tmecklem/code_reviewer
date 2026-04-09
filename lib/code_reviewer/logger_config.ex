defmodule CodeReviewer.LoggerConfig do
  @moduledoc """
  Manages logging configuration for the code reviewer.
  Provides centralized control over log levels and output formatting.
  """

  require Logger

  @debug_key :code_reviewer_debug

  @doc """
  Configures the logger based on provided options.

  Options:
    - debug: boolean - Enable debug logging (default: false)
  """
  def configure(opts \\ []) do
    debug = Keyword.get(opts, :debug, false)

    # Store debug state in application env
    Application.put_env(:code_reviewer, @debug_key, debug)

    # Set logger level
    level = if debug, do: :debug, else: :info
    Logger.configure(level: level)
  end

  @doc """
  Returns true if debug logging is enabled.
  """
  def debug_enabled? do
    Application.get_env(:code_reviewer, @debug_key, false)
  end

  @doc """
  Logs progress messages at info level.
  These are always shown to the user.

  Options:
    - group: string - Name of the rule group being processed
  """
  def log_progress(context, message, opts \\ []) do
    group = Keyword.get(opts, :group)

    prefix = if group do
      "[#{context} - #{group}]"
    else
      "[#{context}]"
    end

    Logger.info("#{prefix} #{message}")
  end

  @doc """
  Logs debug messages only when debug is enabled.
  These are hidden by default unless --debug flag is set.
  """
  def log_debug(context, message) do
    if debug_enabled?() do
      Logger.debug("[#{context}] #{message}")
    end
  end

  @doc """
  Logs a summary message for a completed action.
  """
  def log_summary(context, message) do
    Logger.info("#{context}: #{message}")
  end
end