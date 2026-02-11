defmodule Mix.Tasks.Review do
  @moduledoc """
  Reviews a GitHub Pull Request using Tim's code review preferences.

  ## Usage

      mix review <repo> <pr_number> [options]

  ## Arguments

    * `repo` - Repository in owner/repo format (e.g., tmecklem/code_reviewer)
    * `pr_number` - Pull request number to review

  ## Options

    * `--post` - Post review comments to GitHub (default: just print)
    * `--groups <groups>` - Comma-separated list of rule groups to use (default: all)

  ## Examples

      # Review PR #123 and print results
      mix review tmecklem/code_reviewer 123

      # Review and post comments to GitHub
      mix review tmecklem/code_reviewer 123 --post

      # Review with specific rule groups
      mix review tmecklem/code_reviewer 123 --groups blocking,testing
  """

  use Mix.Task

  alias CodeReviewer.{Reviewer, GitHubClient, RuleGroups}

  @shortdoc "Reviews a GitHub Pull Request"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    case parse_args(args) do
      {:ok, repo, pr_number, opts} ->
        perform_review(repo, pr_number, opts)

      {:error, message} ->
        Mix.shell().error(message)
        Mix.shell().info("\nUsage: mix review <repo> <pr_number> [--post] [--groups <groups>]")
        Mix.shell().info("Example: mix review tmecklem/code_reviewer 123")
    end
  end

  defp parse_args([repo, pr_str | rest]) do
    case Integer.parse(pr_str) do
      {pr_number, ""} when pr_number > 0 ->
        opts = parse_options(rest)
        {:ok, repo, pr_number, opts}

      _ ->
        {:error, "Invalid PR number: #{pr_str}"}
    end
  end

  defp parse_args(_) do
    {:error, "Missing required arguments: repo and pr_number"}
  end

  defp parse_options(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [post: :boolean, groups: :string],
        aliases: [p: :post, g: :groups]
      )

    opts
  end

  defp perform_review(repo, pr_number, opts) do
    Mix.shell().info("🔍 Reviewing PR ##{pr_number} in #{repo}...")

    rule_groups = get_rule_groups(opts)

    case Reviewer.review_and_format(repo, pr_number, rule_groups) do
      {:ok, formatted} ->
        display_results(formatted)

        if Keyword.get(opts, :post, false) do
          post_review(repo, pr_number, formatted)
        else
          Mix.shell().info("\n💡 Run with --post to publish these comments to GitHub")
        end

      {:error, reason} ->
        Mix.shell().error("❌ Review failed: #{reason}")
    end
  end

  defp get_rule_groups(opts) do
    case Keyword.get(opts, :groups) do
      nil ->
        RuleGroups.all()

      groups_str ->
        groups_str
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.map(&get_group_by_name/1)
        |> Enum.reject(&is_nil/1)
    end
  end

  defp get_group_by_name("blocking"), do: RuleGroups.blocking_issues()
  defp get_group_by_name("testing"), do: RuleGroups.testing_strategy()
  defp get_group_by_name("organization"), do: RuleGroups.code_organization()
  defp get_group_by_name("database"), do: RuleGroups.database_and_performance()
  defp get_group_by_name("api"), do: RuleGroups.api_design()
  defp get_group_by_name("rails"), do: RuleGroups.rails_patterns()
  defp get_group_by_name("elixir"), do: RuleGroups.elixir_patterns()
  defp get_group_by_name("errors"), do: RuleGroups.error_handling()
  defp get_group_by_name("quality"), do: RuleGroups.code_quality()
  defp get_group_by_name(_), do: nil

  defp display_results(formatted) do
    Mix.shell().info("\n#{formatted.summary}")

    unless Enum.empty?(formatted.comments) do
      Mix.shell().info("\n📝 Draft Comments (#{length(formatted.comments)}):")
      Mix.shell().info(String.duplicate("=", 80))

      Enum.each(formatted.comments, fn comment ->
        Mix.shell().info("\n📍 #{comment.file}:#{comment.line}")
        Mix.shell().info(comment.body)
        Mix.shell().info(String.duplicate("-", 80))
      end)
    end
  end

  defp post_review(repo, pr_number, formatted) do
    Mix.shell().info("\n📤 Posting review to GitHub...")

    # Post individual comments
    comment_results =
      Enum.map(formatted.comments, fn comment ->
        GitHubClient.post_review_comment(
          repo,
          pr_number,
          comment.file,
          comment.line,
          comment.body
        )
      end)

    failed_comments = Enum.count(comment_results, fn result -> match?({:error, _}, result) end)

    if failed_comments > 0 do
      Mix.shell().error("⚠️  #{failed_comments} comment(s) failed to post")
    end

    # Submit the review with summary
    case GitHubClient.submit_review(repo, pr_number, formatted.summary, "COMMENT") do
      {:ok, _} ->
        Mix.shell().info("✅ Review posted successfully!")

      {:error, reason} ->
        Mix.shell().error("❌ Failed to submit review: #{reason}")
    end
  end
end
