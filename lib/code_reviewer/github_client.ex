defmodule CodeReviewer.GitHubClient do
  @moduledoc """
  Client for interacting with GitHub via the `gh` CLI.
  Requires GITHUB_TOKEN to be set in environment.
  """

  @doc """
  Fetches the diff for a pull request.

  ## Examples

      iex> GitHubClient.fetch_pr_diff("owner/repo", 123)
      {:ok, "diff --git a/file.ex b/file.ex..."}

      iex> GitHubClient.fetch_pr_diff("invalid", 123)
      {:error, "Invalid repository format. Expected 'owner/repo'"}
  """
  def fetch_pr_diff(repo, pr_number) do
    with :ok <- validate_repo_format(repo) do
      run_gh(["pr", "diff", to_string(pr_number), "--repo", repo])
    end
  end

  @doc """
  Fetches the list of files changed in a PR.

  Returns a list of maps with file information including filename, status, additions, deletions.
  """
  def fetch_pr_files(repo, pr_number) do
    with :ok <- validate_repo_format(repo),
         {:ok, json} <-
           run_gh([
             "pr",
             "view",
             to_string(pr_number),
             "--repo",
             repo,
             "--json",
             "files"
           ]) do
      case Jason.decode(json) do
        {:ok, %{"files" => files}} -> {:ok, files}
        {:error, _} -> {:error, "Failed to parse files JSON"}
      end
    end
  end

  @doc """
  Fetches PR metadata including title, body, author, etc.
  """
  def fetch_pr_info(repo, pr_number) do
    with :ok <- validate_repo_format(repo),
         {:ok, json} <-
           run_gh([
             "pr",
             "view",
             to_string(pr_number),
             "--repo",
             repo,
             "--json",
             "number,title,body,author,baseRefName,headRefName,state,createdAt,updatedAt"
           ]) do
      case Jason.decode(json) do
        {:ok, info} -> {:ok, info}
        {:error, _} -> {:error, "Failed to parse PR info JSON"}
      end
    end
  end

  @doc """
  Posts a review comment on a specific line of a file in a PR.

  This creates a draft review comment that can be submitted as part of a review.
  """
  def post_review_comment(repo, pr_number, file_path, line_number, comment_body) do
    with :ok <- validate_repo_format(repo),
         :ok <- validate_required_field(file_path, "file_path"),
         :ok <- validate_required_field(comment_body, "comment_body") do
      # Use gh CLI to create review comment
      # Note: This creates a pending review comment
      args = [
        "pr",
        "review",
        to_string(pr_number),
        "--repo",
        repo,
        "--comment",
        "--body",
        comment_body,
        "--file",
        file_path,
        "--line",
        to_string(line_number)
      ]

      run_gh(args)
    end
  end

  @doc """
  Submits a PR review with summary notes.
  """
  def submit_review(repo, pr_number, review_body, event \\ "COMMENT") do
    with :ok <- validate_repo_format(repo),
         :ok <- validate_review_event(event) do
      args = [
        "pr",
        "review",
        to_string(pr_number),
        "--repo",
        repo,
        event_flag(event),
        "--body",
        review_body
      ]

      run_gh(args)
    end
  end

  # Private functions

  defp validate_repo_format(repo) do
    if String.match?(repo, ~r/^[\w\-]+\/[\w\-]+$/) do
      :ok
    else
      {:error, "Invalid repository format. Expected 'owner/repo'"}
    end
  end

  defp validate_required_field(nil, field_name) do
    {:error, "#{field_name} is required"}
  end

  defp validate_required_field("", field_name) do
    {:error, "#{field_name} cannot be empty"}
  end

  defp validate_required_field(_, _), do: :ok

  defp validate_review_event(event) when event in ["APPROVE", "REQUEST_CHANGES", "COMMENT"] do
    :ok
  end

  defp validate_review_event(event) do
    {:error, "Invalid review event: #{event}. Must be APPROVE, REQUEST_CHANGES, or COMMENT"}
  end

  defp event_flag("APPROVE"), do: "--approve"
  defp event_flag("REQUEST_CHANGES"), do: "--request-changes"
  defp event_flag("COMMENT"), do: "--comment"

  defp run_gh(args) do
    case System.cmd("gh", args, stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, output}

      {error_output, exit_code} ->
        {:error, "gh command failed (exit #{exit_code}): #{error_output}"}
    end
  rescue
    e in ErlangError ->
      {:error, "Failed to execute gh command: #{Exception.message(e)}"}
  end
end
