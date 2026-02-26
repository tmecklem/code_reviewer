defmodule CodeReviewer.ClaudeCodeProvider do
  @moduledoc """
  Provider for using Claude Code CLI for code reviews.

  Uses Agent Client Protocol (ACP) for streaming visibility into the review process.
  """

  require Logger

  alias CodeReviewer.{ACPClient, LoggerConfig}

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
  Reviews code using Claude Code CLI in a pre-cloned repository.

  Returns {:ok, response} with findings or {:error, reason}.
  """
  def review_code(rule_group, diff_content, pr_info, _repo, temp_dir) when is_binary(temp_dir) do
    with {:ok, claude_path} <- find_claude_code(),
         {:ok, prompt} <- build_review_prompt(rule_group, pr_info, diff_content),
         {:ok, output} <- call_claude_code_in_repo(claude_path, prompt, temp_dir) do
      parse_claude_response(output)
    else
      {:error, reason} = error ->
        Logger.error("Claude Code review failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Reviews code using Claude Code CLI by cloning the repo and running git diff.
  This version clones the repo for each call - prefer using the version with a pre-cloned temp_dir.

  Returns {:ok, response} with findings or {:error, reason}.
  """
  def review_code(rule_group, diff_content, pr_info, repo) do
    temp_dir = nil

    try do
      with {:ok, claude_path} <- find_claude_code(),
           {:ok, temp_dir} <- clone_repo_internal(repo, pr_info),
           {:ok, prompt} <- build_review_prompt(rule_group, pr_info, diff_content),
           {:ok, output} <- call_claude_code_in_repo(claude_path, prompt, temp_dir) do
        parse_claude_response(output)
      else
        {:error, reason} = error ->
          Logger.error("Claude Code review failed: #{inspect(reason)}")
          error
      end
    after
      cleanup_temp_repo(temp_dir)
    end
  end

  @doc """
  Clones a repository and prepares it for review.
  Returns {:ok, temp_dir} on success.
  """
  def clone_repo(repo, pr_info) do
    clone_repo_internal(repo, pr_info)
  end

  defp clone_repo_internal(repo, pr_info) do
    # Use both unique integer and timestamp to avoid collisions
    temp_dir =
      Path.join(
        System.tmp_dir!(),
        "claude_review_#{:erlang.unique_integer([:positive])}_#{System.system_time(:millisecond)}"
      )

    base_branch = Map.get(pr_info, "baseRefName", "main")
    head_branch = Map.get(pr_info, "headRefName", "HEAD")

    # Clean up if directory exists from a previous failed run
    if File.exists?(temp_dir) do
      LoggerConfig.log_debug("ClaudeCode", "Cleaning up existing temp dir: #{temp_dir}")
      File.rm_rf(temp_dir)
    end

    Logger.info("Cloning #{repo} to #{temp_dir}")

    # Clone the repo
    case System.cmd("gh", ["repo", "clone", repo, temp_dir], stderr_to_stdout: true) do
      {_, 0} ->
        # Fetch and checkout the PR branch
        with {_, 0} <-
               System.cmd("git", ["fetch", "origin", "#{head_branch}:#{head_branch}"],
                 cd: temp_dir,
                 stderr_to_stdout: true
               ),
             {_, 0} <-
               System.cmd("git", ["checkout", head_branch],
                 cd: temp_dir,
                 stderr_to_stdout: true
               ) do
          Logger.info("Checked out branch #{head_branch}, base is #{base_branch}")
          {:ok, temp_dir}
        else
          {error, _} ->
            cleanup_temp_repo(temp_dir)
            {:error, "Failed to fetch/checkout PR branch: #{error}"}
        end

      {error, _} ->
        cleanup_temp_repo(temp_dir)
        {:error, "Failed to clone repo: #{error}"}
    end
  end

  @doc false
  def cleanup_temp_repo(nil), do: :ok

  def cleanup_temp_repo(temp_dir) do
    if File.exists?(temp_dir) do
      LoggerConfig.log_debug("ClaudeCode", "Cleaning up temp repo: #{temp_dir}")
      File.rm_rf(temp_dir)
    end
  end

  @doc false
  def build_review_prompt(rule_group, pr_info, _diff_content) do
    pr_context = build_pr_context(pr_info)
    base_branch = Map.get(pr_info, "baseRefName", "main")
    head_branch = Map.get(pr_info, "headRefName", "HEAD")

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

    ## Your Task:
    You are in a git repository. The PR branch (#{head_branch}) is ALREADY CHECKED OUT.

    ## CRITICAL INSTRUCTIONS:
    - **DO NOT USE BASH or Terminal commands** - These are DISABLED for security
    - **USE ONLY the tools available to you**
    - **NEVER run git commands directly** - Use the git_diff MCP tool instead

    ## Available MCP Tools:
    You have access to git_diff tool via the MCP server:
    1. **git_diff**: (REQUIRED - USE THIS FIRST!)
       - Purpose: Get the diff between branches
       - Usage: Call with arguments: {"ref1": "#{base_branch}", "ref2": "#{head_branch}", "three_dot": true}
       - For large diffs: Add "limit": 5000 to chunk the response
       - Continue with: {"ref1": "#{base_branch}", "ref2": "#{head_branch}", "offset": 5000, "limit": 5000}

    ## Available Built-in Tools:
    - **Read**: Read specific files for context
    - **Grep**: Search for patterns in files (if available)
    - **Glob**: Find files by pattern (if available)

    Terminal/Bash commands are COMPLETELY DISABLED. Any attempt to use them will fail.

    ## Steps (FOLLOW EXACTLY):
    1. **MANDATORY FIRST STEP**: Call the git_diff tool from the MCP server
       - DO NOT use "git diff" command in bash/terminal (it won't work)
       - The tool should be available as: mcp__code-reviewer-mcp__git_diff
    2. If response has hasMore: true, continue fetching chunks:
       - Call again with offset parameter
       - Repeat until hasMore: false
    3. Review all changes according to the rules above
    4. Use Read tool if needed for additional context
    5. Return findings as JSON

    ## FORBIDDEN ACTIONS:
    - ❌ NO bash commands (git, cat, ls, etc.)
    - ❌ NO terminal commands
    - ❌ NO direct command execution
    - ✅ ONLY use the tools available to you

    Important:
    - The git_diff tool is an MCP tool, NOT a bash command
    - Only flag actual issues you find
    - Be specific with file paths and line numbers
    - Quote the exact code when relevant
    - Match Tim's tone: start positive if things look good, be directive about issues
    - If no issues found, return empty findings array with positive summary
    """

    {:ok, prompt}
  end

  defp call_claude_code_in_repo(_claude_path, prompt, repo_dir) do
    Logger.info("Using ACP mode for Claude Code (streaming enabled)")

    # Add JSON schema instruction to the prompt
    enhanced_prompt = """
    #{prompt}

    ## Output Format

    You MUST respond with valid JSON matching this exact schema:

    ```json
    #{@json_schema}
    ```

    CRITICAL: Keep your output concise!
    - Limit "suggestion" fields to 100 characters max
    - Limit "issue" fields to 100 characters max
    - Limit "quote" fields to 50 characters max
    - Include at most 10 findings total
    - Return ONLY the JSON object, no markdown code fences, no explanations before or after
    """

    case ACPClient.run_session(enhanced_prompt, working_dir: repo_dir) do
      {:ok, result} ->
        # Add separator between agent log and review output
        IO.puts("\n\n" <> String.duplicate("=", 80))
        IO.puts("REVIEW RESULTS")
        IO.puts(String.duplicate("=", 80) <> "\n")

        # The result should contain the final response
        extract_json_from_acp_result(result)

      error ->
        error
    end
  end

  defp extract_json_from_acp_result(result) do
    # The result from ACP session contains the final response
    # We need to extract the JSON from it
    LoggerConfig.log_debug("ClaudeCode", "ACP result: #{inspect(result)}")

    case result do
      # If it's already a map with the expected structure
      %{"findings" => _, "summary" => _} = json_result ->
        {:ok, Jason.encode!(json_result)}

      # If it's a string response, try to parse it
      response when is_binary(response) ->
        # Try to extract JSON from markdown code fences or plain text
        json_str =
          response
          |> String.replace(~r/```json\s*/, "")
          |> String.replace(~r/```\s*$/, "")
          |> String.trim()

        case Jason.decode(json_str) do
          {:ok, parsed} ->
            {:ok, Jason.encode!(parsed)}

          {:error, _} ->
            # If parsing failed, try to find JSON in the text
            case Regex.run(~r/(\{[\s\S]*"findings"[\s\S]*\})/, response, capture: :first) do
              [json_match] ->
                case Jason.decode(json_match) do
                  {:ok, parsed} -> {:ok, Jason.encode!(parsed)}
                  error -> {:error, "Failed to parse extracted JSON: #{inspect(error)}"}
                end

              nil ->
                {:error, "Could not find JSON in ACP response: #{response}"}
            end
        end

      # If it's some other structure, try to extract content
      other ->
        {:error, "Unexpected ACP result structure: #{inspect(other)}"}
    end
  end

  @doc false
  def parse_claude_response(output) do
    case Jason.decode(output) do
      {:ok, %{"structured_output" => structured_output} = response} ->
        log_debug_metadata(response)
        {:ok, structured_output}

      {:ok, response} ->
        log_debug_metadata(response)
        {:ok, response}

      {:error, error} ->
        {:error, "Failed to parse Claude output: #{inspect(error)}"}
    end
  end

  @doc false
  def log_debug_metadata(%{
        "duration_ms" => duration_ms,
        "duration_api_ms" => duration_api_ms,
        "num_turns" => num_turns
      }) do
    Logger.info(
      "Claude Code execution: #{duration_ms}ms total, #{duration_api_ms}ms API, #{num_turns} turns"
    )
  end

  def log_debug_metadata(_), do: :ok

  @doc false
  def find_claude_code do
    candidates = [
      Application.get_env(:code_reviewer, :claude_code_path),
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

  @doc false
  def build_pr_context(pr_info) when is_map(pr_info) do
    """
    Title: #{Map.get(pr_info, "title", "N/A")}
    Author: #{get_in(pr_info, ["author", "login"]) || "N/A"}
    Base Branch: #{Map.get(pr_info, "baseRefName", "N/A")}
    Head Branch: #{Map.get(pr_info, "headRefName", "N/A")}

    Description:
    #{Map.get(pr_info, "body", "No description provided")}
    """
  end

  def build_pr_context(_), do: "No PR information available"
end
