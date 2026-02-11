defmodule CodeReviewer.OutputFormatter do
  @moduledoc """
  Formats review results into GitHub-ready comments and summary notes.
  """

  @doc """
  Formats a review result into structured comments and summary.

  Returns {:ok, %{comments: [], summary: ""}}
  """
  def format_review(review_result) do
    comments = format_comments(review_result.findings)
    summary = format_summary(review_result)

    {:ok,
     %{
       comments: comments,
       summary: summary
     }}
  end

  defp format_comments(findings) do
    findings
    |> Enum.map(fn finding ->
      %{
        file: finding["file"],
        line: finding["line"],
        body: format_comment_body(finding)
      }
    end)
  end

  defp format_comment_body(finding) do
    """
    **#{severity_emoji(finding["severity"])} #{String.capitalize(finding["severity"])} Issue**

    #{finding["issue"]}

    **Suggestion:**
    #{finding["suggestion"]}

    #{if finding["quote"], do: "**Code:**\n```\n#{finding["quote"]}\n```", else: ""}
    """
    |> String.trim()
  end

  defp severity_emoji("critical"), do: "🚨"
  defp severity_emoji("high"), do: "⚠️"
  defp severity_emoji("medium"), do: "💡"
  defp severity_emoji("low"), do: "ℹ️"
  defp severity_emoji(_), do: "📝"

  defp format_summary(review_result) do
    findings = review_result.findings
    pr_title = get_in(review_result, [:pr_info, "title"]) || "this PR"

    if Enum.empty?(findings) do
      format_positive_summary(pr_title)
    else
      format_findings_summary(findings, pr_title)
    end
  end

  defp format_positive_summary(pr_title) do
    """
    ## Review Summary

    Nice work on **#{pr_title}**! I didn't find any issues that need addressing.

    The code looks good and follows the expected patterns.
    """
    |> String.trim()
  end

  defp format_findings_summary(findings, pr_title) do
    concerns = categorize_findings(findings)

    """
    ## Review Summary for #{pr_title}

    I've reviewed the changes and have some feedback organized by priority.

    #{format_concerns_section(concerns)}

    #{format_praise_section(findings)}
    """
    |> String.trim()
  end

  defp categorize_findings(findings) do
    findings
    |> Enum.group_by(fn finding -> finding["severity"] end)
    |> Map.new(fn {severity, items} -> {severity, length(items)} end)
  end

  defp format_concerns_section(concerns) do
    sections =
      ["critical", "high", "medium", "low"]
      |> Enum.filter(fn severity -> Map.get(concerns, severity, 0) > 0 end)
      |> Enum.map(fn severity ->
        count = concerns[severity]
        "- **#{String.capitalize(severity)}**: #{count} #{pluralize("issue", count)}"
      end)

    if Enum.empty?(sections) do
      ""
    else
      """
      ### Issues Found

      #{Enum.join(sections, "\n")}
      """
    end
  end

  defp format_praise_section(_findings) do
    # TODO: Extract praise from LLM responses when available
    ""
  end

  defp pluralize(word, 1), do: word
  defp pluralize(word, _), do: "#{word}s"
end
