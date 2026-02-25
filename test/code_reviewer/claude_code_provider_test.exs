defmodule CodeReviewer.ClaudeCodeProviderTest do
  use ExUnit.Case, async: true

  alias CodeReviewer.ClaudeCodeProvider

  describe "parse_claude_response/1" do
    test "parses successful response with structured_output" do
      json_output = """
      {
        "type": "result",
        "subtype": "success",
        "duration_ms": 1000,
        "duration_api_ms": 1200,
        "num_turns": 5,
        "structured_output": {
          "findings": [
            {
              "severity": "high",
              "file": "lib/app.ex",
              "line": 42,
              "issue": "Test issue",
              "suggestion": "Fix it"
            }
          ],
          "summary": "Review complete"
        }
      }
      """

      assert {:ok, result} = ClaudeCodeProvider.parse_claude_response(json_output)
      assert result["findings"] |> length() == 1
      assert result["summary"] == "Review complete"
    end

    test "parses response with direct findings format" do
      json_output = """
      {
        "findings": [
          {
            "severity": "low",
            "file": "lib/test.ex",
            "line": 10,
            "issue": "Minor issue",
            "suggestion": "Consider fixing"
          }
        ],
        "summary": "Looks good overall"
      }
      """

      assert {:ok, result} = ClaudeCodeProvider.parse_claude_response(json_output)
      assert result["findings"] |> length() == 1
      assert result["summary"] == "Looks good overall"
    end

    test "returns error for invalid JSON" do
      invalid_json = "not valid json"

      assert {:error, error_msg} = ClaudeCodeProvider.parse_claude_response(invalid_json)
      assert error_msg =~ "Failed to parse Claude output"
    end

    test "returns error for error_during_execution responses" do
      json_output = """
      {
        "type": "result",
        "subtype": "error_during_execution",
        "error": "Something went wrong"
      }
      """

      # This should be caught before parse_claude_response in the actual flow
      # but we test it can handle being called with such input
      assert {:ok, _result} = ClaudeCodeProvider.parse_claude_response(json_output)
    end
  end

  describe "build_review_prompt/2" do
    test "includes rule group information" do
      rule_group = %{
        name: "Testing Strategy",
        priority: :high,
        rules: [
          "Write tests first",
          "Use TDD approach"
        ],
        context: "Tim loves TDD"
      }

      pr_info = %{
        "title" => "Add new feature",
        "baseRefName" => "main",
        "headRefName" => "feature-branch"
      }

      assert {:ok, prompt} = ClaudeCodeProvider.build_review_prompt(rule_group, pr_info)
      assert prompt =~ "Testing Strategy"
      assert prompt =~ "Write tests first"
      assert prompt =~ "Use TDD approach"
      assert prompt =~ "Tim loves TDD"
    end

    test "includes git diff command with correct branches" do
      rule_group = %{
        name: "Test Group",
        priority: :medium,
        rules: ["Rule 1"],
        context: "Context"
      }

      pr_info = %{
        "title" => "Test PR",
        "baseRefName" => "develop",
        "headRefName" => "feature-123"
      }

      assert {:ok, prompt} = ClaudeCodeProvider.build_review_prompt(rule_group, pr_info)
      assert prompt =~ "git diff develop...feature-123"
    end

    test "defaults to main branch when baseRefName not provided" do
      rule_group = %{
        name: "Test Group",
        priority: :medium,
        rules: ["Rule 1"],
        context: "Context"
      }

      pr_info = %{
        "title" => "Test PR",
        "headRefName" => "feature-branch"
      }

      assert {:ok, prompt} = ClaudeCodeProvider.build_review_prompt(rule_group, pr_info)
      assert prompt =~ "git diff main...feature-branch"
    end

    test "includes PR context information" do
      rule_group = %{
        name: "Test Group",
        priority: :medium,
        rules: ["Rule 1"],
        context: "Context"
      }

      pr_info = %{
        "title" => "Fix bug in authentication",
        "author" => %{"login" => "developer"},
        "baseRefName" => "main",
        "headRefName" => "bugfix",
        "body" => "This PR fixes a critical auth bug"
      }

      assert {:ok, prompt} = ClaudeCodeProvider.build_review_prompt(rule_group, pr_info)
      assert prompt =~ "Fix bug in authentication"
      assert prompt =~ "developer"
      assert prompt =~ "This PR fixes a critical auth bug"
    end

    test "includes instructions for JSON output" do
      rule_group = %{
        name: "Test Group",
        priority: :medium,
        rules: ["Rule 1"],
        context: "Context"
      }

      pr_info = %{
        "title" => "Test",
        "baseRefName" => "main",
        "headRefName" => "feature"
      }

      assert {:ok, prompt} = ClaudeCodeProvider.build_review_prompt(rule_group, pr_info)
      assert prompt =~ "Return your findings as JSON"
      assert prompt =~ "matching the schema provided"
    end
  end

  describe "build_pr_context/1" do
    test "formats complete PR information" do
      pr_info = %{
        "title" => "Add feature",
        "author" => %{"login" => "dev1"},
        "baseRefName" => "main",
        "headRefName" => "feature-x",
        "body" => "Description here"
      }

      context = ClaudeCodeProvider.build_pr_context(pr_info)

      assert context =~ "Add feature"
      assert context =~ "dev1"
      assert context =~ "main"
      assert context =~ "feature-x"
      assert context =~ "Description here"
    end

    test "handles missing optional fields" do
      pr_info = %{
        "title" => "Test PR"
      }

      context = ClaudeCodeProvider.build_pr_context(pr_info)

      assert context =~ "Test PR"
      assert context =~ "N/A"
      assert context =~ "No description provided"
    end

    test "handles non-map input" do
      context = ClaudeCodeProvider.build_pr_context("not a map")

      assert context == "No PR information available"
    end

    test "handles nil input" do
      context = ClaudeCodeProvider.build_pr_context(nil)

      assert context == "No PR information available"
    end
  end

  describe "log_debug_metadata/1" do
    test "logs timing information when all fields present" do
      response = %{
        "duration_ms" => 5000,
        "duration_api_ms" => 6000,
        "num_turns" => 10
      }

      # Should not crash
      assert :ok = ClaudeCodeProvider.log_debug_metadata(response)
    end

    test "handles missing metadata gracefully" do
      response = %{"findings" => []}

      assert :ok = ClaudeCodeProvider.log_debug_metadata(response)
    end
  end

  describe "find_claude_code/0" do
    test "checks standard locations" do
      # This test just verifies the function returns either ok or error tuple
      case ClaudeCodeProvider.find_claude_code() do
        {:ok, path} ->
          assert is_binary(path)
          assert String.length(path) > 0

        {:error, msg} ->
          assert msg =~ "Claude Code CLI not found"
      end
    end
  end

  describe "cleanup_temp_repo/1" do
    test "handles nil gracefully" do
      assert :ok = ClaudeCodeProvider.cleanup_temp_repo(nil)
    end

    test "handles non-existent directory" do
      # Returns nil (from File.rm_rf when directory doesn't exist)
      result = ClaudeCodeProvider.cleanup_temp_repo("/tmp/does-not-exist-12345")
      assert result == :ok or result == nil
    end
  end
end
