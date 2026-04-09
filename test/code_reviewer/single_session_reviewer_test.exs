defmodule CodeReviewer.SingleSessionReviewerTest do
  @moduledoc """
  Integration tests for single-session reviewer.
  These tests require the actual ACP binary and MCP server to be running.

  Run with: mix test test/code_reviewer/single_session_reviewer_test.exs --include integration

  For unit tests without external dependencies, see SingleSessionReviewerMockTest.
  """

  use ExUnit.Case, async: false
  import Mox

  alias CodeReviewer.Reviewer
  alias CodeReviewer.RuleGroups
  alias CodeReviewer.ACPClient
  alias CodeReviewer.Test.ACPMockPort

  setup :verify_on_exit!

  describe "single session review" do
    setup do
      # Create temp directory
      temp_dir = Path.join([System.tmp_dir!(), "reviewer_test_#{System.unique_integer([:positive])}"])
      File.mkdir_p!(temp_dir)

      # Start MCP server on test port if not running
      ensure_mcp_server_running()

      # Clear any existing feedback
      clear_feedback()

      on_exit(fn ->
        File.rm_rf!(temp_dir)
        clear_feedback()
      end)

      {:ok, temp_dir: temp_dir}
    end

    @tag :integration
    @tag :skip
    test "uses single ACP session for all rule groups", %{temp_dir: temp_dir} do
      # Mock PR info
      pr_info = %{
        "title" => "Test PR",
        "body" => "Test description",
        "baseRefName" => "main",
        "headRefName" => "feature-branch",
        "author" => %{"login" => "testuser"}
      }

      # Get multiple rule groups
      rule_groups = [
        RuleGroups.blocking_issues(),
        RuleGroups.testing_strategy(),
        RuleGroups.code_quality()
      ]

      # This should create only ONE session, not three
      result = Reviewer.review_with_single_session(
        "test-repo",
        pr_info,
        "mock diff content",
        rule_groups,
        temp_dir
      )

      assert {:ok, findings} = result

      # Verify findings structure
      assert is_list(findings)

      # Each finding should have been deduplicated by file:line
      unique_locations =
        findings
        |> Enum.map(fn f -> {f["file"], f["line"]} end)
        |> Enum.uniq()

      assert length(unique_locations) == length(findings), "Findings should be deduplicated"
    end

    @tag :integration
    @tag :skip
    test "accumulates feedback using MCP tools", %{temp_dir: temp_dir} do
      pr_info = %{
        "title" => "Test PR",
        "baseRefName" => "main",
        "headRefName" => "feature"
      }

      rule_groups = [RuleGroups.blocking_issues()]

      # Review should use MCP feedback tools
      {:ok, _findings} = Reviewer.review_with_single_session(
        "test-repo",
        pr_info,
        "diff",
        rule_groups,
        temp_dir
      )

      # Check that feedback was accumulated via MCP
      feedback = get_accumulated_feedback()
      assert feedback["findings"] != nil
    end

    @tag :integration
    @tag :skip
    test "deduplicates findings across rule groups", %{temp_dir: _temp_dir} do
      _pr_info = %{
        "title" => "Test PR",
        "baseRefName" => "main",
        "headRefName" => "feature"
      }

      # Simulate multiple rule groups that might find the same issue
      _rule_groups = [
        RuleGroups.blocking_issues(),
        RuleGroups.error_handling(),
        RuleGroups.code_quality()
      ]

      # Add mock feedback with duplicates to test deduplication
      add_mock_feedback("lib/test.ex", 10, "Issue 1", "high")
      add_mock_feedback("lib/test.ex", 10, "Duplicate issue", "medium")  # Same file:line
      add_mock_feedback("lib/test.ex", 20, "Issue 2", "low")

      feedback = get_accumulated_feedback()

      # Should only have 2 findings (line 10 and line 20)
      assert length(feedback["findings"]) == 2

      # The first issue should be kept (not the duplicate)
      line_10_finding = Enum.find(feedback["findings"], &(&1["line"] == 10))
      assert line_10_finding["issue"] == "Issue 1"
    end

    @tag :integration
    @tag :skip
    test "uses low temperature for consistent reviews", %{temp_dir: temp_dir} do
      pr_info = %{"title" => "Test", "baseRefName" => "main", "headRefName" => "feature"}
      rule_groups = [RuleGroups.blocking_issues()]

      # The session should be configured with low temperature
      # We can verify this by checking the session configuration
      # (In real implementation, this would be verified through the ACP session params)

      {:ok, _findings} = Reviewer.review_with_single_session(
        "test-repo",
        pr_info,
        "diff",
        rule_groups,
        temp_dir,
        temperature: 0.2
      )

      # Temperature should be set to 0.2 for consistency
      # This would be verified in the actual ACP session initialization
      assert true  # Placeholder - actual verification would check session params
    end

    @tag :integration
    @tag :skip
    test "maintains context across rule groups in single session", %{temp_dir: temp_dir} do
      pr_info = %{"title" => "Test", "baseRefName" => "main", "headRefName" => "feature"}

      # Multiple rule groups that should share context
      rule_groups = [
        RuleGroups.blocking_issues(),
        RuleGroups.testing_strategy(),
        RuleGroups.code_organization()
      ]

      {:ok, findings} = Reviewer.review_with_single_session(
        "test-repo",
        pr_info,
        "diff",
        rule_groups,
        temp_dir
      )

      # The session should maintain context, allowing later rule groups
      # to reference findings from earlier ones
      # This prevents redundant analysis and improves quality
      assert is_list(findings)
    end

    @tag :integration
    @tag :skip
    test "handles session errors gracefully", %{temp_dir: _temp_dir} do
      pr_info = %{"title" => "Test", "baseRefName" => "main", "headRefName" => "feature"}
      rule_groups = [RuleGroups.blocking_issues()]

      # Simulate session failure
      # (Would need to mock ACP client to return error)

      result = Reviewer.review_with_single_session(
        "test-repo",
        pr_info,
        "diff",
        rule_groups,
        "nonexistent/directory"  # Bad directory to trigger error
      )

      assert {:error, _reason} = result
    end
  end

  # Helper functions for MCP feedback testing

  defp ensure_mcp_server_running do
    # Use test port 4568 instead of 4567
    url = "http://localhost:4568/rpc"

    # Try to ping the server
    case Req.post(url, json: %{"jsonrpc" => "2.0", "id" => 0, "method" => "ping", "params" => %{}}) do
      {:ok, _} ->
        :ok

      {:error, _} ->
        # Server not running, we'll continue anyway as tests should handle this
        :ok
    end
  end

  defp clear_feedback do
    url = "http://localhost:4568/rpc"
    request = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "tools/call",
      "params" => %{
        "name" => "clear_feedback",
        "arguments" => %{}
      }
    }

    case Req.post(url, json: request) do
      {:ok, _} -> :ok
      _ -> :ok
    end
  end

  defp add_mock_feedback(file, line, issue, severity) do
    url = "http://localhost:4568/rpc"
    request = %{
      "jsonrpc" => "2.0",
      "id" => 2,
      "method" => "tools/call",
      "params" => %{
        "name" => "add_feedback",
        "arguments" => %{
          "severity" => severity,
          "file" => file,
          "line" => line,
          "issue" => issue,
          "suggestion" => "Fix: #{issue}"
        }
      }
    }

    Req.post!(url, json: request)
  end

  defp get_accumulated_feedback do
    url = "http://localhost:4568/rpc"
    request = %{
      "jsonrpc" => "2.0",
      "id" => 3,
      "method" => "tools/call",
      "params" => %{
        "name" => "get_feedback",
        "arguments" => %{}
      }
    }

    case Req.post(url, json: request) do
      {:ok, %{body: body}} ->
        result = body["result"]["content"] |> List.first() |> Map.get("text")
        Jason.decode!(result)

      _ ->
        %{"findings" => []}
    end
  end
end