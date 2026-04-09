defmodule CodeReviewer.MCPServer do
  @moduledoc """
  Custom MCP (Model Context Protocol) server for code review.

  Exposes only the tools needed for code review:
  - git_diff: Run git diff commands
  - grep_files: Search for patterns in files

  Claude Code's built-in Read tool is used for reading file contents.
  """

  require Logger

  @doc """
  Start the MCP server on stdio.
  Reads JSON-RPC requests from stdin and writes responses to stdout.
  """
  def start(working_dir) do
    Logger.info("Starting MCP server in #{working_dir}")

    # Main loop: read from stdin, process, write to stdout
    loop(working_dir)
  end

  defp loop(working_dir) do
    case IO.read(:stdio, :line) do
      :eof ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to read from stdin: #{inspect(reason)}")
        :ok

      line ->
        case Jason.decode(line) do
          {:ok, request} ->
            response = handle_request(request, working_dir)
            IO.puts(Jason.encode!(response))
            loop(working_dir)

          {:error, error} ->
            Logger.error("Failed to parse JSON: #{inspect(error)}")
            loop(working_dir)
        end
    end
  end

  defp handle_request(%{"method" => "initialize", "id" => id}, _working_dir) do
    %{
      jsonrpc: "2.0",
      id: id,
      result: %{
        protocolVersion: "2024-11-05",
        capabilities: %{
          tools: %{}
        },
        serverInfo: %{
          name: "code-reviewer-mcp",
          version: "1.0.0"
        }
      }
    }
  end

  defp handle_request(%{"method" => "tools/list", "id" => id}, _working_dir) do
    %{
      jsonrpc: "2.0",
      id: id,
      result: %{
        tools: [
          %{
            name: "git_diff",
            description:
              "Run git diff command to see changes between branches. Supports chunking for large diffs to avoid context window limits.",
            inputSchema: %{
              type: "object",
              properties: %{
                ref1: %{
                  type: "string",
                  description: "First git ref (e.g. 'main', 'HEAD', commit SHA)"
                },
                ref2: %{
                  type: "string",
                  description: "Second git ref (optional, defaults to working directory)"
                },
                three_dot: %{
                  type: "boolean",
                  description:
                    "Use three-dot diff (ref1...ref2) to show changes from common ancestor (default: true)"
                },
                offset: %{
                  type: "integer",
                  description:
                    "Start position for chunking (in characters). Use 0 or omit for the beginning."
                },
                limit: %{
                  type: "integer",
                  description:
                    "Maximum number of characters to return. Omit to return the full diff."
                }
              },
              required: ["ref1"]
            }
          },
          %{
            name: "grep_files",
            description: "Search for a pattern in files using grep",
            inputSchema: %{
              type: "object",
              properties: %{
                pattern: %{
                  type: "string",
                  description: "Pattern to search for (regex supported)"
                },
                path: %{
                  type: "string",
                  description: "Path to search in (file or directory, defaults to '.')"
                },
                recursive: %{
                  type: "boolean",
                  description: "Search recursively (default: true)"
                },
                show_line_numbers: %{
                  type: "boolean",
                  description: "Show line numbers in output (default: true)"
                }
              },
              required: ["pattern"]
            }
          }
        ]
      }
    }
  end

  defp handle_request(%{"method" => "tools/call", "id" => id, "params" => params}, working_dir) do
    result = call_tool(params["name"], params["arguments"], working_dir)

    %{
      jsonrpc: "2.0",
      id: id,
      result: result
    }
  end

  defp handle_request(%{"method" => method, "id" => id}, _working_dir) do
    %{
      jsonrpc: "2.0",
      id: id,
      error: %{
        code: -32601,
        message: "Method not found: #{method}"
      }
    }
  end

  # Handle notification (no id)
  defp handle_request(%{"method" => _method}, _working_dir) do
    # Notifications don't get responses
    nil
  end

  @doc false
  def call_tool(name, args, working_dir), do: do_call_tool(name, args, working_dir)

  defp do_call_tool("git_diff", args, working_dir) do
    ref1 = Map.get(args, "ref1")
    ref2 = Map.get(args, "ref2")
    three_dot = Map.get(args, "three_dot", true)
    offset = Map.get(args, "offset", 0)
    limit = Map.get(args, "limit")

    # Build git diff command
    diff_args =
      cond do
        ref2 && three_dot -> ["diff", "#{ref1}...#{ref2}"]
        ref2 -> ["diff", "#{ref1}..#{ref2}"]
        three_dot -> ["diff", "#{ref1}...HEAD"]
        true -> ["diff", ref1]
      end

    case System.cmd("git", diff_args, cd: working_dir, stderr_to_stdout: true) do
      {output, 0} ->
        chunk_diff_output(output, offset, limit)

      {error, _code} ->
        %{
          content: [
            %{
              type: "text",
              text: "Git diff failed: #{error}"
            }
          ],
          isError: true
        }
    end
  end

  defp do_call_tool("grep_files", args, working_dir) do
    pattern = Map.get(args, "pattern")
    path = Map.get(args, "path", ".")
    recursive = Map.get(args, "recursive", true)
    show_line_numbers = Map.get(args, "show_line_numbers", true)

    full_path = Path.join(working_dir, path)

    # Build grep arguments
    grep_args =
      []
      |> then(fn args -> if recursive, do: ["-r" | args], else: args end)
      |> then(fn args -> if show_line_numbers, do: ["-n" | args], else: args end)
      |> Kernel.++([pattern, full_path])

    case System.cmd("grep", grep_args, cd: working_dir, stderr_to_stdout: true) do
      {output, 0} ->
        %{
          content: [
            %{
              type: "text",
              text: output
            }
          ]
        }

      {_output, 1} ->
        # Exit code 1 means no matches found
        %{
          content: [
            %{
              type: "text",
              text: "No matches found for pattern: #{pattern}"
            }
          ]
        }

      {error, _code} ->
        %{
          content: [
            %{
              type: "text",
              text: "Grep failed: #{error}"
            }
          ],
          isError: true
        }
    end
  end

  defp do_call_tool(name, _args, _working_dir) do
    %{
      content: [
        %{
          type: "text",
          text: "Unknown tool: #{name}"
        }
      ],
      isError: true
    }
  end

  defp chunk_diff_output(full_output, offset, nil) when offset == 0 do
    # No chunking requested - return full output
    %{
      content: [
        %{
          type: "text",
          text: full_output
        }
      ]
    }
  end

  defp chunk_diff_output(full_output, offset, limit) do
    full_length = String.length(full_output)

    cond do
      offset >= full_length ->
        # Offset exceeds content length
        %{
          content: [
            %{
              type: "text",
              text: ""
            }
          ],
          hasMore: false
        }

      offset + limit >= full_length ->
        # Final chunk
        chunk = String.slice(full_output, offset, full_length - offset)

        %{
          content: [
            %{
              type: "text",
              text: chunk
            }
          ],
          hasMore: false
        }

      true ->
        # More chunks available
        chunk = String.slice(full_output, offset, limit)

        %{
          content: [
            %{
              type: "text",
              text: chunk
            }
          ],
          hasMore: true,
          offset: offset + limit
        }
    end
  end
end
