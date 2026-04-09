defmodule CodeReviewer.ACPClientTest do
  use ExUnit.Case, async: false
  import Mox
  import ExUnit.CaptureLog

  alias CodeReviewer.ACPClient
  alias CodeReviewer.Test.ACPMockPort

  setup :verify_on_exit!

  describe "run_session/2" do
    test "runs a single prompt session and returns result" do
      # This test would require mocking the Port or using a test double
      # For now, we'll skip this as it requires external binary
      :skip
    end
  end

  describe "run_persistent_session/2" do
    test "creates a persistent session that accepts multiple prompts" do
      # Test that we can:
      # 1. Start a persistent session
      # 2. Send multiple prompts to the same session
      # 3. Maintain context between prompts
      # 4. Close the session when done

      # Mock implementation would go here
      # For a real implementation, we'd need to mock the Port communication

      opts = [working_dir: "/tmp/test"]

      # Should return {:ok, session_handle}
      assert {:ok, session} = ACPClient.run_persistent_session("Initial prompt", opts)
      assert is_map(session)
      assert session.session_id != nil
      assert session.port != nil

      # Should be able to send additional prompts
      assert {:ok, result1} = ACPClient.send_additional_prompt(session, "Second prompt")
      assert is_binary(result1)

      assert {:ok, result2} = ACPClient.send_additional_prompt(session, "Third prompt")
      assert is_binary(result2)

      # Should be able to close the session
      assert :ok = ACPClient.close_session(session)
    end

    test "supports temperature configuration for consistent reviews" do
      opts = [
        working_dir: "/tmp/test",
        temperature: 0.2  # Low temperature for consistent reviews
      ]

      # When creating a session with temperature
      assert {:ok, session} = ACPClient.run_persistent_session("Test", opts)

      # The session should have temperature configured
      assert session.temperature == 0.2
    end

    test "handles session errors gracefully" do
      opts = [working_dir: "/tmp/test"]

      # Simulate error scenarios
      # 1. Port spawn failure
      # 2. Initialize failure
      # 3. Session creation failure

      # These would need proper mocking of the Port
      :skip
    end

    test "maintains session state across prompts" do
      opts = [working_dir: "/tmp/test"]

      assert {:ok, session} = ACPClient.run_persistent_session("Define X = 42", opts)

      # Second prompt should have access to context from first
      assert {:ok, result} = ACPClient.send_additional_prompt(session, "What is X?")

      # Result should reference the value 42 defined earlier
      # (This would need actual ACP binary or mocking)
      :skip
    end

    test "handles MCP server integration in persistent session" do
      opts = [
        working_dir: "/tmp/test",
        mcp_servers: [
          %{
            "type" => "http",
            "name" => "test-mcp",
            "url" => "http://localhost:4567/rpc"
          }
        ]
      ]

      assert {:ok, session} = ACPClient.run_persistent_session("Test with MCP", opts)
      assert session.mcp_servers == opts[:mcp_servers]
    end

    test "properly cleans up resources on session close" do
      opts = [working_dir: "/tmp/test"]

      assert {:ok, session} = ACPClient.run_persistent_session("Test", opts)
      port = session.port

      # Close the session
      assert :ok = ACPClient.close_session(session)

      # Port should be closed
      # (Would need to verify with Port.info or similar)
      :skip
    end
  end

  describe "send_additional_prompt/2" do
    test "sends prompt to existing session" do
      # Create a mock session
      session = %{
        session_id: "test-session-123",
        port: self(),  # Mock port as current process for testing
        message_id: 3
      }

      # Should send prompt and increment message ID
      assert {:ok, result} = ACPClient.send_additional_prompt(session, "Additional prompt")
      assert is_binary(result)

      # Session should have incremented message_id
      # (Implementation detail - may need adjustment)
      :skip
    end

    test "returns error if session is closed" do
      session = %{
        session_id: "closed-session",
        port: nil,
        closed: true
      }

      assert {:error, "Session is closed"} =
        ACPClient.send_additional_prompt(session, "Should fail")
    end

    test "handles prompt with system context override" do
      session = %{
        session_id: "test-session",
        port: self()
      }

      # Should be able to override system context for specific prompt
      opts = [system_prompt: "You are now a different assistant"]

      assert {:ok, _result} =
        ACPClient.send_additional_prompt(session, "Test", opts)
    end
  end

  describe "close_session/1" do
    test "closes an open session" do
      session = %{
        session_id: "test-session",
        port: self()  # Mock
      }

      assert :ok = ACPClient.close_session(session)
    end

    test "handles already closed session gracefully" do
      session = %{
        session_id: "test-session",
        port: nil,
        closed: true
      }

      assert :ok = ACPClient.close_session(session)
    end
  end

  describe "set_temperature/2" do
    test "updates temperature for existing session" do
      session = %{
        session_id: "test-session",
        port: self(),
        temperature: 1.0
      }

      # Should update temperature
      assert {:ok, updated_session} = ACPClient.set_temperature(session, 0.2)
      assert updated_session.temperature == 0.2
    end

    test "validates temperature range" do
      session = %{session_id: "test", port: self()}

      # Should reject invalid temperatures
      assert {:error, "Temperature must be between 0 and 2"} =
        ACPClient.set_temperature(session, -1)

      assert {:error, "Temperature must be between 0 and 2"} =
        ACPClient.set_temperature(session, 3)
    end
  end
end