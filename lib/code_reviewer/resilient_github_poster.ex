defmodule CodeReviewer.ResilientGitHubPoster do
  @moduledoc """
  Provides resilient posting of review comments to GitHub.

  Attempts to post inline comments individually, and if any fail
  (e.g., with a 422 error for deleted lines), collects them for
  inclusion in the PR-level summary comment.
  """

  require Logger
  alias CodeReviewer.GitHubClient

  @doc """
  Posts a review with resilient handling of failed inline comments.

  Returns a map with:
  - successful_inline_comments: count of successfully posted inline comments
  - failed_inline_comments: count of failed inline comments
  - pr_level_summary: the final PR comment text that was posted
  """
  def post_review_resilient(repo, pr_number, commit_sha, comments, summary) do
    # Deduplicate comments first
    unique_comments = deduplicate_comments(comments)

    # Try to post each comment individually
    {successful, failed} = post_inline_comments(repo, pr_number, commit_sha, unique_comments)

    # Build PR-level summary including any failed comments
    pr_summary = build_pr_summary(summary, failed)

    # Post the PR-level summary
    case GitHubClient.submit_review(repo, pr_number, pr_summary, "COMMENT") do
      {:ok, _} ->
        {:ok, %{
          successful_inline_comments: length(successful),
          failed_inline_comments: length(failed),
          pr_level_summary: pr_summary
        }}

      {:error, reason} ->
        {:error, "Failed to post PR summary: #{reason}"}
    end
  end

  @doc """
  Deduplicates comments by file:line combination.
  Keeps the first comment for each unique location.
  """
  def deduplicate_comments(comments) do
    comments
    |> Enum.uniq_by(fn comment -> {comment.file, comment.line} end)
  end

  # Private functions

  defp post_inline_comments(repo, pr_number, commit_sha, comments) do
    results = Enum.map(comments, fn comment ->
      case post_single_inline_comment(repo, pr_number, commit_sha, comment) do
        {:ok, _} ->
          {:success, comment}
        {:error, reason} ->
          Logger.warning("Failed to post inline comment to #{comment.file}:#{comment.line} - #{reason}")
          {:failure, comment}
      end
    end)

    successful = for {:success, comment} <- results, do: comment
    failed = for {:failure, comment} <- results, do: comment

    {successful, failed}
  end

  defp post_single_inline_comment(repo, pr_number, commit_sha, comment) do
    # Try to post a single inline comment
    # Use with_retries for transient failures
    with_retries(3, fn ->
      GitHubClient.create_pending_review(
        repo,
        pr_number,
        commit_sha,
        [comment],
        ""
      )
    end)
  end

  defp with_retries(0, func) do
    func.()
  end

  defp with_retries(retries_left, func) do
    case func.() do
      {:error, reason} = error ->
        if should_retry?(reason) and retries_left > 0 do
          Logger.debug("Retrying after error: #{reason}")
          Process.sleep(1000)
          with_retries(retries_left - 1, func)
        else
          error
        end

      success ->
        success
    end
  end

  defp should_retry?(reason) when is_binary(reason) do
    # Retry on transient network errors (5xx), not on client errors (4xx)
    String.contains?(reason, ["500", "502", "503", "504", "timeout", "network"])
  end

  defp should_retry?(_), do: false

  defp build_pr_summary(base_summary, []) do
    # No failed comments, just return the base summary
    base_summary
  end

  defp build_pr_summary(base_summary, failed_comments) do
    failed_section = format_failed_comments_for_pr(failed_comments)

    """
    #{base_summary}

    #{failed_section}
    """
  end

  @doc false
  def format_failed_comments_for_pr(comments) do
    """
    ## Comments that could not be posted inline

    The following comments could not be posted as inline comments (possibly due to deleted lines or other issues):

    #{format_failed_comments(comments)}
    """
  end

  defp format_failed_comments(comments) do
    comments
    |> Enum.map(fn comment ->
      """
      ### 📍 **#{comment.file}:#{comment.line}**

      #{comment.body}
      """
    end)
    |> Enum.join("\n---\n")
  end
end