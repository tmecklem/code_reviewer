defmodule CodeReviewer.ResilientGitHubPosterTest do
  @moduledoc """
  Unit tests for resilient GitHub posting functionality.
  """

  use ExUnit.Case, async: true
  alias CodeReviewer.ResilientGitHubPoster

  describe "deduplicate_comments/1" do
    test "removes duplicate comments for same file:line" do
      comments = [
        %{file: "lib/test.ex", line: 10, body: "First comment"},
        %{file: "lib/test.ex", line: 10, body: "Duplicate comment"},
        %{file: "lib/test.ex", line: 20, body: "Different line"},
        %{file: "lib/other.ex", line: 10, body: "Different file"}
      ]

      result = ResilientGitHubPoster.deduplicate_comments(comments)

      assert length(result) == 3
      assert %{file: "lib/test.ex", line: 10, body: "First comment"} in result
      assert %{file: "lib/test.ex", line: 20, body: "Different line"} in result
      assert %{file: "lib/other.ex", line: 10, body: "Different file"} in result
    end

    test "returns empty list for empty input" do
      assert [] == ResilientGitHubPoster.deduplicate_comments([])
    end

    test "preserves single comment" do
      comments = [%{file: "lib/test.ex", line: 10, body: "Single"}]
      assert comments == ResilientGitHubPoster.deduplicate_comments(comments)
    end
  end

  describe "format_failed_comments_for_pr/1" do
    test "formats failed comments correctly" do
      comments = [
        %{file: "lib/test.ex", line: 10, body: "Security issue: SQL injection"},
        %{file: "lib/other.ex", line: 20, body: "Performance: N+1 query"}
      ]

      result = ResilientGitHubPoster.format_failed_comments_for_pr(comments)

      assert result =~ "## Comments that could not be posted inline"
      assert result =~ "lib/test.ex:10"
      assert result =~ "Security issue: SQL injection"
      assert result =~ "lib/other.ex:20"
      assert result =~ "Performance: N+1 query"
    end

    test "handles empty comment list" do
      result = ResilientGitHubPoster.format_failed_comments_for_pr([])

      assert result =~ "## Comments that could not be posted inline"
      refute result =~ "lib/"
    end
  end
end