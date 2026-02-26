defmodule CodeReviewer.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        # Start the MCP HTTP server if enabled
        maybe_start_mcp_server()
      ]
      |> List.flatten()
      |> Enum.reject(&is_nil/1)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CodeReviewer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_start_mcp_server do
    if Application.get_env(:code_reviewer, :start_mcp_server, false) do
      CodeReviewer.MCPHttpSupervisor
    end
  end
end
