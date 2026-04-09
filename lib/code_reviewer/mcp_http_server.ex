defmodule CodeReviewer.MCPHttpServer do
  @moduledoc """
  HTTP-based MCP server for code review tools.

  Provides git_diff and grep_files tools via JSON-RPC 2.0 over HTTP.
  Supports chunking for large diff responses.
  Includes feedback accumulator for deduplicating review comments.
  """

  use Plug.Router

  require Logger

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason,
    body_reader: {__MODULE__, :read_body, []}
  )

  plug(:match)
  plug(:dispatch)

  # Custom body reader to handle parse errors gracefully
  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        {:ok, body, conn}

      {:more, _data, _conn} = result ->
        result

      {:error, _reason} = error ->
        error
    end
  end

  # HTTP endpoints

  post "/rpc" do
    try do
      response =
        case conn.body_params do
          nil ->
            error_response(nil, -32700, "Parse error")

          params ->
            case handle_jsonrpc(params, conn) do
              {:ok, response} -> response
              {:error, response} -> response
            end
        end

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(response))
    rescue
      Plug.Parsers.ParseError ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(error_response(nil, -32700, "Parse error")))
    end
  end

  get "/health" do
    send_resp(conn, 200, "OK")
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  # Simplified server management (no GenServer needed for tests)

  def start_link(opts \\ []) do
    working_dir = Keyword.get(opts, :working_dir, File.cwd!())

    # Store working directory in process dictionary for this test approach
    Process.put(:working_dir, working_dir)


    # For tests, we don't need to start an actual HTTP server
    # The Plug.Test helpers simulate HTTP requests
    {:ok, self()}
  end


  def call(conn, opts) do
    # Allow working_dir to be passed as an option or use process dictionary
    working_dir = Keyword.get(opts, :working_dir, Process.get(:working_dir, File.cwd!()))
    Process.put(:working_dir, working_dir)

    super(conn, opts)
  end

  # JSON-RPC handlers

  defp handle_jsonrpc(nil, _conn) do
    {:error, error_response(nil, -32700, "Parse error")}
  end

  defp handle_jsonrpc(request, conn) when is_map(request) do
    id = Map.get(request, "id")
    method = Map.get(request, "method")
    params = Map.get(request, "params", %{})

    case method do
      "initialize" ->
        handle_initialize(id, params)

      "tools/list" ->
        handle_tools_list(id, params)

      "tools/call" ->
        handle_tools_call(id, params, conn)

      nil ->
        {:error, error_response(id, -32600, "Invalid request")}

      _ ->
        {:error, error_response(id, -32601, "Method not found")}
    end
  rescue
    e ->
      Logger.error("Error handling JSON-RPC request: #{inspect(e)}")
      {:error, error_response(Map.get(request, "id"), -32603, "Internal error")}
  end

  defp handle_jsonrpc(_, _conn) do
    {:error, error_response(nil, -32700, "Parse error")}
  end

  defp handle_initialize(id, _params) do
    {:ok,
     success_response(id, %{
       "protocolVersion" => "2024-11-05",
       "capabilities" => %{
         "tools" => %{}
       },
       "serverInfo" => %{
         "name" => "code-reviewer-mcp",
         "version" => "1.0.0"
       }
     })}
  end

  defp handle_tools_list(id, _params) do
    tools = [
      %{
        "name" => "git_diff",
        "description" =>
          "Run git diff command to see changes between branches. Supports chunking for large diffs.",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "ref1" => %{
              "type" => "string",
              "description" => "First git ref (e.g. 'main', 'HEAD', commit SHA)"
            },
            "ref2" => %{
              "type" => "string",
              "description" => "Second git ref (optional, defaults to working directory)"
            },
            "three_dot" => %{
              "type" => "boolean",
              "description" =>
                "Use three-dot diff (ref1...ref2) to show changes from common ancestor"
            },
            "offset" => %{
              "type" => "integer",
              "description" => "Start position for chunking (in characters)"
            },
            "limit" => %{
              "type" => "integer",
              "description" => "Maximum number of characters to return"
            }
          },
          "required" => ["ref1"]
        }
      },
      %{
        "name" => "grep_files",
        "description" => "Search for a pattern in files using grep",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "pattern" => %{
              "type" => "string",
              "description" => "Pattern to search for (regex supported)"
            },
            "path" => %{
              "type" => "string",
              "description" => "Path to search in (file or directory, defaults to '.')"
            },
            "recursive" => %{
              "type" => "boolean",
              "description" => "Search recursively (default: true)"
            },
            "show_line_numbers" => %{
              "type" => "boolean",
              "description" => "Show line numbers in output (default: true)"
            }
          },
          "required" => ["pattern"]
        }
      },
      %{
        "name" => "add_feedback",
        "description" => "Add review feedback with deduplication by file and line",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{
            "severity" => %{
              "type" => "string",
              "enum" => ["critical", "high", "medium", "low"],
              "description" => "Severity level of the issue"
            },
            "file" => %{
              "type" => "string",
              "description" => "File path where the issue is located"
            },
            "line" => %{
              "type" => "integer",
              "description" => "Line number where the issue is located"
            },
            "issue" => %{
              "type" => "string",
              "description" => "Description of the issue"
            },
            "suggestion" => %{
              "type" => "string",
              "description" => "Suggested fix for the issue"
            },
            "quote" => %{
              "type" => "string",
              "description" => "Code snippet showing the issue (optional)"
            }
          },
          "required" => ["severity", "file", "line", "issue", "suggestion"]
        }
      },
      %{
        "name" => "get_feedback",
        "description" => "Get accumulated feedback (deduplicated)",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{}
        }
      },
      %{
        "name" => "clear_feedback",
        "description" => "Clear all accumulated feedback",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{}
        }
      }
    ]

    {:ok, success_response(id, %{"tools" => tools})}
  end

  defp handle_tools_call(id, params, conn) do
    name = Map.get(params, "name")
    arguments = Map.get(params, "arguments", %{})

    # Get working directory from header if provided, otherwise use process default
    working_dir = case get_req_header(conn, "x-working-dir") do
      [dir | _] -> dir
      [] -> Process.get(:working_dir, File.cwd!())
    end

    case name do
      "git_diff" ->
        result = call_git_diff(arguments, working_dir)
        {:ok, success_response(id, result)}

      "grep_files" ->
        result = call_grep_files(arguments, working_dir)
        {:ok, success_response(id, result)}

      "add_feedback" ->
        result = call_add_feedback(arguments)
        {:ok, success_response(id, result)}

      "get_feedback" ->
        result = call_get_feedback()
        {:ok, success_response(id, result)}

      "clear_feedback" ->
        result = call_clear_feedback()
        {:ok, success_response(id, result)}

      _ ->
        {:error, error_response(id, -32602, "Unknown tool: #{name}")}
    end
  end

  # Tool implementations

  defp call_add_feedback(args) do
    # Validate required fields
    required_fields = ["severity", "file", "line", "issue", "suggestion"]

    if Enum.all?(required_fields, fn field -> Map.has_key?(args, field) end) do
      case CodeReviewer.FeedbackStore.add_feedback(args) do
        {:ok, message} ->
          %{
            "content" => [
              %{
                "type" => "text",
                "text" => message
              }
            ]
          }

        {:duplicate, message} ->
          %{
            "content" => [
              %{
                "type" => "text",
                "text" => message
              }
            ]
          }
      end
    else
      %{
        "content" => [
          %{
            "type" => "text",
            "text" => "Error: Missing required fields",
            "isError" => true
          }
        ]
      }
    end
  end

  defp call_get_feedback do
    feedback = CodeReviewer.FeedbackStore.get_all_feedback()

    %{
      "content" => [
        %{
          "type" => "text",
          "text" => Jason.encode!(feedback)
        }
      ]
    }
  end

  defp call_clear_feedback do
    CodeReviewer.FeedbackStore.clear_all_feedback()

    %{
      "content" => [
        %{
          "type" => "text",
          "text" => "Feedback cleared successfully"
        }
      ]
    }
  end

  defp call_git_diff(args, working_dir) do
    ref1 = Map.get(args, "ref1", "HEAD")
    ref2 = Map.get(args, "ref2")
    three_dot = Map.get(args, "three_dot", true)
    offset = Map.get(args, "offset", 0)
    limit = Map.get(args, "limit")

    # Build git diff command - just try to run it
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
          "content" => [
            %{
              "type" => "text",
              "text" => "Git diff failed: #{error}"
            }
          ],
          "isError" => true
        }
    end
  end

  defp chunk_diff_output(full_output, offset, nil) when offset == 0 do
    # No chunking requested - return full output
    %{
      "content" => [
        %{
          "type" => "text",
          "text" => full_output
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
          "content" => [
            %{
              "type" => "text",
              "text" => ""
            }
          ],
          "hasMore" => false
        }

      offset + limit >= full_length ->
        # Final chunk
        chunk = String.slice(full_output, offset, full_length - offset)

        %{
          "content" => [
            %{
              "type" => "text",
              "text" => chunk
            }
          ],
          "hasMore" => false
        }

      true ->
        # More chunks available
        chunk = String.slice(full_output, offset, limit)

        %{
          "content" => [
            %{
              "type" => "text",
              "text" => chunk
            }
          ],
          "hasMore" => true,
          "offset" => offset + limit
        }
    end
  end

  defp call_grep_files(args, working_dir) do
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
          "content" => [
            %{
              "type" => "text",
              "text" => output
            }
          ]
        }

      {_output, 1} ->
        # Exit code 1 means no matches found
        %{
          "content" => [
            %{
              "type" => "text",
              "text" => "No matches found for pattern: #{pattern}"
            }
          ]
        }

      {error, _code} ->
        %{
          "content" => [
            %{
              "type" => "text",
              "text" => "Grep failed: #{error}"
            }
          ],
          "isError" => true
        }
    end
  end

  # Response helpers

  defp success_response(id, result) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => result
    }
  end

  defp error_response(id, code, message) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{
        "code" => code,
        "message" => message
      }
    }
  end
end
