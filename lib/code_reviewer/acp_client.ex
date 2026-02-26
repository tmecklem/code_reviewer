defmodule CodeReviewer.ACPClient do
  @moduledoc """
  Client for Agent Client Protocol (ACP) JSON-RPC communication.

  Implements the ACP protocol for communicating with claude-agent-acp binary
  over stdio using newline-delimited JSON-RPC 2.0 messages.
  """

  require Logger
  alias CodeReviewer.LoggerConfig

  @type message_handler :: (map() -> :ok)

  @doc """
  Runs an ACP session with the claude-agent-acp binary.

  Options:
    - :on_message - callback function that receives each JSON-RPC message
    - :working_dir - directory to run the agent in
    - :env - environment variables

  Returns {:ok, session_id} or {:error, reason}
  """
  def run_session(prompt, opts \\ []) do
    on_message = Keyword.get(opts, :on_message, &default_message_handler/1)
    working_dir = Keyword.get(opts, :working_dir, File.cwd!())
    env = Keyword.get(opts, :env, [])

    with {:ok, port} <- spawn_agent(working_dir, env),
         {:ok, _} <- initialize(port, on_message),
         {:ok, session_id} <- create_session(port, on_message, working_dir),
         {:ok, result} <- send_prompt(port, session_id, prompt, on_message) do
      close_port(port)
      {:ok, result}
    else
      {:error, reason} = error ->
        Logger.error("ACP session failed: #{inspect(reason)}")
        error
    end
  end

  defp spawn_agent(working_dir, env) do
    # Check for npx
    case System.find_executable("npx") do
      nil ->
        {:error, "npx not found in PATH. Install Node.js to use ACP mode."}

      npx_path ->
        Logger.info("Spawning claude-agent-acp in #{working_dir}")

        Logger.info(
          "Setting ACP_PERMISSION_MODE=bypassPermissions to bypass all permission checks"
        )

        try do
          # Unset CLAUDECODE to allow nested sessions
          # Add ACP_PERMISSION_MODE to bypass all permissions
          # Add this to the provided env list
          env_with_overrides = [
            {"CLAUDECODE", false},
            {"ACP_PERMISSION_MODE", "bypassPermissions"}
            | env
          ]

          # Convert env list to list of tuples format expected by Port
          port_env =
            Enum.map(env_with_overrides, fn
              {k, v} when is_binary(k) and is_binary(v) ->
                {String.to_charlist(k), String.to_charlist(v)}

              {k, false} when is_binary(k) ->
                # false means unset the variable
                {String.to_charlist(k), false}

              other ->
                other
            end)

          port =
            Port.open(
              {:spawn_executable, npx_path},
              [
                :binary,
                :exit_status,
                {:args,
                 [
                   "--yes",
                   "@zed-industries/claude-agent-acp"
                 ]},
                {:cd, working_dir},
                {:env, port_env},
                {:line, 1024 * 1024},
                # 1MB line buffer for large JSON messages
                :use_stdio
              ]
            )

          {:ok, port}
        rescue
          e ->
            {:error, "Failed to spawn claude-agent-acp: #{inspect(e)}"}
        end
    end
  end

  defp initialize(port, on_message) do
    request = %{
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: %{
        protocolVersion: 1,
        capabilities: %{
          # Disable all terminal/bash operations (correct ACP format)
          terminal: false,
          # Allow reading files but not writing (for security)
          fs: %{
            readTextFile: true,
            writeTextFile: false
          }
        },
        clientInfo: %{
          name: "code_reviewer",
          version: "1.0.0"
        }
      }
    }

    LoggerConfig.log_debug("ACP", "Sending initialize request (terminal: false, writeTextFile: false)")
    send_message(port, request)

    case wait_for_response(port, 1, on_message, 10_000) do
      {:ok, response} ->
        Logger.info("Initialized ACP session: #{inspect(response["result"])}")
        {:ok, response}

      error ->
        error
    end
  end

  defp create_session(port, on_message, working_dir) do
    # Create session with HTTP MCP server configuration
    # The claude-agent-acp reported it supports HTTP in mcpCapabilities
    mcp_servers = [
      %{
        "type" => "http",
        "name" => "code-reviewer-mcp",
        "url" => "http://localhost:4567/rpc",
        "headers" => []
      }
    ]

    request = %{
      jsonrpc: "2.0",
      id: 2,
      method: "session/new",
      params: %{
        cwd: working_dir,
        mcpServers: mcp_servers
      }
    }

    LoggerConfig.log_debug("ACP", "Creating new session in #{working_dir} with HTTP MCP server")
    send_message(port, request)

    case wait_for_response(port, 2, on_message, 10_000) do
      {:ok, response} ->
        session_id = response["result"]["sessionId"]
        Logger.info("Created session: #{session_id} with git_diff MCP tool")
        {:ok, session_id}

      error ->
        error
    end
  end

  defp send_prompt(port, session_id, prompt, on_message) do
    request = %{
      jsonrpc: "2.0",
      id: 3,
      method: "session/prompt",
      params: %{
        sessionId: session_id,
        prompt: [
          %{
            type: "text",
            text: prompt
          }
        ]
      }
    }

    Logger.info("Sending prompt to session #{session_id}")
    send_message(port, request)

    # Accumulate agent message chunks
    {:ok, accumulator_pid} = Agent.start_link(fn -> "" end)

    # Create a custom message handler that accumulates agent responses
    accumulating_handler = fn message ->
      on_message.(message)

      # Extract agent message chunks from session updates
      case message do
        %{
          "method" => "session/update",
          "params" => %{
            "update" => %{
              "sessionUpdate" => "agent_message_chunk",
              "content" => %{"text" => text}
            }
          }
        } ->
          Agent.update(accumulator_pid, fn current -> current <> text end)

        _ ->
          :ok
      end
    end

    # Wait for the final response
    # Meanwhile, session/update notifications will be handled by accumulating_handler
    case wait_for_response(port, 3, accumulating_handler, :infinity) do
      {:ok, _response} ->
        Logger.info("Session completed")
        result = Agent.get(accumulator_pid, & &1)
        Agent.stop(accumulator_pid)
        {:ok, result}

      error ->
        Agent.stop(accumulator_pid)
        error
    end
  end

  defp send_message(port, message) do
    json = Jason.encode!(message)
    Port.command(port, json <> "\n")
  end

  defp wait_for_response(port, request_id, on_message, timeout) do
    start_time = System.monotonic_time(:millisecond)

    wait_loop = fn wait_loop_fn ->
      receive do
        {^port, {:data, {:eol, line}}} ->
          case Jason.decode(line) do
            {:ok, message} ->
              # Handle permission requests specially with the correct ID
              if message["method"] == "session/request_permission" do
                LoggerConfig.log_debug("Permission", "Raw message: #{inspect(message)}")
                # Permission requests should have an ID for the JSON-RPC response
                request_id = Map.get(message, "id", 0)
                handle_permission_request_with_port(port, request_id, message["params"])
              end

              # Call the message handler for all messages
              on_message.(message)

              # Check if this is the response we're waiting for
              cond do
                Map.get(message, "id") == request_id and Map.has_key?(message, "result") ->
                  {:ok, message}

                Map.get(message, "id") == request_id and Map.has_key?(message, "error") ->
                  {:error, message["error"]}

                true ->
                  # Not our response, keep waiting
                  check_timeout(timeout, start_time, wait_loop_fn)
              end

            {:error, error} ->
              Logger.warning("Failed to parse JSON-RPC message: #{inspect(error)}")
              check_timeout(timeout, start_time, wait_loop_fn)
          end

        {^port, {:exit_status, status}} ->
          {:error, "Agent process exited with status #{status}"}
      after
        1000 ->
          check_timeout(timeout, start_time, wait_loop_fn)
      end
    end

    wait_loop.(wait_loop)
  end

  defp handle_permission_request_with_port(port, id, params) do
    LoggerConfig.log_debug("Permission Request", "ID: #{inspect(id)}, Full params: #{inspect(params)}")

    # Find the "allow_always" or "allow_once" option
    option =
      Enum.find(params["options"], fn opt ->
        LoggerConfig.log_debug("Permission", "Checking option: #{inspect(opt)}")
        opt["kind"] == "allow_always" || opt["kind"] == "allow_once"
      end)

    if option do
      Logger.info("[Permission] Auto-approving: #{option["name"]}")
      LoggerConfig.log_debug("Permission", "Selected option: #{inspect(option)}")

      # Send the response to approve the permission
      response = %{
        jsonrpc: "2.0",
        id: id,
        result: %{
          # Fixed: was option["id"], should be optionId
          selection: option["optionId"]
        }
      }

      LoggerConfig.log_debug("Permission", "Sending response: #{inspect(response)}")
      send_message(port, response)
      LoggerConfig.log_debug("Permission", "Sent permission approval response")
    else
      Logger.warning("[Permission] No allow option found in: #{inspect(params["options"])}")

      # Send error response
      response = %{
        jsonrpc: "2.0",
        id: id,
        error: %{
          code: -32603,
          message: "No allow option available"
        }
      }

      send_message(port, response)
    end
  end

  defp check_timeout(:infinity, _start_time, wait_loop_fn) do
    wait_loop_fn.(wait_loop_fn)
  end

  defp check_timeout(timeout, start_time, wait_loop_fn) do
    elapsed = System.monotonic_time(:millisecond) - start_time

    if elapsed >= timeout do
      {:error, "Timeout waiting for response after #{timeout}ms"}
    else
      wait_loop_fn.(wait_loop_fn)
    end
  end

  defp close_port(port) do
    Port.close(port)
  rescue
    _ -> :ok
  end

  defp default_message_handler(message) do
    case message do
      %{"method" => "session/update", "params" => params} ->
        log_session_update(params)

      %{"method" => "session/request_permission", "params" => params} ->
        Logger.info("[Permission Request] #{inspect(params["toolCall"])}")
        # Note: Permission requests need to be handled in the context with port access
        # This handler just logs the request
        :ok

      %{"id" => id, "result" => _result} ->
        LoggerConfig.log_debug("ACP", "Received response for request #{id}")

      %{"id" => id, "error" => error} ->
        Logger.error("Received error for request #{id}: #{inspect(error)}")

      _ ->
        LoggerConfig.log_debug("ACP", "Received message: #{inspect(message)}")
    end
  end

  defp log_session_update(%{"type" => "message", "message" => message_data}) do
    content = message_data["content"] || []

    Enum.each(content, fn
      %{"type" => "text", "text" => text} ->
        Logger.info("[Agent] #{text}")

      %{"type" => "tool_use", "name" => name, "input" => input} ->
        Logger.info("[Tool Call] #{name}")
        LoggerConfig.log_debug("Tool", "Input: #{inspect(input)}")

      %{"type" => "tool_result", "tool_use_id" => tool_id, "content" => result} ->
        Logger.info("[Tool Result] #{tool_id}")

        # Show the actual tool result content
        case result do
          [%{"type" => "text", "text" => text}] ->
            Logger.info("Output: #{text}")

          list when is_list(list) ->
            Enum.each(list, fn
              %{"type" => "text", "text" => text} ->
                Logger.info("Output: #{text}")

              other ->
                Logger.info("Output: #{inspect(other)}")
            end)

          other ->
            Logger.info("Output: #{inspect(other)}")
        end

      %{"type" => "thinking"} = thinking ->
        thinking_text = Map.get(thinking, "thinking", "...")
        Logger.info("[Thinking] #{thinking_text}")

      other ->
        LoggerConfig.log_debug("Content", inspect(other))
    end)
  end

  defp log_session_update(%{"type" => "plan", "plan" => plan}) do
    Logger.info("[Plan] #{inspect(plan)}")
  end

  defp log_session_update(%{"sessionId" => _session_id, "update" => update} = _params) do
    # Parse ACP session updates for readable progress logging
    case update do
      %{"sessionUpdate" => "tool_call", "title" => title, "status" => "pending"} ->
        IO.puts("  → #{title}")

      %{"sessionUpdate" => "tool_call_update", "title" => title, "status" => "completed"} ->
        IO.puts("  ✓ #{title}")

      %{"sessionUpdate" => "tool_call_update", "title" => title, "status" => "failed"} ->
        IO.puts("  ✗ #{title} (failed)")

      %{"sessionUpdate" => "agent_message_chunk", "content" => %{"text" => text}}
      when text != "" ->
        # Stream agent thinking/responses without newline
        IO.write(text)

      %{"sessionUpdate" => "available_commands_update"} ->
        # Skip verbose command listings
        :ok

      _ ->
        # Log other updates at debug level
        LoggerConfig.log_debug("Session Update", inspect(update))
    end
  end

  defp log_session_update(%{"type" => type} = params) do
    LoggerConfig.log_debug("Session Update: #{type}", inspect(params))
  end

  defp log_session_update(params) do
    LoggerConfig.log_debug("Session Update", inspect(params))
  end
end
