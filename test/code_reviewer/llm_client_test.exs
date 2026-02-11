defmodule CodeReviewer.LLMClientTest do
  use ExUnit.Case, async: true

  alias CodeReviewer.LLMClient

  describe "review_code/3" do
    test "validates rule group structure" do
      invalid_group = %{name: "Test"}
      result = LLMClient.review_code(invalid_group, "diff content", %{})

      assert {:error, reason} = result
      assert reason =~ "Invalid rule group"
    end

    test "validates diff content" do
      rule_group = valid_rule_group()
      result = LLMClient.review_code(rule_group, "", %{})

      assert {:error, reason} = result
      assert reason =~ "Diff content cannot be empty"
    end
  end

  describe "parse_llm_response/1" do
    test "parses valid JSON response" do
      response = """
      {
        "findings": [
          {
            "severity": "high",
            "file": "lib/example.ex",
            "line": 10,
            "issue": "Magic number detected",
            "suggestion": "Extract 42 to a named constant"
          }
        ],
        "summary": "Found 1 issue"
      }
      """

      result = LLMClient.parse_llm_response(response)

      assert {:ok, parsed} = result
      assert length(parsed["findings"]) == 1
      assert hd(parsed["findings"])["severity"] == "high"
    end

    test "handles malformed JSON" do
      result = LLMClient.parse_llm_response("not json")

      assert {:error, _reason} = result
    end
  end

  defp valid_rule_group do
    %{
      name: "Test Group",
      priority: :high,
      rules: ["test rule"],
      context: "test context"
    }
  end
end
