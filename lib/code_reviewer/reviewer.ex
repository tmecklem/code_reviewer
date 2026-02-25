defmodule CodeReviewer.Reviewer do
  @moduledoc """
  Main orchestrator for code reviews.
  Coordinates GitHub client, LLM client, and rule groups to perform reviews.
  """

  alias CodeReviewer.{ClaudeCodeProvider, GitHubClient, LLMClient, OutputFormatter, RuleGroups}

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
      findings = review_with_rule_groups(rule_groups, diff, pr_info, repo)

      {:ok,
       %{
         pr_info: pr_info,
         files: files,
         findings: findings
       }}
    end
  end

  defp review_with_rule_groups(rule_groups, diff, pr_info, repo) do
    provider = get_llm_provider()

    rule_groups
    |> Enum.map(fn rule_group ->
      case provider.review_code(rule_group, diff, pr_info, repo) do
        {:ok, result} -> Map.get(result, "findings", [])
        {:error, _reason} -> []
      end
    end)
    |> List.flatten()
  end

  defp get_llm_provider do
    case System.get_env("LLM_PROVIDER") do
      "claude_code" -> ClaudeCodeProvider
      _ -> LLMClient
    end
  end
end
