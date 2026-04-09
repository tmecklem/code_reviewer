defmodule CodeReviewer.Reviewer do
  @moduledoc """
  Main orchestrator for code reviews.
  Coordinates GitHub client, Claude Code provider, and rule groups to perform reviews.
  """

  require Logger
  alias CodeReviewer.{ACPClient, ClaudeCodeProvider, GitHubClient, LoggerConfig, OutputFormatter, RuleGroups}

  @doc """
  Reviews a PR using all default rule groups.
  """
  def review_pr(repo, pr_number) do
    review_pr(repo, pr_number, RuleGroups.all())
  end

  @doc """
  Reviews a PR using specified rule groups.
  """
  def review_pr(repo, pr_number, rule_groups) do
    with :ok <- validate_repo(repo),
         :ok <- validate_pr_number(pr_number),
         :ok <- validate_rule_groups(rule_groups) do
      perform_review(repo, pr_number, rule_groups)
    end
  end

  # Private functions

  defp validate_repo(repo) do
    if String.match?(repo, ~r/^[\w\-]+\/[\w\-]+$/) do
      :ok
    else
      {:error, "Invalid repository format. Expected 'owner/repo'"}
    end
  end

  defp validate_pr_number(pr_number) when is_integer(pr_number) and pr_number > 0 do
    :ok
  end

  defp validate_pr_number(_) do
    {:error, "PR number must be positive integer"}
  end

  defp validate_rule_groups([]) do
    {:error, "At least one rule group required"}
  end

  defp validate_rule_groups(groups) when is_list(groups) do
    invalid_group =
      Enum.find(groups, fn group ->
        not is_map(group) or
          not Map.has_key?(group, :name) or
          not Map.has_key?(group, :priority) or
          not Map.has_key?(group, :rules) or
          not Map.has_key?(group, :context)
      end)

    if invalid_group do
      {:error, "Invalid rule group structure"}
    else
      :ok
    end
  end

  defp validate_rule_groups(_) do
    {:error, "Rule groups must be a list"}
  end

  @doc """
  Reviews a PR and returns formatted output ready for posting.
  """
  def review_and_format(repo, pr_number) do
    review_and_format(repo, pr_number, RuleGroups.all())
  end

  def review_and_format(repo, pr_number, rule_groups) do
    with {:ok, review} <- review_pr(repo, pr_number, rule_groups),
         {:ok, formatted} <- OutputFormatter.format_review(review) do
      {:ok, formatted}
    end
  end

  defp perform_review(repo, pr_number, rule_groups) do
    with {:ok, pr_info} <- GitHubClient.fetch_pr_info(repo, pr_number),
         {:ok, diff} <- GitHubClient.fetch_pr_diff(repo, pr_number),
         {:ok, files} <- GitHubClient.fetch_pr_files(repo, pr_number) do

      # Clone the repo once for the review session
      case ClaudeCodeProvider.clone_repo(repo, pr_info) do
        {:ok, temp_dir} ->
          try do
            LoggerConfig.log_progress("Review", "Using single ACP session for all rule groups")

            # Use the single-session approach
            case review_with_single_session(repo, pr_info, diff, rule_groups, temp_dir) do
              {:ok, findings} ->
                {:ok,
                 %{
                   pr_info: pr_info,
                   files: files,
                   findings: findings
                 }}

              {:error, reason} ->
                {:error, reason}
            end
          after
            ClaudeCodeProvider.cleanup_temp_repo(temp_dir)
          end

        {:error, reason} ->
          Logger.error("Failed to clone repo: #{inspect(reason)}")
          {:error, "Failed to clone repo: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Reviews with a single persistent ACP session for all rule groups.
  Uses MCP feedback accumulator for deduplication.

  Options:
    - :temperature - Model temperature (default: 0.2 for consistency)
  """
  def review_with_single_session(_repo, pr_info, _diff, rule_groups, working_dir, opts \\ []) do
    temperature = Keyword.get(opts, :temperature, 0.2)

    # Ensure .claude/settings.json exists in working directory for permission bypass
    ensure_claude_settings(working_dir)

    # Clear any previous feedback
    clear_mcp_feedback()

    # Start a single persistent session
    initial_prompt = build_initial_prompt(pr_info, working_dir)

    # Get MCP port from config or default to 4567
    mcp_port = Application.get_env(:code_reviewer, :mcp_port, 4567)

    session_opts = [
      working_dir: working_dir,
      temperature: temperature,
      mcp_servers: [
        %{
          "type" => "http",
          "name" => "code-reviewer-mcp",
          # Use 127.0.0.1 instead of localhost for better compatibility
          "url" => "http://127.0.0.1:#{mcp_port}/rpc",
          "headers" => [
            %{"name" => "x-working-dir", "value" => working_dir}
          ]
        }
      ]
    ]

    case ACPClient.run_persistent_session(initial_prompt, session_opts) do
      {:ok, session} ->
        try do
          LoggerConfig.log_progress("Review", "Started single ACP session (temperature: #{temperature})")

          # Process each rule group in the same session
          results =
            rule_groups
            |> Enum.with_index(1)
            |> Enum.map(fn {rule_group, index} ->
              LoggerConfig.log_progress(
                "Review",
                "Processing (#{index}/#{length(rule_groups)})",
                group: rule_group.name
              )

              # Build prompt for this specific rule group
              group_prompt = build_rule_group_prompt(rule_group, pr_info)

              # Send prompt to existing session
              case ACPClient.send_additional_prompt(session, group_prompt) do
                {:ok, _result} ->
                  LoggerConfig.log_summary("✓ #{rule_group.name}", "Analysis complete")
                  :ok

                {:error, reason} ->
                  LoggerConfig.log_debug("Review", "Failed: #{inspect(reason)}")
                  LoggerConfig.log_summary("✗ #{rule_group.name}", "Failed")
                  {:error, reason}
              end
            end)

          # Check if all reviews succeeded
          failed = Enum.find(results, &match?({:error, _}, &1))

          if failed do
            {:error, "Some reviews failed"}
          else
            # Get accumulated feedback from MCP
            case get_mcp_feedback() do
              {:ok, feedback} ->
                findings = Map.get(feedback, "findings", [])
                LoggerConfig.log_progress("Review", "Retrieved #{length(findings)} deduplicated findings")
                {:ok, findings}

              {:error, reason} ->
                {:error, "Failed to get feedback: #{reason}"}
            end
          end
        after
          # Always close the session
          ACPClient.close_session(session)
        end

      {:error, reason} ->
        Logger.error("Failed to create ACP session: #{inspect(reason)}")
        {:error, "Failed to create ACP session: #{inspect(reason)}"}
    end
  end

  defp build_initial_prompt(pr_info, working_dir) do
    """
    You are Tim's AI code reviewer. You think and review exactly like Tim does.

    You are currently in the directory: #{working_dir}
    This is a git repository for a pull request review.

    ## Pull Request Information:
    Title: #{Map.get(pr_info, "title", "N/A")}
    Author: #{get_in(pr_info, ["author", "login"]) || "N/A"}
    Base Branch: #{Map.get(pr_info, "baseRefName", "N/A")}
    Head Branch: #{Map.get(pr_info, "headRefName", "N/A")}

    Description:
    #{Map.get(pr_info, "body", "No description provided")}

    ## Important Instructions:
    1. Use the git_diff MCP tool to get the changes (DO NOT use bash commands)
    2. For each issue you find, use the add_feedback MCP tool to record it
    3. The add_feedback tool will automatically deduplicate by file:line
    4. Be specific with file paths and line numbers

    ## Available MCP Tools:
    - git_diff: Get the diff between branches
    - add_feedback: Add a review finding (with automatic deduplication)
    - get_feedback: Get all accumulated feedback
    - clear_feedback: Clear all feedback (already done at start)

    I will now give you specific rule groups to review. Each rule group will have its own focus and rules.
    """
  end

  defp build_rule_group_prompt(rule_group, pr_info) do
    base_branch = Map.get(pr_info, "baseRefName", "main")
    head_branch = Map.get(pr_info, "headRefName", "HEAD")

    """
    ## Now reviewing: #{rule_group.name}
    Priority: #{rule_group.priority}

    ## Rules for this review:
    #{Enum.map_join(rule_group.rules, "\n", fn rule -> "- #{rule}" end)}

    ## Review Context:
    #{rule_group.context}

    ## Your Task:
    1. First, use the git_diff tool to review the changes:
       Call with: {"ref1": "#{base_branch}", "ref2": "#{head_branch}", "three_dot": true}

       Note: Both branches are available locally:
       - #{base_branch} (base branch)
       - #{head_branch} (PR branch - currently checked out)

    2. For each issue found according to the rules above:
       - Use the add_feedback tool with:
         - severity: "critical", "high", "medium", or "low"
         - file: exact file path
         - line: exact line number
         - issue: clear description
         - suggestion: how to fix it
         - quote: relevant code snippet (optional)

    3. Focus ONLY on issues related to this rule group (#{rule_group.name})

    4. Remember: The add_feedback tool will automatically skip duplicates, so don't worry about calling it multiple times for the same file:line

    Start your review now.
    """
  end

  defp clear_mcp_feedback do
    mcp_port = Application.get_env(:code_reviewer, :mcp_port, 4567)
    url = "http://localhost:#{mcp_port}/rpc"
    request = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "tools/call",
      "params" => %{
        "name" => "clear_feedback",
        "arguments" => %{}
      }
    }

    case Req.post(url, json: request) do
      {:ok, _} ->
        LoggerConfig.log_debug("Review", "Cleared previous feedback")
        :ok

      {:error, reason} ->
        LoggerConfig.log_debug("Review", "Failed to clear feedback: #{inspect(reason)}")
        :ok  # Continue anyway
    end
  end

  defp ensure_claude_settings(working_dir) do
    settings_dir = Path.join(working_dir, ".claude")
    File.mkdir_p!(settings_dir)

    settings_file = Path.join(settings_dir, "settings.json")

    settings = %{
      "defaultMode" => "bypassPermissions",
      "permissions" => %{
        "allow" => [
          "mcp__code-reviewer-mcp",
          "mcp__code-reviewer-mcp__*",
          "mcp__code-reviewer-mcp__git_diff",
          "mcp__code-reviewer-mcp__add_feedback",
          "mcp__code-reviewer-mcp__get_feedback",
          "mcp__code-reviewer-mcp__clear_feedback"
        ]
      }
    }

    File.write!(settings_file, Jason.encode!(settings, pretty: true))
    LoggerConfig.log_debug("Review", "Created Claude settings in #{settings_file}")
  end

  defp get_mcp_feedback do
    mcp_port = Application.get_env(:code_reviewer, :mcp_port, 4567)
    url = "http://localhost:#{mcp_port}/rpc"
    request = %{
      "jsonrpc" => "2.0",
      "id" => 2,
      "method" => "tools/call",
      "params" => %{
        "name" => "get_feedback",
        "arguments" => %{}
      }
    }

    case Req.post(url, json: request) do
      {:ok, %{body: body}} ->
        case body do
          %{"result" => %{"content" => [%{"text" => json_text} | _]}} ->
            case Jason.decode(json_text) do
              {:ok, feedback} -> {:ok, feedback}
              error -> error
            end

          _ ->
            {:error, "Unexpected response format"}
        end

      error ->
        error
    end
  end

end
