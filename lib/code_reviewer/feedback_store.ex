defmodule CodeReviewer.FeedbackStore do
  @moduledoc """
  GenServer that manages the feedback ETS table for the MCP server.
  Ensures the ETS table persists across HTTP requests.
  """
  use GenServer

  @table_name :mcp_feedback_accumulator

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    # Create the ETS table owned by this process
    :ets.new(@table_name, [:set, :public, :named_table])
    {:ok, %{}}
  end

  def add_feedback(feedback) do
    key = {feedback["file"], feedback["line"]}

    case :ets.lookup(@table_name, key) do
      [] ->
        :ets.insert(@table_name, {key, feedback})
        {:ok, "Feedback added successfully"}
      _ ->
        {:duplicate, "Feedback already exists for #{feedback["file"]}:#{feedback["line"]} (skipped)"}
    end
  end

  def get_all_feedback do
    findings =
      :ets.tab2list(@table_name)
      |> Enum.map(fn {_key, feedback} -> feedback end)
      |> Enum.sort_by(fn f -> {f["file"], f["line"]} end)

    %{"findings" => findings}
  end

  def clear_all_feedback do
    :ets.delete_all_objects(@table_name)
    :ok
  end
end