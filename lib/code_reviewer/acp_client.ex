defmodule CodeReviewer.ACPClient do
  @moduledoc """
  Client for Agent Client Protocol (ACP) JSON-RPC communication.

  Implements the ACP protocol for communicating with claude-agent-acp binary
  over stdio using newline-delimited JSON-RPC 2.0 messages.
  """

  require Logger
  alias CodeReviewer.LoggerConfig

  @type message_handler :: (map() -> :ok)
  @type session :: %{
          session_id: String.t(),
          port: port() | nil,
          message_id: integer(),
          on_message: message_handler(),
          temperature: float(),
          mcp_servers: list(map()),
          working_dir: String.t(),
          closed: boolean()
        }

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

  @doc """
  Creates a persistent ACP session that can handle multiple prompts.

  Options:
    - :on_message - callback function that receives each JSON-RPC message
    - :working_dir - directory to run the agent in
    - :env - environment variables
    - :temperature - temperature for the model (0.0 to 2.0, default 1.0)
    - :mcp_servers - list of MCP server configurations

  Returns {:ok, session} or {:error, reason}
  """
  def run_persistent_session(initial_prompt, opts \\ []) do
    on_message = Keyword.get(opts, :on_message, &default_message_handler/1)
    working_dir = Keyword.get(opts, :working_dir, File.cwd!())
    env = Keyword.get(opts, :env, [])
    temperature = Keyword.get(opts, :temperature, 1.0)
    mcp_servers = Keyword.get(opts, :mcp_servers, [])

    with {:ok, port} <- spawn_agent(working_dir, env),
         {:ok, _} <- initialize_with_temperature(port, on_message, temperature),
         {:ok, session_id} <- create_session_with_mcp(port, on_message, working_dir, mcp_servers) do

      session = %{
        session_id: session_id,
        port: port,
        message_id: 4,  # Start at 4 since we've used 1-3 for init
        on_message: on_message,
        temperature: temperature,
        mcp_servers: mcp_servers,
        working_dir: working_dir,
        closed: false
      }

      # Send the initial prompt
      case send_additional_prompt(session, initial_prompt) do
        {:ok, _result} ->
          {:ok, session}

        {:error, reason} ->
          close_port(port)
          {:error, reason}
      end
    else
      {:error, reason} = error ->
        Logger.error("Failed to create persistent session: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Sends an additional prompt to an existing persistent session.

  Options:
    - :system_prompt - override system prompt for this specific message

  Returns {:ok, result} or {:error, reason}
  """
  def send_additional_prompt(session, prompt, opts \\ [])

  def send_additional_prompt(%{closed: true}, _prompt, _opts) do
    {:error, "Session is closed"}
  end

  def send_additional_prompt(session, prompt, opts) do
    %{
      port: port,
      session_id: session_id
    } = session

    message_id = Map.get(session, :message_id, 4)
    on_message = Map.get(session, :on_message, &default_message_handler/1)

    system_prompt = Keyword.get(opts, :system_prompt)

    # Build the prompt message, potentially with system override
    prompt_content =
      if system_prompt do
        "#{system_prompt}\n\n#{prompt}"
      else
        prompt
      end

    request = %{
      jsonrpc: "2.0",
      id: message_id,
      method: "session/prompt",
      params: %{
        sessionId: session_id,
        prompt: [
          %{
            type: "text",
            text: prompt_content
          }
        ]
      }
    }

    Logger.info("Sending additional prompt to session #{session_id}")
    send_message(port, request)

    # Accumulate response
    {:ok, accumulator_pid} = Agent.start_link(fn -> "" end)

    accumulating_handler = fn message ->
      on_message.(message)

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

        # Log any message that might be completion signal
        %{"id" => id} when not is_nil(id) ->
          Logger.debug("[ACP] Got message with ID #{id} during prompt (session_id: #{session_id})")
          :ok

        _ ->
          :ok
      end
    end

    case wait_for_response(port, message_id, accumulating_handler, :infinity) do
      {:ok, _response} ->
        result = Agent.get(accumulator_pid, & &1)
        Agent.stop(accumulator_pid)

        # Note: In a real implementation, we'd need to track message_id state
        # For now, just return the result
        {:ok, result}

      error ->
        Agent.stop(accumulator_pid)
        error
    end
  end

  @doc """
  Closes a persistent session.
  """
  def close_session(session) do
    cond do
      Map.get(session, :closed, false) == true -> :ok
      Map.get(session, :port) == nil -> :ok
      true ->
        close_port(session.port)
        :ok
    end
  end

  @doc """
  Updates the temperature for an existing session.

  Note: Temperature changes apply to subsequent prompts.
  """
  def set_temperature(_session, temperature) when temperature < 0 or temperature > 2 do
    {:error, "Temperature must be between 0 and 2"}
  end

  def set_temperature(session, temperature) do
    {:ok, %{session | temperature: temperature}}
  end

  defp spawn_agent(working_dir, env) do
    # Check for npx
    case System.find_executable("npx") do
      nil ->
        {:error, "npx not found in PATH. Install Node.js to use ACP mode."}

      npx_path ->
        Logger.info("Spawning claude-agent-acp in #{working_dir}")

        Logger.info(
          "Setting permission bypass environment variables"
        )

        try do
          # Unset CLAUDECODE to allow nested sessions
          # Add ACP_PERMISSION_MODE to bypass all permissions
          # Add CLAUDECODE_DANGEROUSLY_SKIP_PERMISSIONS to skip permissions in Claude Code
          # Use the parent's CLAUDE_SETTINGS_DIR if it exists (for auth), otherwise use local
          claude_settings_dir =
            case System.get_env("CLAUDE_SETTINGS_DIR") do
              nil -> Path.join(working_dir, ".claude")
              dir -> dir
            end

          Logger.debug("Using CLAUDE_SETTINGS_DIR: #{claude_settings_dir}")

          # Add this to the provided env list
          # Also pass HOME to ensure ACP can find Claude config
          env_with_overrides = [
            {"CLAUDECODE", false},
            {"ACP_PERMISSION_MODE", "bypassPermissions"},
            {"CLAUDECODE_DANGEROUSLY_SKIP_PERMISSIONS", "true"},
            {"CLAUDE_SETTINGS_DIR", claude_settings_dir},
            {"HOME", System.get_env("HOME", "/home/appuser")}
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
    initialize_with_temperature(port, on_message, 1.0)
  end

  defp initialize_with_temperature(port, on_message, temperature) do
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
        },
        # Add model parameters for temperature
        modelParameters: %{
          temperature: temperature
        }
      }
    }

    LoggerConfig.log_debug("ACP", "Sending initialize request (terminal: false, writeTextFile: false)")
    send_message(port, request)

    # Use 30 second timeout for initialization
    case wait_for_response(port, 1, on_message, 30_000) do
      {:ok, response} ->
        Logger.info("Initialized ACP session successfully")
        LoggerConfig.log_debug("ACP", "Protocol version: #{response["result"]["protocolVersion"]}")
        {:ok, response}

      error ->
        Logger.error("Failed to initialize ACP session after 30s: #{inspect(error)}")
        error
    end
  end

  defp create_session(port, on_message, working_dir) do
    # Default MCP server configuration
    default_mcp_servers = [
      %{
        "type" => "http",
        "name" => "code-reviewer-mcp",
        # Use 127.0.0.1 instead of localhost for better compatibility
        "url" => "http://127.0.0.1:4567/rpc",
        "headers" => [
          %{"name" => "X-Working-Dir", "value" => working_dir}
        ]
      }
    ]

    create_session_with_mcp(port, on_message, working_dir, default_mcp_servers)
  end

  defp create_session_with_mcp(port, on_message, working_dir, mcp_servers) do

    request = %{
      jsonrpc: "2.0",
      id: 2,
      method: "session/new",
      params: %{
        cwd: working_dir,
        mcpServers: mcp_servers
      }
    }

    LoggerConfig.log_debug("ACP", "Creating new session in #{working_dir} with #{length(mcp_servers)} MCP server(s)")
    send_message(port, request)

    # Use longer timeout for session creation with MCP servers (60 seconds)
    # The ACP agent needs to connect to and validate each MCP server
    # which can take time, especially on first connection
    case wait_for_response(port, 2, on_message, 60_000) do
      {:ok, response} ->
        session_id = response["result"]["sessionId"]
        Logger.info("Created session: #{session_id} with git_diff MCP tool")
        {:ok, session_id}

      error ->
        Logger.error("Session creation failed after 60s: #{inspect(error)}")
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
              # Log every message we receive for debugging
              msg_id = Map.get(message, "id")
              msg_method = Map.get(message, "method")
              has_result = Map.has_key?(message, "result")
              has_error = Map.has_key?(message, "error")

              Logger.debug(
                "[ACP] Message - id: #{inspect(msg_id)}, method: #{inspect(msg_method)}, " <>
                "has_result: #{has_result}, has_error: #{has_error}, waiting_for: #{request_id}"
              )

              # Handle permission requests specially with the correct ID
              if message["method"] == "session/request_permission" do
                LoggerConfig.log_debug("Permission", "Received permission request: #{inspect(message)}")
                # Permission requests should have an ID for the JSON-RPC response
                perm_request_id = Map.get(message, "id")
                handle_permission_request_with_port(port, perm_request_id, message["params"])
                # After handling permission, continue waiting for more messages
                on_message.(message)
                check_timeout(timeout, start_time, wait_loop_fn)
              else
                # Call the message handler for all non-permission messages
                on_message.(message)

                # Check if this is the response we're waiting for
                cond do
                  Map.get(message, "id") == request_id and Map.has_key?(message, "result") ->
                    Logger.debug("[ACP] Found matching response for request #{request_id}")
                    {:ok, message}

                  Map.get(message, "id") == request_id and Map.has_key?(message, "error") ->
                    Logger.error("[ACP] Error response for request #{request_id}: #{inspect(message["error"])}")
                    {:error, message["error"]}

                  true ->
                    # Not our response, keep waiting
                    check_timeout(timeout, start_time, wait_loop_fn)
                end
              end

            {:error, error} ->
              Logger.warning("Failed to parse JSON-RPC message: #{inspect(error)}")
              Logger.warning("Raw line was: #{inspect(line)}")
              check_timeout(timeout, start_time, wait_loop_fn)
          end

        {^port, {:exit_status, status}} ->
          Logger.error("[ACP] Agent process exited with status #{status}")
          {:error, "Agent process exited with status #{status}"}
      after
        1000 ->
          elapsed = System.monotonic_time(:millisecond) - start_time
          # Only warn every 10 seconds to reduce noise
          if rem(div(elapsed, 1000), 10) == 0 and elapsed > 5000 do
            Logger.info("[ACP] Still processing request #{request_id} (#{elapsed}ms elapsed)")
          end
          check_timeout(timeout, start_time, wait_loop_fn)
      end
    end

    wait_loop.(wait_loop)
  end

  defp handle_permission_request_with_port(port, id, params) do
    LoggerConfig.log_debug("Permission Request", "ID: #{inspect(id)}, Full params: #{inspect(params)}")

    # Log the tool call being requested
    tool_call = params["toolCall"]
    Logger.info("[Permission] Tool requested: #{inspect(tool_call["title"])}")

    # Find the "allow_always" or "allow_once" option
    option =
      Enum.find(params["options"], fn opt ->
        LoggerConfig.log_debug("Permission", "Checking option: #{inspect(opt)}")
        opt["kind"] == "allow_always" || opt["kind"] == "allow_once"
      end)

    if option do
      Logger.info("[Permission] Auto-approving with: #{option["optionId"]} (#{option["name"]})")
      LoggerConfig.log_debug("Permission", "Selected option: #{inspect(option)}")

      # Send the response to approve the permission
      response = %{
        jsonrpc: "2.0",
        id: id,
        result: %{
          selection: option["optionId"]
        }
      }

      LoggerConfig.log_debug("Permission", "Sending approval response for request #{id}: #{inspect(response)}")
      send_message(port, response)
      LoggerConfig.log_debug("Permission", "Sent permission approval response, waiting for tool execution")

      # Add small delay to ensure response is processed
      Process.sleep(100)
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
