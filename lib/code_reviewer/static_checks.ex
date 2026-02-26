defmodule CodeReviewer.StaticChecks do
  @moduledoc """
  Deterministic static code checks that can be run without LLM calls.

  These checks catch common issues that can be detected with pattern matching:
  - ENV variables outside config boundaries
  - Models/schemas referenced in migrations
  - Controller specs (Rails anti-pattern)
  """

  @type finding :: %{
          severity: String.t(),
          file: String.t(),
          line: integer(),
          issue: String.t(),
          suggestion: String.t(),
          quote: String.t() | nil
        }

  @doc """
  Check for System.get_env or ENV[] usage outside of configuration boundaries.

  Flags:
  - Elixir: System.get_env in lib/ (except config/)
  - Rails: ENV[] in app/ (except config/initializers)
  """
  @spec check_env_in_app_code(String.t()) :: [finding()]
  def check_env_in_app_code(diff) do
    diff
    |> parse_diff()
    |> Enum.flat_map(&check_file_for_env/1)
  end

  @doc """
  Check for model/schema references in migration files.

  Migrations should use raw SQL, not ActiveRecord models or Ecto schemas.
  """
  @spec check_models_in_migrations(String.t()) :: [finding()]
  def check_models_in_migrations(diff) do
    diff
    |> parse_diff()
    |> Enum.filter(&migration_file?/1)
    |> Enum.flat_map(&check_migration_for_models/1)
  end

  @doc """
  Check for Rails controller specs (anti-pattern).

  Should use request specs instead.
  """
  @spec check_controller_specs(String.t()) :: [finding()]
  def check_controller_specs(diff) do
    diff
    |> parse_diff()
    |> Enum.filter(&controller_spec_file?/1)
    |> Enum.map(&controller_spec_finding/1)
  end

  @doc """
  Run all static checks and return aggregated findings.
  """
  @spec run_all(String.t()) :: [finding()]
  def run_all(diff) do
    [
      check_env_in_app_code(diff),
      check_models_in_migrations(diff),
      check_controller_specs(diff)
    ]
    |> List.flatten()
  end

  # Private functions

  defp parse_diff(diff) do
    diff
    |> String.split("\n")
    |> Enum.reduce([], fn line, acc ->
      cond do
        # New file being diffed
        String.starts_with?(line, "diff --git") ->
          [file] = Regex.run(~r{diff --git a/(.*?) b/}, line, capture: :all_but_first)
          [%{file: file, lines: [], current_line: 0} | acc]

        # Line number marker
        String.starts_with?(line, "@@") ->
          case acc do
            [current | rest] ->
              # Extract starting line number from @@ -1,3 +1,4 @@ format
              [line_num] = Regex.run(~r{\+(\d+)}, line, capture: :all_but_first)
              [%{current | current_line: String.to_integer(line_num)} | rest]

            [] ->
              acc
          end

        # Added line
        String.starts_with?(line, "+") and not String.starts_with?(line, "+++") ->
          case acc do
            [current | rest] ->
              line_content = String.slice(line, 1..-1//1)

              [
                %{
                  current
                  | lines: current.lines ++ [{current.current_line, line_content}],
                    current_line: current.current_line + 1
                }
                | rest
              ]

            [] ->
              acc
          end

        # Context line (space prefix)
        String.starts_with?(line, " ") ->
          case acc do
            [current | rest] ->
              [%{current | current_line: current.current_line + 1} | rest]

            [] ->
              acc
          end

        true ->
          acc
      end
    end)
    |> Enum.reverse()
  end

  defp check_file_for_env(%{file: file, lines: lines}) do
    cond do
      # Elixir: allow in config/
      String.starts_with?(file, "config/") ->
        []

      # Elixir: check lib/ for System.get_env
      String.starts_with?(file, "lib/") ->
        Enum.filter(lines, fn {_line_num, content} ->
          String.contains?(content, "System.get_env")
        end)
        |> Enum.map(fn {line_num, content} ->
          %{
            severity: "critical",
            file: file,
            line: line_num,
            issue:
              "ENV variable read in application code (System.get_env). ENV variables should only be read in config/runtime.exs or config/config.exs",
            suggestion:
              "Move System.get_env call to config/runtime.exs and access via Application.get_env/2",
            quote: String.trim(content)
          }
        end)

      # Rails: allow in config/initializers
      String.starts_with?(file, "config/initializers") ->
        []

      # Rails: check app/ for ENV[]
      String.starts_with?(file, "app/") ->
        Enum.filter(lines, fn {_line_num, content} ->
          String.contains?(content, "ENV[")
        end)
        |> Enum.map(fn {line_num, content} ->
          %{
            severity: "critical",
            file: file,
            line: line_num,
            issue:
              "ENV variable read in application code (ENV[]). ENV variables should only be read in config/initializers",
            suggestion:
              "Move ENV[] access to config/initializers and use Rails.configuration instead",
            quote: String.trim(content)
          }
        end)

      true ->
        []
    end
  end

  defp migration_file?(%{file: file}) do
    String.contains?(file, "/migrate/") or String.contains?(file, "/migrations/")
  end

  defp check_migration_for_models(%{file: file, lines: lines}) do
    lines
    |> Enum.filter(fn {_line_num, content} ->
      is_model_reference?(content)
    end)
    |> Enum.map(fn {line_num, content} ->
      %{
        severity: "critical",
        file: file,
        line: line_num,
        issue:
          "ActiveRecord model or Ecto schema reference in migration. Migrations should use raw SQL (execute \"...\") to avoid breaking when models change.",
        suggestion:
          "Replace model/schema usage with raw SQL using execute/1. Models change over time and will break old migrations.",
        quote: String.trim(content)
      }
    end)
  end

  defp is_model_reference?(content) do
    # Look for patterns that suggest model usage
    cond do
      # ActiveRecord patterns: Model.where, Model.find, etc.
      Regex.match?(~r/[A-Z][a-zA-Z]+\.(where|find|update|create|all|first)/, content) ->
        true

      # Ecto patterns: from(...), Repo.all, schema pipes
      Regex.match?(~r/\|>\s*Repo\.(all|one|insert|update|delete)/, content) ->
        true

      # Module-qualified model access: MyApp.Accounts.User
      Regex.match?(~r/[A-Z][a-zA-Z]+\.[A-Z][a-zA-Z]+\.[A-Z][a-zA-Z]+/, content) and
          not Regex.match?(~r/(execute|Repo\.execute)/, content) ->
        true

      true ->
        false
    end
  end

  defp controller_spec_file?(%{file: file}) do
    String.contains?(file, "spec/controllers/") and String.ends_with?(file, "_spec.rb")
  end

  defp controller_spec_finding(%{file: file}) do
    %{
      severity: "high",
      file: file,
      line: 1,
      issue:
        "Controller spec file detected. Controller specs are an anti-pattern in Rails - they test the framework, not your code.",
      suggestion:
        "Replace with request specs in spec/requests/. Request specs test through the full Rails stack and are more valuable.",
      quote: nil
    }
  end
end
