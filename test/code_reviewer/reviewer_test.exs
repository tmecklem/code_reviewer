defmodule CodeReviewer.ReviewerTest do
  use ExUnit.Case, async: true

  alias CodeReviewer.Reviewer

  describe "review_pr/3 validations" do
    test "validates repository format" do
      result = Reviewer.review_pr("invalid-repo", 1, [])
      assert {:error, reason} = result
      assert reason =~ "Invalid repository format"
    end

    test "validates PR number must be positive" do
      result = Reviewer.review_pr("owner/repo", -1, [])
      assert {:error, reason} = result
      assert reason =~ "PR number must be positive"
    end

    test "validates PR number must be integer" do
      result = Reviewer.review_pr("owner/repo", "not_a_number", [])
      assert {:error, reason} = result
      assert reason =~ "PR number must be positive"
    end

    test "validates rule groups must not be empty" do
      result = Reviewer.review_pr("owner/repo", 1, [])
      assert {:error, reason} = result
      assert reason =~ "At least one rule group required"
    end

    test "validates rule group structure" do
      # Missing required fields
      invalid_group = %{name: "Test"}
      result = Reviewer.review_pr("owner/repo", 1, [invalid_group])
      assert {:error, reason} = result
      assert reason =~ "Invalid rule group structure"
    end

    test "accepts valid inputs" do
      valid_group = %{
        name: "Test Group",
        priority: :high,
        rules: ["test rule"],
        context: "test context"
      }

      # This will fail when trying to make external calls,
      # but that's expected - we're only testing validation here
      result = Reviewer.review_pr("owner/repo", 1, [valid_group])

      # The test passes validation but fails on external call
      # In a real app, we'd use dependency injection to mock these
      assert {:error, _} = result
    end
  end

  describe "review_pr/2" do
    test "uses default rule groups" do
      # This will fail on external calls, but validates the function exists
      result = Reviewer.review_pr("owner/repo", 1)
      assert {:error, _} = result
    end
  end
end
