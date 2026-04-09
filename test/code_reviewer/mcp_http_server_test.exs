defmodule CodeReviewer.MCPHttpServerTest do
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn

  alias CodeReviewer.MCPHttpServer

  describe "POST /rpc - initialize" do
    test "responds to initialize request with capabilities" do
      request = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "initialize",
        "params" => %{}
      }

      conn =
        conn(:post, "/rpc", Jason.encode!(request))
        |> put_req_header("content-type", "application/json")
        |> MCPHttpServer.call([])

      assert conn.status == 200
      assert {"content-type", "application/json; charset=utf-8"} in conn.resp_headers

      response = Jason.decode!(conn.resp_body)
      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1
      assert response["result"]["protocolVersion"] == "2024-11-05"
      assert response["result"]["capabilities"]["tools"] == %{}
      assert response["result"]["serverInfo"]["name"] == "code-reviewer-mcp"
    end
  end

  describe "POST /rpc - tools/list" do
    test "returns list of available tools" do
      request = %{
        "jsonrpc" => "2.0",
        "id" => 2,
        "method" => "tools/list",
        "params" => %{}
      }

      conn =
        conn(:post, "/rpc", Jason.encode!(request))
        |> put_req_header("content-type", "application/json")
        |> MCPHttpServer.call([])

      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 2

      tools = response["result"]["tools"]
      assert is_list(tools)
      assert length(tools) == 5

      git_diff_tool = Enum.find(tools, &(&1["name"] == "git_diff"))
      assert git_diff_tool != nil
      assert git_diff_tool["description"] =~ "git diff"
      assert git_diff_tool["inputSchema"]["properties"]["ref1"]
      assert git_diff_tool["inputSchema"]["properties"]["offset"]
      assert git_diff_tool["inputSchema"]["properties"]["limit"]

      grep_tool = Enum.find(tools, &(&1["name"] == "grep_files"))
      assert grep_tool != nil

      # Check for new feedback tools
      add_feedback_tool = Enum.find(tools, &(&1["name"] == "add_feedback"))
      assert add_feedback_tool != nil
      assert add_feedback_tool["description"] =~ "Add review feedback"

      get_feedback_tool = Enum.find(tools, &(&1["name"] == "get_feedback"))
      assert get_feedback_tool != nil
      assert get_feedback_tool["description"] =~ "Get accumulated feedback"

      clear_feedback_tool = Enum.find(tools, &(&1["name"] == "clear_feedback"))
      assert clear_feedback_tool != nil
      assert clear_feedback_tool["description"] =~ "Clear all accumulated feedback"
    end
  end

  describe "POST /rpc - tools/call - feedback accumulator" do
    setup do
      # Clear any existing feedback before each test
      clear_request = %{
        "jsonrpc" => "2.0",
        "id" => 999,
        "method" => "tools/call",
        "params" => %{
          "name" => "clear_feedback",
          "arguments" => %{}
        }
      }

      conn(:post, "/rpc", Jason.encode!(clear_request))
      |> put_req_header("content-type", "application/json")
      |> MCPHttpServer.call([])

      :ok
    end

    test "add_feedback stores review findings" do
      request = %{
        "jsonrpc" => "2.0",
        "id" => 10,
        "method" => "tools/call",
        "params" => %{
          "name" => "add_feedback",
          "arguments" => %{
            "severity" => "high",
            "file" => "lib/example.ex",
            "line" => 42,
            "issue" => "Potential nil pointer",
            "suggestion" => "Add nil check",
            "quote" => "user.name"
          }
        }
      }

      conn =
        conn(:post, "/rpc", Jason.encode!(request))
        |> put_req_header("content-type", "application/json")
        |> MCPHttpServer.call([])

      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)

      assert response["result"]["content"] == [
               %{"type" => "text", "text" => "Feedback added successfully"}
             ]
    end

    test "add_feedback deduplicates by file and line" do
      # Add first feedback
      request1 = %{
        "jsonrpc" => "2.0",
        "id" => 11,
        "method" => "tools/call",
        "params" => %{
          "name" => "add_feedback",
          "arguments" => %{
            "severity" => "high",
            "file" => "lib/example.ex",
            "line" => 42,
            "issue" => "First issue",
            "suggestion" => "First suggestion"
          }
        }
      }

      conn(:post, "/rpc", Jason.encode!(request1))
      |> put_req_header("content-type", "application/json")
      |> MCPHttpServer.call([])

      # Add duplicate (same file and line)
      request2 = %{
        "jsonrpc" => "2.0",
        "id" => 12,
        "method" => "tools/call",
        "params" => %{
          "name" => "add_feedback",
          "arguments" => %{
            "severity" => "medium",
            "file" => "lib/example.ex",
            "line" => 42,
            "issue" => "Duplicate issue",
            "suggestion" => "Duplicate suggestion"
          }
        }
      }

      conn =
        conn(:post, "/rpc", Jason.encode!(request2))
        |> put_req_header("content-type", "application/json")
        |> MCPHttpServer.call([])

      response = Jason.decode!(conn.resp_body)
      assert response["result"]["content"] == [
               %{"type" => "text", "text" => "Feedback already exists for lib/example.ex:42 (skipped)"}
             ]

      # Get feedback to verify only one entry
      get_request = %{
        "jsonrpc" => "2.0",
        "id" => 13,
        "method" => "tools/call",
        "params" => %{
          "name" => "get_feedback",
          "arguments" => %{}
        }
      }

      conn =
        conn(:post, "/rpc", Jason.encode!(get_request))
        |> put_req_header("content-type", "application/json")
        |> MCPHttpServer.call([])

      response = Jason.decode!(conn.resp_body)
      feedback = Jason.decode!(response["result"]["content"] |> List.first() |> Map.get("text"))
      assert length(feedback["findings"]) == 1
      assert List.first(feedback["findings"])["issue"] == "First issue"
    end

    test "get_feedback returns all accumulated findings" do
      # Add multiple feedback items
      files_and_lines = [
        {"lib/file1.ex", 10, "Issue 1"},
        {"lib/file2.ex", 20, "Issue 2"},
        {"lib/file3.ex", 30, "Issue 3"}
      ]

      for {file, line, issue} <- files_and_lines do
        request = %{
          "jsonrpc" => "2.0",
          "id" => line,
          "method" => "tools/call",
          "params" => %{
            "name" => "add_feedback",
            "arguments" => %{
              "severity" => "medium",
              "file" => file,
              "line" => line,
              "issue" => issue,
              "suggestion" => "Fix #{issue}"
            }
          }
        }

        conn(:post, "/rpc", Jason.encode!(request))
        |> put_req_header("content-type", "application/json")
        |> MCPHttpServer.call([])
      end

      # Get all feedback
      get_request = %{
        "jsonrpc" => "2.0",
        "id" => 100,
        "method" => "tools/call",
        "params" => %{
          "name" => "get_feedback",
          "arguments" => %{}
        }
      }

      conn =
        conn(:post, "/rpc", Jason.encode!(get_request))
        |> put_req_header("content-type", "application/json")
        |> MCPHttpServer.call([])

      response = Jason.decode!(conn.resp_body)
      feedback = Jason.decode!(response["result"]["content"] |> List.first() |> Map.get("text"))

      assert length(feedback["findings"]) == 3
      assert Enum.all?(feedback["findings"], fn f -> f["severity"] == "medium" end)

      issues = Enum.map(feedback["findings"], & &1["issue"])
      assert "Issue 1" in issues
      assert "Issue 2" in issues
      assert "Issue 3" in issues
    end

    test "clear_feedback removes all accumulated findings" do
      # Add some feedback
      add_request = %{
        "jsonrpc" => "2.0",
        "id" => 20,
        "method" => "tools/call",
        "params" => %{
          "name" => "add_feedback",
          "arguments" => %{
            "severity" => "low",
            "file" => "test.ex",
            "line" => 1,
            "issue" => "Test issue",
            "suggestion" => "Test suggestion"
          }
        }
      }

      conn(:post, "/rpc", Jason.encode!(add_request))
      |> put_req_header("content-type", "application/json")
      |> MCPHttpServer.call([])

      # Clear feedback
      clear_request = %{
        "jsonrpc" => "2.0",
        "id" => 21,
        "method" => "tools/call",
        "params" => %{
          "name" => "clear_feedback",
          "arguments" => %{}
        }
      }

      conn =
        conn(:post, "/rpc", Jason.encode!(clear_request))
        |> put_req_header("content-type", "application/json")
        |> MCPHttpServer.call([])

      response = Jason.decode!(conn.resp_body)
      assert response["result"]["content"] == [
               %{"type" => "text", "text" => "Feedback cleared successfully"}
             ]

      # Verify feedback is empty
      get_request = %{
        "jsonrpc" => "2.0",
        "id" => 22,
        "method" => "tools/call",
        "params" => %{
          "name" => "get_feedback",
          "arguments" => %{}
        }
      }

      conn =
        conn(:post, "/rpc", Jason.encode!(get_request))
        |> put_req_header("content-type", "application/json")
        |> MCPHttpServer.call([])

      response = Jason.decode!(conn.resp_body)
      feedback = Jason.decode!(response["result"]["content"] |> List.first() |> Map.get("text"))
      assert feedback["findings"] == []
    end

    test "get_feedback returns empty array when no feedback exists" do
      get_request = %{
        "jsonrpc" => "2.0",
        "id" => 30,
        "method" => "tools/call",
        "params" => %{
          "name" => "get_feedback",
          "arguments" => %{}
        }
      }

      conn =
        conn(:post, "/rpc", Jason.encode!(get_request))
        |> put_req_header("content-type", "application/json")
        |> MCPHttpServer.call([])

      response = Jason.decode!(conn.resp_body)
      feedback = Jason.decode!(response["result"]["content"] |> List.first() |> Map.get("text"))
      assert feedback["findings"] == []
    end

    test "add_feedback validates required fields" do
      # Missing required field
      request = %{
        "jsonrpc" => "2.0",
        "id" => 40,
        "method" => "tools/call",
        "params" => %{
          "name" => "add_feedback",
          "arguments" => %{
            "severity" => "high",
            "file" => "lib/example.ex"
            # Missing line, issue, suggestion
          }
        }
      }

      conn =
        conn(:post, "/rpc", Jason.encode!(request))
        |> put_req_header("content-type", "application/json")
        |> MCPHttpServer.call([])

      response = Jason.decode!(conn.resp_body)
      assert response["result"]["content"] == [
               %{"type" => "text", "text" => "Error: Missing required fields", "isError" => true}
             ]
    end
  end

  describe "POST /rpc - tools/call - git_diff" do
    setup do
      # Create a temporary git repo for testing
      temp_dir = create_test_repo()

      # Start the server with the temp directory
      {:ok, _pid} = MCPHttpServer.start_link(working_dir: temp_dir)

      on_exit(fn ->
        File.rm_rf!(temp_dir)
      end)

      {:ok, working_dir: temp_dir}
    end

    test "returns full diff when no chunking params", %{working_dir: _} do
      request = %{
        "jsonrpc" => "2.0",
        "id" => 3,
        "method" => "tools/call",
        "params" => %{
          "name" => "git_diff",
          "arguments" => %{
            "ref1" => "HEAD~1",
            "ref2" => "HEAD"
          }
        }
      }

      conn =
        conn(:post, "/rpc", Jason.encode!(request))
        |> put_req_header("content-type", "application/json")
        |> MCPHttpServer.call([])

      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 3

      result = response["result"]
      assert [%{"type" => "text", "text" => text}] = result["content"]
      assert text =~ "diff --git"
      refute Map.has_key?(result, "hasMore")
    end

    test "returns chunked diff with limit", %{working_dir: _} do
      request = %{
        "jsonrpc" => "2.0",
        "id" => 4,
        "method" => "tools/call",
        "params" => %{
          "name" => "git_diff",
          "arguments" => %{
            "ref1" => "HEAD~1",
            "ref2" => "HEAD",
            "limit" => 100
          }
        }
      }

      conn =
        conn(:post, "/rpc", Jason.encode!(request))
        |> put_req_header("content-type", "application/json")
        |> MCPHttpServer.call([])

      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)

      result = response["result"]
      assert [%{"type" => "text", "text" => text}] = result["content"]
      assert String.length(text) <= 100
      assert result["hasMore"] == true
      assert result["offset"] == 100
    end

    test "returns next chunk with offset", %{working_dir: _} do
      request = %{
        "jsonrpc" => "2.0",
        "id" => 5,
        "method" => "tools/call",
        "params" => %{
          "name" => "git_diff",
          "arguments" => %{
            "ref1" => "HEAD~1",
            "ref2" => "HEAD",
            "offset" => 100,
            "limit" => 100
          }
        }
      }

      conn =
        conn(:post, "/rpc", Jason.encode!(request))
        |> put_req_header("content-type", "application/json")
        |> MCPHttpServer.call([])

      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)

      result = response["result"]
      assert [%{"type" => "text", "text" => text}] = result["content"]
      assert String.length(text) <= 100
    end
  end

  describe "POST /rpc - error handling" do
    test "returns error for unknown method" do
      request = %{
        "jsonrpc" => "2.0",
        "id" => 99,
        "method" => "unknown/method",
        "params" => %{}
      }

      conn =
        conn(:post, "/rpc", Jason.encode!(request))
        |> put_req_header("content-type", "application/json")
        |> MCPHttpServer.call([])

      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 99
      assert response["error"]["code"] == -32601
      assert response["error"]["message"] =~ "Method not found"
    end

    test "returns error for invalid JSON" do
      # Since we can't easily trigger a parse error through Plug.Test,
      # let's test by sending a valid request with malformed JSON in a string field
      # and verify our error handling works
      # Empty JSON object
      conn =
        conn(:post, "/rpc", Jason.encode!(%{}))
        |> put_req_header("content-type", "application/json")
        |> MCPHttpServer.call([])

      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)

      assert response["jsonrpc"] == "2.0"
      # Invalid request (no method)
      assert response["error"]["code"] == -32600
      assert response["error"]["message"] =~ "Invalid request"
    end

    test "returns error for unknown tool" do
      request = %{
        "jsonrpc" => "2.0",
        "id" => 100,
        "method" => "tools/call",
        "params" => %{
          "name" => "unknown_tool",
          "arguments" => %{}
        }
      }

      conn =
        conn(:post, "/rpc", Jason.encode!(request))
        |> put_req_header("content-type", "application/json")
        |> MCPHttpServer.call([])

      assert conn.status == 200
      response = Jason.decode!(conn.resp_body)

      assert response["error"]["code"] == -32602
      assert response["error"]["message"] =~ "Unknown tool"
    end
  end

  describe "GET /health" do
    test "returns OK" do
      conn = conn(:get, "/health") |> MCPHttpServer.call([])

      assert conn.status == 200
      assert conn.resp_body == "OK"
    end
  end

  # Helper functions

  defp create_test_repo do
    temp_dir = Path.join([System.tmp_dir!(), "mcp_test_#{System.unique_integer([:positive])}"])
    File.mkdir_p!(temp_dir)

    # Initialize git repo
    {_, 0} = System.cmd("git", ["init"], cd: temp_dir, stderr_to_stdout: true)
    {_, 0} = System.cmd("git", ["config", "user.email", "test@test.com"], cd: temp_dir)
    {_, 0} = System.cmd("git", ["config", "user.name", "Test User"], cd: temp_dir)
    {_, 0} = System.cmd("git", ["config", "commit.gpgsign", "false"], cd: temp_dir)

    # Create first commit
    File.write!(Path.join(temp_dir, "test.txt"), "initial content\n")
    {_, 0} = System.cmd("git", ["add", "."], cd: temp_dir, stderr_to_stdout: true)

    {_, 0} =
      System.cmd("git", ["commit", "-m", "Initial commit"], cd: temp_dir, stderr_to_stdout: true)

    # Create second commit
    File.write!(Path.join(temp_dir, "test.txt"), "modified content\n")
    {_, 0} = System.cmd("git", ["add", "."], cd: temp_dir, stderr_to_stdout: true)

    {_, 0} =
      System.cmd("git", ["commit", "-m", "Second commit"], cd: temp_dir, stderr_to_stdout: true)

    temp_dir
  end
end
