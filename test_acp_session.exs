#!/usr/bin/env elixir

# Test script to reproduce the ACP session timeout issue

Code.require_file("lib/code_reviewer/acp_client.ex")
Code.require_file("lib/code_reviewer/logger_config.ex")

defmodule TestACPSession do
  require Logger

  def test do
    IO.puts("Testing ACP session creation with MCP server...")

    temp_dir = System.tmp_dir!() <> "/test_acp_#{:rand.uniform(10000)}"
    File.mkdir_p!(temp_dir)

    IO.puts("Using temp dir: #{temp_dir}")

    # Custom message handler
    on_message = fn message ->
      case message do
        %{"method" => "session/update", "params" => params} ->
          update = params["update"]
          session_update_type = Map.get(update, "sessionUpdate")
          IO.puts("📨 session/update: #{inspect(session_update_type)}")

          if session_update_type do
            IO.inspect(update, label: "  Update details", limit: 5)
          end

        %{"method" => method} ->
          IO.puts("📨 Notification: #{method}")

        %{"id" => id, "result" => _} ->
          IO.puts("✅ Response for request #{id}")

        %{"id" => id, "error" => error} ->
          IO.puts("❌ Error for request #{id}: #{inspect(error)}")

        _ ->
          IO.puts("📬 Other message: #{inspect(Map.keys(message))}")
      end
    end

    mcp_servers = [
      %{
        "type" => "http",
        "name" => "code-reviewer-mcp",
        "url" => "http://localhost:4567/rpc",
        "headers" => [
          %{"name" => "x-working-dir", "value" => temp_dir}
        ]
      }
    ]

    opts = [
      on_message: on_message,
      working_dir: temp_dir,
      env: [],
      temperature: 0.2,
      mcp_servers: mcp_servers
    ]

    IO.puts("\nCreating persistent session...")
    IO.puts("Temperature: 0.2")
    IO.puts("MCP servers: #{inspect(mcp_servers, pretty: true)}")

    case CodeReviewer.ACPClient.run_persistent_session("Test prompt", opts) do
      {:ok, session} ->
        IO.puts("\n✅ SUCCESS! Session created: #{session.session_id}")

        # Try sending an additional prompt
        IO.puts("\nSending additional prompt...")

        case CodeReviewer.ACPClient.send_additional_prompt(session, "Reply with just 'OK'") do
          {:ok, result} ->
            IO.puts("✅ Got result: #{String.slice(result, 0, 100)}")

          {:error, reason} ->
            IO.puts("❌ Additional prompt failed: #{inspect(reason)}")
        end

        # Clean up
        CodeReviewer.ACPClient.close_session(session)
        IO.puts("\n✅ Session closed")

      {:error, reason} ->
        IO.puts("\n❌ FAILED to create session: #{inspect(reason)}")
        System.halt(1)
    end

    # Clean up temp dir
    File.rm_rf!(temp_dir)
  end
end

TestACPSession.test()
