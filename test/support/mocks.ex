defmodule CodeReviewer.Test.Mocks do
  @moduledoc """
  Defines mocks for external services used in tests.
  """

  import Mox

  # Define behavior for GitHub operations
  defmodule GitHubClientBehaviour do
    @callback fetch_pr_info(String.t(), integer()) :: {:ok, map()} | {:error, String.t()}
    @callback fetch_pr_diff(String.t(), integer()) :: {:ok, String.t()} | {:error, String.t()}
    @callback fetch_pr_files(String.t(), integer()) :: {:ok, list(map())} | {:error, String.t()}
  end

  # Define behavior for ClaudeCode provider
  defmodule ClaudeCodeProviderBehaviour do
    @callback clone_repo(String.t(), map()) :: {:ok, String.t()} | {:error, String.t()}
    @callback review_code(map(), String.t(), map(), String.t(), String.t()) ::
                {:ok, map()} | {:error, String.t()}
  end

  # Define mocks
  defmock(GitHubClientMock, for: GitHubClientBehaviour)
  defmock(ClaudeCodeProviderMock, for: ClaudeCodeProviderBehaviour)
end
