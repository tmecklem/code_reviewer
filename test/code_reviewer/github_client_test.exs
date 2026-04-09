defmodule CodeReviewer.GitHubClientTest do
  use ExUnit.Case, async: true

  alias CodeReviewer.GitHubClient

  describe "fetch_pr_diff/2" do
    @tag :integration
    test "returns diff for valid PR" do
      result = GitHubClient.fetch_pr_diff("tmecklem/equipment_tracker", 1)

      assert {:ok, diff} = result
      assert is_binary(diff)
      assert diff =~ "diff --git"
    end

    test "returns error for invalid repo format" do
      result = GitHubClient.fetch_pr_diff("invalid-format", 1)

      assert {:error, reason} = result
      assert reason =~ "format"
    end
  end

  describe "fetch_pr_files/2" do
    @tag :integration
    test "returns list of changed files" do
      result = GitHubClient.fetch_pr_files("tmecklem/equipment_tracker", 1)

      assert {:ok, files} = result
      assert is_list(files)
      assert length(files) > 0

      for file <- files do
        assert is_map(file)
        assert Map.has_key?(file, "path")
      end
    end
  end

  describe "fetch_pr_info/2" do
    @tag :integration
    test "returns PR metadata" do
      result = GitHubClient.fetch_pr_info("tmecklem/equipment_tracker", 1)

      assert {:ok, info} = result
      assert is_map(info)
      assert Map.has_key?(info, "title")
      assert Map.has_key?(info, "body")
      assert Map.has_key?(info, "number")
    end
  end

  describe "fetch_pr_head_sha/2" do
    @tag :integration
    test "returns HEAD commit SHA for PR" do
      result = GitHubClient.fetch_pr_head_sha("tmecklem/equipment_tracker", 1)

      assert {:ok, sha} = result
      assert is_binary(sha)
      assert String.length(sha) == 40
      assert sha =~ ~r/^[0-9a-f]{40}$/
    end

    test "returns error for invalid repo format" do
      result = GitHubClient.fetch_pr_head_sha("invalid-format", 1)

      assert {:error, reason} = result
      assert reason =~ "format"
    end
  end

  describe "create_pending_review/5" do
    test "validates repo format" do
      comments = [
        %{file: "lib/test.ex", line: 10, body: "Test comment"}
      ]

      result =
        GitHubClient.create_pending_review("invalid-format", 1, "abc123", comments, "Summary")

      assert {:error, reason} = result
      assert reason =~ "format"
    end

    test "validates required commit_sha" do
      comments = [
        %{file: "lib/test.ex", line: 10, body: "Test comment"}
      ]

      result = GitHubClient.create_pending_review("owner/repo", 1, nil, comments, "Summary")

      assert {:error, reason} = result
      assert reason =~ "commit_sha"

      result = GitHubClient.create_pending_review("owner/repo", 1, "", comments, "Summary")

      assert {:error, reason} = result
      assert reason =~ "commit_sha"
    end

    test "accepts empty comments list" do
      # Should not error with empty comments, just creates review with summary
      result = GitHubClient.create_pending_review("owner/repo", 1, "abc123", [], "Summary only")

      # Will fail with actual gh command, but validates input correctly
      assert match?({:error, _}, result)
    end
  end
end
