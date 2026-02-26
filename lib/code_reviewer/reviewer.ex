defmodule CodeReviewer.Reviewer do
  @moduledoc """
  Main orchestrator for code reviews.
  Coordinates GitHub client, Claude Code provider, and rule groups to perform reviews.
  """

  require Logger
  alias CodeReviewer.{ClaudeCodeProvider, GitHubClient, OutputFormatter, RuleGroups}

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
      case review_with_rule_groups(rule_groups, diff, pr_info, repo) do
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
    end
  end

  defp review_with_rule_groups(rule_groups, diff, pr_info, repo) do
    alias CodeReviewer.LoggerConfig

    # Clone the repo once and run reviews sequentially
    case ClaudeCodeProvider.clone_repo(repo, pr_info) do
      {:ok, temp_dir} ->
        try do
          LoggerConfig.log_progress("Review", "Running #{length(rule_groups)} rule groups")

          # Run reviews sequentially
          results =
            rule_groups
            |> Enum.with_index(1)
            |> Enum.map(fn {rule_group, index} ->
              LoggerConfig.log_progress(
                "Review",
                "Processing (#{index}/#{length(rule_groups)})",
                group: rule_group.name
              )

              case ClaudeCodeProvider.review_code(rule_group, diff, pr_info, repo, temp_dir) do
                {:ok, result} ->
                  findings = Map.get(result, "findings", [])
                  LoggerConfig.log_summary("✓ #{rule_group.name}", "Found #{length(findings)} issues")
                  {:ok, findings}

                {:error, reason} ->
                  LoggerConfig.log_debug("Review", "Failed: #{inspect(reason)}")
                  LoggerConfig.log_summary("✗ #{rule_group.name}", "Failed")
                  {:error, reason}
              end
            end)

          # Check if all reviews failed
          all_failed? =
            Enum.all?(results, fn
              {:error, _} -> true
              _ -> false
            end)

          if all_failed? do
            {:error, "All reviews failed"}
          else
            # Collect findings from successful reviews
            findings =
              results
              |> Enum.flat_map(fn
                {:ok, findings} -> findings
                {:error, _} -> []
              end)

            {:ok, findings}
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
