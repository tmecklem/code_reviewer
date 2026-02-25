defmodule CodeReviewer.LLMClient do
  @moduledoc """
  Client for interacting with OpenAI API to perform code reviews.
  Uses the OpenAI API with environment variables for configuration.
  """

  require Logger

  @doc """
  Reviews code based on a rule group, diff, and PR information.

  Returns {:ok, response} with findings or {:error, reason}.
  """
  def review_code(rule_group, diff_content, pr_info, _repo \\ nil) do
    with :ok <- validate_rule_group(rule_group),
         :ok <- validate_diff(diff_content),
         {:ok, prompt} <- build_prompt(rule_group, diff_content, pr_info),
         {:ok, response} <- call_openai(prompt) do
      parse_llm_response(response)
    end
  end

  @doc """
  Parses the LLM response JSON into a map.
  """
  def parse_llm_response(response_text) do
    case Jason.decode(response_text) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, error} -> {:error, "Failed to parse LLM response: #{inspect(error)}"}
    end
  end

  # Private functions

  defp validate_rule_group(%{name: _, priority: _, rules: _, context: _}) do
    :ok
  end

  defp validate_rule_group(_) do
    {:error, "Invalid rule group structure. Must have :name, :priority, :rules, and :context"}
  end

  defp validate_diff(""), do: {:error, "Diff content cannot be empty"}
  defp validate_diff(nil), do: {:error, "Diff content cannot be nil"}
  defp validate_diff(_), do: :ok

  defp build_prompt(rule_group, diff_content, pr_info) do
    pr_context = build_pr_context(pr_info)

    prompt = """
    You are Tim's AI code reviewer. You think and review exactly like Tim does.

    ## Review Focus: #{rule_group.name}
    Priority: #{rule_group.priority}

    ## Rules for this review:
    #{Enum.map_join(rule_group.rules, "\n", fn rule -> "- #{rule}" end)}

    ## Review Context:
    #{rule_group.context}

    ## Pull Request Information:
    #{pr_context}

    ## Code Changes:
    ```diff
    #{diff_content}
    ```

    ## Your Task:
    Review the code changes above according to the rules and context provided.
    Return your findings as JSON in this exact format:

    {
      "findings": [
        {
          "severity": "critical|high|medium|low",
          "file": "path/to/file",
          "line": line_number,
          "issue": "Description of the issue",
          "suggestion": "Specific suggestion for fixing it",
          "quote": "Exact code that has the issue"
        }
      ],
      "summary": "Brief summary of findings and overall assessment",
      "praise": "Optional: Specific things done well (if any)"
    }

    Important:
    - Only flag actual issues you find
    - Be specific with file paths and line numbers
    - Quote the exact code when relevant
    - Match Tim's tone: start positive if things look good, be directive about issues
    - If no issues found, return empty findings array with positive summary
    """

    {:ok, prompt}
  end

  defp build_pr_context(pr_info) when is_map(pr_info) do
    """
    Title: #{Map.get(pr_info, "title", "N/A")}
    Author: #{get_in(pr_info, ["author", "login"]) || "N/A"}
    Base Branch: #{Map.get(pr_info, "baseRefName", "N/A")}
    Head Branch: #{Map.get(pr_info, "headRefName", "N/A")}

    Description:
    #{Map.get(pr_info, "body", "No description provided")}
    """
  end

  defp build_pr_context(_), do: "No PR information available"

  defp call_openai(prompt) do
    api_key = System.get_env("OPENAI_API_KEY")

    if api_key do
      headers = [
        {"authorization", "Bearer #{api_key}"},
        {"content-type", "application/json"}
      ]

      body =
        Jason.encode!(%{
          model: System.get_env("OPENAI_MODEL", "gpt-4o"),
          messages: [
            %{
              role: "system",
              content: "You are Tim's AI code reviewer. You review code exactly like Tim does."
            },
            %{
              role: "user",
              content: prompt
            }
          ],
          temperature: 0.3,
          response_format: %{type: "json_object"}
        })

      case Req.post("https://api.openai.com/v1/chat/completions",
             headers: headers,
             body: body
           ) do
        {:ok, %{status: 200, body: response_body}} ->
          content = get_in(response_body, ["choices", Access.at(0), "message", "content"])
          {:ok, content}

        {:ok, %{status: status, body: body}} ->
          {:error, "OpenAI API error (#{status}): #{inspect(body)}"}

        {:error, error} ->
          {:error, "Request failed: #{inspect(error)}"}
      end
    else
      {:error, "OPENAI_API_KEY environment variable not set"}
    end
  end
end
