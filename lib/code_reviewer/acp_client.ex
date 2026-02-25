defmodule CodeReviewer.ACPClient do
  @moduledoc """
  Client for Agent Client Protocol (ACP) JSON-RPC communication.

  Implements the ACP protocol for communicating with claude-agent-acp binary
  over stdio using newline-delimited JSON-RPC 2.0 messages.
  """

  require Logger

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

        try do
          # Unset CLAUDECODE to allow nested sessions
          # Add this to the provided env list
          env_with_unset = [{"CLAUDECODE", false} | env]

          # Convert env list to list of tuples format expected by Port
          port_env =
            Enum.map(env_with_unset, fn
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
                {:args, [
                  "--yes",
                  "@zed-industries/claude-agent-acp",
                  "--",
                  "--dangerously-skip-permissions"
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
          tools: %{},
          terminal: %{
            execute: true,
            manage: true
          }
        },
        clientInfo: %{
          name: "code_reviewer",
          version: "1.0.0"
        }
      }
    }

    Logger.debug("Sending initialize request")
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
    request = %{
      jsonrpc: "2.0",
      id: 2,
      method: "session/new",
      params: %{
        cwd: working_dir,
        mcpServers: []
      }
    }

    Logger.debug("Creating new session in #{working_dir}")
    send_message(port, request)

    case wait_for_response(port, 2, on_message, 10_000) do
      {:ok, response} ->
        session_id = response["result"]["sessionId"]
        Logger.info("Created session: #{session_id}")
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

    # Wait for the final response
    # Meanwhile, session/update notifications will be handled by on_message
    case wait_for_response(port, 3, on_message, :infinity) do
      {:ok, response} ->
        Logger.info("Session completed")
        {:ok, response["result"]}

      error ->
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

      %{"method" => "session/request_permission", "params" => params} = msg ->
        Logger.info("[Permission Request] #{inspect(params["toolCall"])}")
        # Auto-approve permission requests in non-interactive mode
        handle_permission_request(msg)

      %{"id" => id, "result" => _result} ->
        Logger.debug("Received response for request #{id}")

      %{"id" => id, "error" => error} ->
        Logger.error("Received error for request #{id}: #{inspect(error)}")

      _ ->
        Logger.debug("Received message: #{inspect(message)}")
    end
  end

  defp handle_permission_request(%{"id" => id, "params" => params}) do
    # Find the "allow_always" or "allow" option
    option =
      Enum.find(params["options"], fn opt ->
        opt["kind"] == "allow_always" || opt["kind"] == "allow_once"
      end)

    if option do
      Logger.info("[Permission] Auto-approving: #{option["name"]}")

      # Send the response to approve the permission
      # Note: We need access to the port here, but default_message_handler doesn't have it
      # This is a limitation - we'll need to restructure to handle this properly
      :ok
    else
      Logger.warning("[Permission] No allow option found")
      :ok
    end
  end

  defp log_session_update(%{"type" => "message", "message" => message_data}) do
    content = message_data["content"] || []

    Enum.each(content, fn
      %{"type" => "text", "text" => text} ->
        Logger.info("[Agent] #{text}")

      %{"type" => "tool_use", "name" => name, "input" => input} ->
        Logger.info("[Tool Call] #{name}")
        Logger.debug("Tool input: #{inspect(input)}")

      %{"type" => "tool_result", "tool_use_id" => tool_id, "content" => result} ->
        Logger.info("[Tool Result] #{tool_id}")
        Logger.debug("Tool result: #{inspect(result)}")

      %{"type" => "thinking"} = thinking ->
        thinking_text = Map.get(thinking, "thinking", "...")
        Logger.info("[Thinking] #{thinking_text}")

      other ->
        Logger.debug("[Content] #{inspect(other)}")
    end)
  end

  defp log_session_update(%{"type" => "plan", "plan" => plan}) do
    Logger.info("[Plan] #{inspect(plan)}")
  end

  defp log_session_update(%{"type" => type} = params) do
    Logger.debug("[Session Update: #{type}] #{inspect(params)}")
  end

  defp log_session_update(params) do
    Logger.debug("[Session Update] #{inspect(params)}")
  end
end
