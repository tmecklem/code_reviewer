defmodule CodeReviewer.ReviewerTest do
  use ExUnit.Case, async: true

  alias CodeReviewer.Reviewer

  describe "review_pr/2" do
    test "validates repository format" do
      result = Reviewer.review_pr("invalid-repo", 123)

      assert {:error, reason} = result
      assert reason =~ "repository format"
    end

    test "validates PR number" do
      result = Reviewer.review_pr("owner/repo", -1)

      assert {:error, reason} = result
      assert reason =~ "PR number must be positive"
    end
  end

  describe "review_pr/3 with rule groups" do
    test "validates rule groups list" do
      result = Reviewer.review_pr("owner/repo", 123, [])

      assert {:error, reason} = result
      assert reason =~ "At least one rule group"
    end

    test "validates each rule group structure" do
      invalid_groups = [%{name: "Test"}]
      result = Reviewer.review_pr("owner/repo", 123, invalid_groups)

      assert {:error, reason} = result
      assert reason =~ "Invalid rule group"
    end
  end

  describe "perform_review/3" do
    @tag :integration
    test "returns structured review results" do
      rule_groups = [
        %{
          name: "Test Group",
          priority: :high,
          rules: ["test rule"],
          context: "test context"
        }
      ]

      result = Reviewer.review_pr("tmecklem/equipment_tracker", 1, rule_groups)

      assert {:ok, review} = result
      assert is_map(review)
      assert Map.has_key?(review, :pr_info)
      assert Map.has_key?(review, :files)
      assert Map.has_key?(review, :findings)
    end

    @tag :integration
    test "fetches PR data and reviews with LLM" do
      rule_groups = [
        %{
          name: "Testing Strategy",
          priority: :high,
          rules: ["Add tests for new functionality"],
          context: "Focus on testing practices"
        }
      ]

      result = Reviewer.review_pr("tmecklem/equipment_tracker", 1, rule_groups)

      assert {:ok, review} = result
      assert Map.has_key?(review, :pr_info)
      assert Map.has_key?(review, :findings)
      assert is_list(review.findings)
    end
  end
end
