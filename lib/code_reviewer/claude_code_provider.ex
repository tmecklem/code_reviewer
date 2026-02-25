defmodule CodeReviewer.ClaudeCodeProvider do
  @moduledoc """
  Provider for using Claude Code CLI for code reviews.

  Supports two modes:
  - ACP mode: Uses Agent Client Protocol for streaming visibility (default)
  - Print mode: Uses --print flag for one-shot execution (fallback)

  Set CLAUDE_CODE_MODE=print to use print mode instead of ACP.
  """

  require Logger

  alias CodeReviewer.ACPClient

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
  def review_code(rule_group, _diff_content, pr_info, _repo, temp_dir) when is_binary(temp_dir) do
    with {:ok, claude_path} <- find_claude_code(),
         {:ok, prompt} <- build_review_prompt(rule_group, pr_info),
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
  def review_code(rule_group, _diff_content, pr_info, repo) do
    temp_dir = nil

    try do
      with {:ok, claude_path} <- find_claude_code(),
           {:ok, temp_dir} <- clone_repo_internal(repo, pr_info),
           {:ok, prompt} <- build_review_prompt(rule_group, pr_info),
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
      Logger.debug("Cleaning up existing temp dir: #{temp_dir}")
      File.rm_rf(temp_dir)
    end

    Logger.info("Cloning #{repo} to #{temp_dir}")

    # Clone the repo
    case System.cmd("gh", ["repo", "clone", repo, temp_dir], stderr_to_stdout: true) do
      {_, 0} ->
        # Fetch the PR branches
        case System.cmd("git", ["fetch", "origin", "#{head_branch}:#{head_branch}"],
               cd: temp_dir,
               stderr_to_stdout: true
             ) do
          {_, 0} ->
            Logger.info("Fetched branch #{head_branch}, base is #{base_branch}")
            {:ok, temp_dir}

          {error, _} ->
            cleanup_temp_repo(temp_dir)
            {:error, "Failed to fetch PR branch: #{error}"}
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
      Logger.debug("Cleaning up temp repo: #{temp_dir}")
      File.rm_rf(temp_dir)
    end
  end

  @doc false
  def build_review_prompt(rule_group, pr_info) do
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
    You are currently in a git repository with the PR code checked out.

    1. Run `git diff #{base_branch}...#{head_branch}` to see the changes in this PR
    2. Review the diff according to the rules above
    3. Return your findings as JSON matching the schema provided

    Important:
    - Only flag actual issues you find
    - Be specific with file paths and line numbers from the diff
    - Quote the exact code when relevant
    - Match Tim's tone: start positive if things look good, be directive about issues
    - If no issues found, return empty findings array with positive summary
    """

    {:ok, prompt}
  end

  defp call_claude_code_in_repo(_claude_path, prompt, repo_dir) do
    mode = Application.get_env(:code_reviewer, :claude_code_mode, "acp")

    case mode do
      "acp" -> call_with_acp(prompt, repo_dir)
      "print" -> call_with_print(prompt, repo_dir)
      _ -> call_with_acp(prompt, repo_dir)
    end
  end

  defp call_with_acp(prompt, repo_dir) do
    Logger.info("Using ACP mode for Claude Code (streaming enabled)")

    # Add JSON schema instruction to the prompt
    enhanced_prompt = """
    #{prompt}

    ## Output Format

    You MUST respond with valid JSON matching this exact schema:

    ```json
    #{@json_schema}
    ```

    Return ONLY the JSON object, no markdown code fences, no explanations before or after.
    """

    case ACPClient.run_session(enhanced_prompt,
           working_dir: repo_dir,
           env: [{"ANTHROPIC_API_KEY", get_anthropic_api_key()}]
         ) do
      {:ok, result} ->
        # The result should contain the final response
        extract_json_from_acp_result(result)

      error ->
        error
    end
  end

  defp call_with_print(prompt, repo_dir) do
    Logger.info("Using print mode for Claude Code (no streaming)")

    # Write prompt to temp file
    prompt_file =
      Path.join(System.tmp_dir!(), "claude_prompt_#{:erlang.unique_integer([:positive])}.txt")

    File.write!(prompt_file, prompt)

    # Find claude binary
    {:ok, claude_path} = find_claude_code()

    try do
      bash_cmd =
        "cd #{repo_dir} && cat #{prompt_file} | #{claude_path} --print --output-format json --json-schema '#{@json_schema}' --model claude-sonnet-4-6 --debug --dangerously-skip-permissions"

      Logger.debug("Executing: #{bash_cmd}")

      case System.cmd("bash", ["-c", bash_cmd], stderr_to_stdout: true) do
        {output, 0} ->
          # Check if the response indicates an error
          case Jason.decode(output) do
            {:ok, %{"type" => "result", "subtype" => "error_during_execution"} = result} ->
              Logger.error("Claude Code error_during_execution: #{inspect(result)}")
              {:error, "Claude Code encountered an error during execution: #{inspect(result)}"}

            _ ->
              {:ok, output}
          end

        {error_output, exit_code} ->
          {:error, "Claude Code exited with code #{exit_code}: #{error_output}"}
      end
    after
      File.rm(prompt_file)
    end
  end

  defp get_anthropic_api_key do
    case System.get_env("ANTHROPIC_API_KEY") do
      nil ->
        Logger.warning("ANTHROPIC_API_KEY not set, ACP mode may fail")
        ""

      key ->
        key
    end
  end

  defp extract_json_from_acp_result(result) do
    # The result from ACP session contains the final response
    # We need to extract the JSON from it
    Logger.debug("ACP result: #{inspect(result)}")

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
