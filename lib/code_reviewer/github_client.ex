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
  Creates a pending review with inline comments.

  This creates a DRAFT review that you can view and submit later.
  All comments are added together in one pending review.

  If a pending review already exists, it will be deleted first.
  """
  def create_pending_review(repo, pr_number, commit_sha, comments, body \\ "") do
    with :ok <- validate_repo_format(repo),
         :ok <- validate_required_field(commit_sha, "commit_sha"),
         :ok <- delete_existing_pending_reviews(repo, pr_number) do
      api_path = "repos/#{repo}/pulls/#{pr_number}/reviews"

      # Create pending review with comments
      # Omitting 'event' parameter creates a PENDING review
      payload =
        Jason.encode!(%{
          commit_id: commit_sha,
          body: body,
          comments:
            Enum.map(comments, fn comment ->
              %{
                path: comment.file,
                line: comment.line,
                side: "RIGHT",
                body: comment.body
              }
            end)
        })

      # Use echo to pipe JSON payload to gh api
      cmd = "echo '#{String.replace(payload, "'", "'\\''")}' | gh api #{api_path} --input -"

      case System.cmd("bash", ["-c", cmd], stderr_to_stdout: true) do
        {output, 0} -> {:ok, output}
        {error, code} -> {:error, "Failed to create pending review (exit #{code}): #{error}"}
      end
    end
  end

  @doc """
  Lists all reviews for a PR and returns pending reviews.
  """
  def list_pending_reviews(repo, pr_number) do
    with :ok <- validate_repo_format(repo),
         {:ok, json} <- run_gh(["api", "repos/#{repo}/pulls/#{pr_number}/reviews"]) do
      case Jason.decode(json) do
        {:ok, reviews} when is_list(reviews) ->
          pending = Enum.filter(reviews, fn review -> review["state"] == "PENDING" end)
          {:ok, pending}

        {:error, _} ->
          {:error, "Failed to parse reviews JSON"}
      end
    end
  end

  @doc """
  Deletes a review by ID.
  """
  def delete_review(repo, pr_number, review_id) do
    with :ok <- validate_repo_format(repo) do
      case run_gh([
             "api",
             "-X",
             "DELETE",
             "repos/#{repo}/pulls/#{pr_number}/reviews/#{review_id}"
           ]) do
        {:ok, _} -> :ok
        error -> error
      end
    end
  end

  defp delete_existing_pending_reviews(repo, pr_number) do
    case list_pending_reviews(repo, pr_number) do
      {:ok, []} ->
        :ok

      {:ok, pending_reviews} ->
        require Logger
        Logger.info("Found #{length(pending_reviews)} pending review(s), deleting them first")

        Enum.each(pending_reviews, fn review ->
          case delete_review(repo, pr_number, review["id"]) do
            :ok ->
              Logger.debug("Deleted pending review #{review["id"]}")

            {:error, reason} ->
              Logger.warning("Failed to delete review #{review["id"]}: #{reason}")
          end
        end)

        :ok

      {:error, _reason} ->
        # If we can't list reviews, just try to create anyway
        :ok
    end
  end

  @doc """
  Fetches the HEAD commit SHA for a pull request.
  """
  def fetch_pr_head_sha(repo, pr_number) do
    with :ok <- validate_repo_format(repo),
         {:ok, json} <-
           run_gh([
             "pr",
             "view",
             to_string(pr_number),
             "--repo",
             repo,
             "--json",
             "headRefOid"
           ]) do
      case Jason.decode(json) do
        {:ok, %{"headRefOid" => sha}} -> {:ok, sha}
        {:error, _} -> {:error, "Failed to parse HEAD commit SHA"}
      end
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
  end
end
