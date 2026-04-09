defmodule CodeReviewer.Test.ACPMockServer do
  @moduledoc """
  Mock ACP server that simulates claude-agent-acp binary responses.
  Useful for testing without requiring the actual binary.
  """

  use GenServer

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def send_response(response) do
    GenServer.call(__MODULE__, {:send_response, response})
  end

  def get_last_request do
    GenServer.call(__MODULE__, :get_last_request)
  end

  def get_all_requests do
    GenServer.call(__MODULE__, :get_all_requests)
  end

  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    parent_pid = Keyword.get(opts, :parent_pid, self())

    state = %{
      requests: [],
      parent_pid: parent_pid,
      session_id: "mock-session-#{:rand.uniform(10000)}",
      message_counter: 1
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:send_response, response}, _from, state) do
    # Send the response to the parent process (simulating port communication)
    if state.parent_pid do
      send(state.parent_pid, {self(), {:data, {:eol, Jason.encode!(response)}}})
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:get_last_request, _from, state) do
    {:reply, List.first(state.requests), state}
  end

  @impl true
  def handle_call(:get_all_requests, _from, state) do
    {:reply, Enum.reverse(state.requests), state}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    {:reply, :ok, %{state | requests: []}}
  end

  @impl true
  def handle_info({:port_command, json}, state) do
    # Handle incoming commands (simulating port receiving data)
    case Jason.decode(json) do
      {:ok, request} ->
        new_state = %{state | requests: [request | state.requests]}

        # Generate appropriate response based on request
        response = generate_response(request, new_state)

        # Send response back
        if state.parent_pid && response do
          send(state.parent_pid, {self(), {:data, {:eol, Jason.encode!(response)}}})
        end

        {:noreply, new_state}

      {:error, _} ->
        {:noreply, state}
    end
  end

  # Response generation

  defp generate_response(%{"method" => "initialize", "id" => id}, _state) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{
        "protocolVersion" => 1,
        "capabilities" => %{
          "terminal" => false,
          "fs" => %{
            "readTextFile" => true,
            "writeTextFile" => false
          },
          "mcpCapabilities" => %{
            "http" => true
          }
        },
        "serverInfo" => %{
          "name" => "mock-acp-server",
          "version" => "1.0.0"
        }
      }
    }
  end

  defp generate_response(%{"method" => "session/new", "id" => id}, state) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{
        "sessionId" => state.session_id
      }
    }
  end

  defp generate_response(%{"method" => "session/prompt", "id" => id, "params" => params}, state) do
    session_id = params["sessionId"]
    prompt_text = get_in(params, ["prompt", Access.at(0), "text"]) || ""

    # Send session update first
    session_update = %{
      "jsonrpc" => "2.0",
      "method" => "session/update",
      "params" => %{
        "sessionId" => session_id,
        "update" => %{
          "sessionUpdate" => "agent_message_chunk",
          "content" => %{
            "text" => "Mock response to: #{String.slice(prompt_text, 0, 50)}"
          }
        }
      }
    }

    if state.parent_pid do
      send(state.parent_pid, {self(), {:data, {:eol, Jason.encode!(session_update)}}})
    end

    # Return completion
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{
        "sessionId" => session_id,
        "status" => "completed"
      }
    }
  end

  defp generate_response(_request, _state), do: nil
end

defmodule CodeReviewer.Test.ACPMockPort do
  @moduledoc """
  Mock Port implementation for testing ACP client without spawning real processes.
  """

  defstruct [:pid, :owner, :info]

  def new(opts \\ []) do
    owner = Keyword.get(opts, :owner, self())

    # Start the mock server
    {:ok, pid} = CodeReviewer.Test.ACPMockServer.start_link(parent_pid: owner)

    %__MODULE__{
      pid: pid,
      owner: owner,
      info: %{
        connected: owner,
        id: :rand.uniform(65536),
        name: "mock_acp_port"
      }
    }
  end

  def command(%__MODULE__{pid: pid}, data) when is_binary(data) do
    # Strip trailing newline if present
    json = String.trim_trailing(data, "\n")

    # Send to mock server
    send(pid, {:port_command, json})
    true
  end

  def close(%__MODULE__{pid: pid}) do
    if Process.alive?(pid) do
      GenServer.stop(pid, :normal, 1000)
    end
    true
  end

  def info(%__MODULE__{info: info}), do: {:ok, Enum.to_list(info)}
end