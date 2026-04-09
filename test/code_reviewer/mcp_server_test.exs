defmodule CodeReviewer.MCPServerTest do
  use ExUnit.Case, async: true

  alias CodeReviewer.MCPServer

  describe "git_diff tool with chunking" do
    test "returns full diff when no chunk params provided" do
      # Arrange
      working_dir = create_test_dir()
      setup_git_repo(working_dir)

      args = %{"ref1" => "HEAD~1", "ref2" => "HEAD"}

      # Act
      result = MCPServer.call_tool("git_diff", args, working_dir)

      # Assert
      assert %{content: [%{type: "text", text: text}]} = result
      assert text =~ "diff --git"
      refute Map.has_key?(result, :hasMore)
      refute Map.has_key?(result, :offset)
    end

    test "returns chunked diff with limit parameter" do
      # Arrange
      working_dir = create_test_dir()
      setup_git_repo_with_large_diff(working_dir)

      args = %{
        "ref1" => "HEAD~1",
        "ref2" => "HEAD",
        # 500 characters
        "limit" => 500
      }

      # Act
      result = MCPServer.call_tool("git_diff", args, working_dir)

      # Assert
      assert %{content: [%{type: "text", text: text}], hasMore: true, offset: 500} = result
      assert String.length(text) <= 500
    end

    test "returns subsequent chunk with offset parameter" do
      # Arrange
      working_dir = create_test_dir()
      setup_git_repo_with_large_diff(working_dir)

      args = %{
        "ref1" => "HEAD~1",
        "ref2" => "HEAD",
        "offset" => 500,
        "limit" => 500
      }

      # Act
      result = MCPServer.call_tool("git_diff", args, working_dir)

      # Assert
      assert %{content: [%{type: "text", text: text}]} = result
      assert String.length(text) <= 500
    end

    test "returns final chunk with hasMore: false" do
      # Arrange
      working_dir = create_test_dir()
      setup_git_repo_with_large_diff(working_dir)

      # Get the full diff length first
      full_diff = get_full_diff(working_dir, "HEAD~1", "HEAD")
      full_length = String.length(full_diff)

      args = %{
        "ref1" => "HEAD~1",
        "ref2" => "HEAD",
        "offset" => full_length - 100,
        "limit" => 500
      }

      # Act
      result = MCPServer.call_tool("git_diff", args, working_dir)

      # Assert
      assert %{content: [%{type: "text", text: _text}], hasMore: false} = result
    end

    test "returns empty when offset exceeds diff length" do
      # Arrange
      working_dir = create_test_dir()
      setup_git_repo(working_dir)

      args = %{
        "ref1" => "HEAD~1",
        "ref2" => "HEAD",
        "offset" => 100_000,
        "limit" => 500
      }

      # Act
      result = MCPServer.call_tool("git_diff", args, working_dir)

      # Assert
      assert %{content: [%{type: "text", text: ""}], hasMore: false} = result
    end

    test "supports three_dot diff with chunking" do
      # Arrange
      working_dir = create_test_dir()
      setup_git_repo_with_large_diff(working_dir)

      args = %{
        "ref1" => "HEAD~1",
        "ref2" => "HEAD",
        "three_dot" => true,
        "limit" => 500
      }

      # Act
      result = MCPServer.call_tool("git_diff", args, working_dir)

      # Assert
      assert %{content: [%{type: "text", text: text}]} = result
      assert String.length(text) <= 500
    end
  end

  # Helper functions

  defp create_test_dir do
    # Create a unique temp directory in the current project tmp folder
    base_tmp = Path.join([File.cwd!(), "tmp", "test_repos"])
    File.mkdir_p!(base_tmp)

    unique_dir = Path.join(base_tmp, "repo_#{System.unique_integer([:positive])}")
    File.mkdir_p!(unique_dir)
    unique_dir
  end

  defp setup_git_repo(working_dir) do
    # Initialize git repo
    {_, 0} = System.cmd("git", ["init"], cd: working_dir, stderr_to_stdout: true)

    {_, 0} =
      System.cmd("git", ["config", "user.email", "test@test.com"],
        cd: working_dir,
        stderr_to_stdout: true
      )

    {_, 0} =
      System.cmd("git", ["config", "user.name", "Test User"],
        cd: working_dir,
        stderr_to_stdout: true
      )

    {_, 0} =
      System.cmd("git", ["config", "commit.gpgsign", "false"],
        cd: working_dir,
        stderr_to_stdout: true
      )

    # Create initial commit
    File.write!(Path.join(working_dir, "test.txt"), "initial content\n")
    {_, 0} = System.cmd("git", ["add", "."], cd: working_dir, stderr_to_stdout: true)

    {_, 0} =
      System.cmd("git", ["commit", "-m", "Initial commit"],
        cd: working_dir,
        stderr_to_stdout: true
      )

    # Create second commit
    File.write!(Path.join(working_dir, "test.txt"), "modified content\n")
    {_, 0} = System.cmd("git", ["add", "."], cd: working_dir, stderr_to_stdout: true)

    {_, 0} =
      System.cmd("git", ["commit", "-m", "Second commit"],
        cd: working_dir,
        stderr_to_stdout: true
      )
  end

  defp setup_git_repo_with_large_diff(working_dir) do
    # Initialize git repo
    {_, 0} = System.cmd("git", ["init"], cd: working_dir, stderr_to_stdout: true)

    {_, 0} =
      System.cmd("git", ["config", "user.email", "test@test.com"],
        cd: working_dir,
        stderr_to_stdout: true
      )

    {_, 0} =
      System.cmd("git", ["config", "user.name", "Test User"],
        cd: working_dir,
        stderr_to_stdout: true
      )

    {_, 0} =
      System.cmd("git", ["config", "commit.gpgsign", "false"],
        cd: working_dir,
        stderr_to_stdout: true
      )

    # Create initial commit with small file
    File.write!(Path.join(working_dir, "large.txt"), "initial\n")
    {_, 0} = System.cmd("git", ["add", "."], cd: working_dir, stderr_to_stdout: true)

    {_, 0} =
      System.cmd("git", ["commit", "-m", "Initial commit"],
        cd: working_dir,
        stderr_to_stdout: true
      )

    # Create second commit with large changes
    large_content =
      String.duplicate("This is a line of content that will make the diff large\n", 100)

    File.write!(Path.join(working_dir, "large.txt"), large_content)
    {_, 0} = System.cmd("git", ["add", "."], cd: working_dir, stderr_to_stdout: true)

    {_, 0} =
      System.cmd("git", ["commit", "-m", "Large changes"],
        cd: working_dir,
        stderr_to_stdout: true
      )
  end

  defp get_full_diff(working_dir, ref1, ref2) do
    {output, _} =
      System.cmd("git", ["diff", "#{ref1}...#{ref2}"], cd: working_dir, stderr_to_stdout: true)

    output
  end
end
