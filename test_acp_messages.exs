#!/usr/bin/env elixir

Mix.install([{:jason, "~> 1.4"}])

# Simple script to see what messages ACP sends during initialization

defmodule ACPTester do
  require Logger

  def test do
    IO.puts("Starting ACP binary...")

    port =
      Port.open(
        {:spawn_executable, System.find_executable("npx")},
        [
          :binary,
          :exit_status,
          {:args, ["--yes", "@zed-industries/claude-agent-acp"]},
          {:line, 1024 * 1024},
          :use_stdio,
          {:env, [
            {~c"CLAUDECODE", false},
            {~c"ACP_PERMISSION_MODE", ~c"bypassPermissions"}
          ]}
        ]
      )

    IO.puts("Sending initialize request...")

    init_request = %{
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: %{
        protocolVersion: 1,
        capabilities: %{
          terminal: false,
          fs: %{readTextFile: true, writeTextFile: false}
        },
        clientInfo: %{
          name: "test",
          version: "1.0.0"
        }
      }
    }

    json = Jason.encode!(init_request)
    Port.command(port, json <> "\n")
    IO.puts("Sent: #{json}\n")

    # Collect messages for 5 seconds
    collect_messages(port, 50, [])
  end

  defp collect_messages(port, 0, messages) do
    Port.close(port)
    IO.puts("\n\n=== SUMMARY ===")
    IO.puts("Total messages received: #{length(messages)}")

    Enum.with_index(messages, 1)
    |> Enum.each(fn {msg, idx} ->
      IO.puts("\nMessage #{idx}:")
      IO.puts("  ID: #{inspect(Map.get(msg, "id"))}")
      IO.puts("  Method: #{inspect(Map.get(msg, "method"))}")
      IO.puts("  Has result: #{Map.has_key?(msg, "result")}")
      IO.puts("  Has error: #{Map.has_key?(msg, "error")}")

      if Map.has_key?(msg, "result") do
        IO.puts("  Result keys: #{inspect(Map.keys(msg["result"]))}")
      end
    end)
  end

  defp collect_messages(port, remaining, messages) do
    receive do
      {^port, {:data, {:eol, line}}} ->
        case Jason.decode(line) do
          {:ok, message} ->
            IO.puts("\n📥 Received message:")
            IO.inspect(message, pretty: true, limit: :infinity)
            collect_messages(port, remaining - 1, [message | messages])

          {:error, error} ->
            IO.puts("❌ JSON decode error: #{inspect(error)}")
            IO.puts("Raw line: #{inspect(line)}")
            collect_messages(port, remaining - 1, messages)
        end

      {^port, {:exit_status, status}} ->
        IO.puts("\n⚠️  Process exited with status: #{status}")
        collect_messages(port, 0, messages)
    after
      100 ->
        IO.write(".")
        collect_messages(port, remaining - 1, messages)
    end
  end
end

ACPTester.test()
