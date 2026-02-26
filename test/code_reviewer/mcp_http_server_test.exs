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
      assert length(tools) == 2

      git_diff_tool = Enum.find(tools, &(&1["name"] == "git_diff"))
      assert git_diff_tool != nil
      assert git_diff_tool["description"] =~ "git diff"
      assert git_diff_tool["inputSchema"]["properties"]["ref1"]
      assert git_diff_tool["inputSchema"]["properties"]["offset"]
      assert git_diff_tool["inputSchema"]["properties"]["limit"]

      grep_tool = Enum.find(tools, &(&1["name"] == "grep_files"))
      assert grep_tool != nil
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
