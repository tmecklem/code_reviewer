defmodule CodeReviewer.ClaudeCodeProvider do
  @moduledoc """
  Provider for using Claude Code CLI for code reviews.

  This module uses Claude Code's --print mode to perform code reviews,
  providing an alternative to direct OpenAI API integration.
  """

  require Logger

  @json_schema """
  {
    "type": "object",
    "properties": {
      "findings": {
        "type": "array",
        "items": {
          "type": "object",
          "properties": {
            "severity": {"type": "string", "enum": ["critical", "high", "medium", "low"]},
            "file": {"type": "string"},
            "line": {"type": "integer"},
            "issue": {"type": "string"},
            "suggestion": {"type": "string"},
            "quote": {"type": "string"}
          },
          "required": ["severity", "file", "line", "issue", "suggestion"]
        }
      },
      "summary": {"type": "string"},
      "praise": {"type": "string"}
    },
    "required": ["findings", "summary"]
  }
  """

  @doc """
  Reviews code using Claude Code CLI.

  Returns {:ok, response} with findings or {:error, reason}.
  """
  def review_code(rule_group, diff_content, pr_info) do
    with {:ok, claude_path} <- find_claude_code(),
         {:ok, prompt} <- build_review_prompt(rule_group, diff_content, pr_info),
         {:ok, result} <- call_claude_code(claude_path, prompt) do
      parse_response(result)
    else
      {:error, reason} = error ->
        Logger.error("Claude Code review failed: #{inspect(reason)}")
        error
    end
  end

  defp find_claude_code do
    candidates = [
      System.get_env("CLAUDE_CODE_PATH"),
      System.find_executable("claude"),
      System.find_executable("claude-code"),
      Path.expand("~/.local/bin/claude"),
      "/usr/local/bin/claude"
    ]

    case Enum.find(candidates, &(&1 && File.exists?(&1))) do
      nil ->
        {:error,
         "Claude Code CLI not found. Install from https://claude.com/product/claude-code or set CLAUDE_CODE_PATH"}

      path ->
        {:ok, path}
    end
  end

  defp call_claude_code(claude_path, prompt) do
    Logger.info("Calling Claude Code for review...")

    # Build command args
    args = [
      "--print",
      prompt,
      "--output-format",
      "json",
      "--json-schema",
      @json_schema,
      "--tools",
      "",
      # Disable tools for safety
      "--dangerously-skip-permissions"
      # Skip permissions since we're just analyzing text
    ]

    Logger.debug("Executing: #{claude_path} #{Enum.join(args, " ")}")

    # Call Claude Code CLI
    case System.cmd(claude_path, args, stderr_to_stdout: true) do
      {output, 0} ->
        Logger.debug("Claude Code output: #{String.slice(output, 0, 500)}...")
        parse_claude_output(output)

      {error_output, exit_code} ->
        {:error, "Claude Code exited with code #{exit_code}: #{error_output}"}
    end
  end

  defp parse_claude_output(output) do
    case Jason.decode(output) do
      {:ok, %{"result" => result}} when is_binary(result) ->
        # Result is JSON string, decode it
        case Jason.decode(result) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, _} -> {:ok, %{"findings" => [], "summary" => result}}
        end

      {:ok, %{"result" => result}} when is_map(result) ->
        # Result is already a map
        {:ok, result}

      {:ok, result} when is_map(result) ->
        # Direct map result
        {:ok, result}

      {:error, error} ->
        {:error, "Failed to parse Claude Code output: #{inspect(error)}"}
    end
  end

  defp build_review_prompt(rule_group, diff_content, pr_info) do
    pr_context = build_pr_context(pr_info)

    prompt = """
    You are Tim's AI code reviewer. You think and review exactly like Tim does.

    ## Review Focus: #{rule_group.name}
    Priority: #{rule_group.priority}

    ## Rules for this review:
    #{Enum.map_join(rule_group.rules, "\n", fn rule -> "- #{rule}" end)}

    ## Review Context:
    #{rule_group.context}

    ## Pull Request Information:
    #{pr_context}

    ## Code Changes:
    ```diff
    #{diff_content}
    ```

    ## Your Task:
    Review the code changes above according to the rules and context provided.
    Return your findings as JSON matching the schema provided.

    Important:
    - Only flag actual issues you find
    - Be specific with file paths and line numbers
    - Quote the exact code when relevant
    - Match Tim's tone: start positive if things look good, be directive about issues
    - If no issues found, return empty findings array with positive summary
    """

    {:ok, prompt}
  end

  defp build_pr_context(pr_info) when is_map(pr_info) do
    """
    Title: #{Map.get(pr_info, "title", "N/A")}
    Author: #{get_in(pr_info, ["author", "login"]) || "N/A"}
    Base Branch: #{Map.get(pr_info, "baseRefName", "N/A")}
    Head Branch: #{Map.get(pr_info, "headRefName", "N/A")}

    Description:
    #{Map.get(pr_info, "body", "No description provided")}
    """
  end

  defp build_pr_context(_), do: "No PR information available"

  defp parse_response({:ok, parsed}) when is_map(parsed) do
    {:ok, parsed}
  end

  defp parse_response({:error, _} = error), do: error
end
