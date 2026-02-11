defmodule CodeReviewer.OutputFormatterTest do
  use ExUnit.Case, async: true

  alias CodeReviewer.OutputFormatter

  describe "format_review/1" do
    test "formats review with findings into comments and summary" do
      review_result = %{
        pr_info: %{
          "title" => "Add new feature",
          "author" => %{"login" => "developer"}
        },
        files: [],
        findings: [
          %{
            "severity" => "high",
            "file" => "lib/app.ex",
            "line" => 42,
            "issue" => "Missing test coverage",
            "suggestion" => "Add tests for this function",
            "quote" => "def process(data) do"
          }
        ]
      }

      result = OutputFormatter.format_review(review_result)

      assert {:ok, formatted} = result
      assert Map.has_key?(formatted, :comments)
      assert Map.has_key?(formatted, :summary)
      assert is_list(formatted.comments)
      assert is_binary(formatted.summary)
    end

    test "separates concerns and praise in summary" do
      review_result = %{
        pr_info: %{"title" => "Test PR"},
        files: [],
        findings: [
          %{
            "severity" => "low",
            "file" => "lib/app.ex",
            "line" => 10,
            "issue" => "Minor style issue",
            "suggestion" => "Fix formatting",
            "quote" => "code"
          }
        ]
      }

      result = OutputFormatter.format_review(review_result)

      assert {:ok, formatted} = result
      assert formatted.summary =~ "Concerns" or formatted.summary =~ "Issues"
    end

    test "formats individual comments with file, line, and suggestion" do
      review_result = %{
        pr_info: %{"title" => "Test"},
        files: [],
        findings: [
          %{
            "severity" => "medium",
            "file" => "lib/test.ex",
            "line" => 15,
            "issue" => "N+1 query detected",
            "suggestion" => "Use eager loading",
            "quote" => "Enum.map(items, fn item -> item.association end)"
          }
        ]
      }

      result = OutputFormatter.format_review(review_result)

      assert {:ok, formatted} = result
      assert [comment] = formatted.comments
      assert comment.file == "lib/test.ex"
      assert comment.line == 15
      assert comment.body =~ "N+1 query detected"
      assert comment.body =~ "Use eager loading"
    end

    test "handles empty findings with positive summary" do
      review_result = %{
        pr_info: %{"title" => "Test"},
        files: [],
        findings: []
      }

      result = OutputFormatter.format_review(review_result)

      assert {:ok, formatted} = result
      assert formatted.comments == []
      assert formatted.summary =~ "looks good" or formatted.summary =~ "no issues"
    end
  end
end
