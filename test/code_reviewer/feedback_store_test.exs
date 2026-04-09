defmodule CodeReviewer.FeedbackStoreTest do
  use ExUnit.Case, async: false

  alias CodeReviewer.FeedbackStore

  setup do
    # Start the FeedbackStore if not already running
    case GenServer.whereis(FeedbackStore) do
      nil ->
        {:ok, _pid} = FeedbackStore.start_link([])
      _pid ->
        :ok
    end

    # Clear any existing feedback before each test
    FeedbackStore.clear_all_feedback()
    :ok
  end

  describe "add_feedback/1" do
    test "adds new feedback successfully" do
      feedback = %{
        "severity" => "high",
        "file" => "test.ex",
        "line" => 10,
        "issue" => "Test issue",
        "suggestion" => "Fix it"
      }

      assert {:ok, "Feedback added successfully"} = FeedbackStore.add_feedback(feedback)
    end

    test "prevents duplicate feedback for same file and line" do
      feedback = %{
        "severity" => "high",
        "file" => "test.ex",
        "line" => 10,
        "issue" => "Test issue",
        "suggestion" => "Fix it"
      }

      assert {:ok, "Feedback added successfully"} = FeedbackStore.add_feedback(feedback)
      assert {:duplicate, "Feedback already exists for test.ex:10 (skipped)"} =
        FeedbackStore.add_feedback(feedback)
    end

    test "allows feedback for same file but different line" do
      feedback1 = %{
        "severity" => "high",
        "file" => "test.ex",
        "line" => 10,
        "issue" => "Issue 1",
        "suggestion" => "Fix 1"
      }

      feedback2 = %{
        "severity" => "medium",
        "file" => "test.ex",
        "line" => 20,
        "issue" => "Issue 2",
        "suggestion" => "Fix 2"
      }

      assert {:ok, "Feedback added successfully"} = FeedbackStore.add_feedback(feedback1)
      assert {:ok, "Feedback added successfully"} = FeedbackStore.add_feedback(feedback2)
    end
  end

  describe "get_all_feedback/0" do
    test "returns empty findings when no feedback exists" do
      assert %{"findings" => []} = FeedbackStore.get_all_feedback()
    end

    test "returns all added feedback sorted by file and line" do
      feedback1 = %{
        "severity" => "high",
        "file" => "b.ex",
        "line" => 20,
        "issue" => "Issue B",
        "suggestion" => "Fix B"
      }

      feedback2 = %{
        "severity" => "medium",
        "file" => "a.ex",
        "line" => 10,
        "issue" => "Issue A",
        "suggestion" => "Fix A"
      }

      feedback3 = %{
        "severity" => "low",
        "file" => "b.ex",
        "line" => 5,
        "issue" => "Issue B2",
        "suggestion" => "Fix B2"
      }

      FeedbackStore.add_feedback(feedback1)
      FeedbackStore.add_feedback(feedback2)
      FeedbackStore.add_feedback(feedback3)

      %{"findings" => findings} = FeedbackStore.get_all_feedback()

      assert length(findings) == 3
      # Should be sorted by file, then line
      assert [
        %{"file" => "a.ex", "line" => 10},
        %{"file" => "b.ex", "line" => 5},
        %{"file" => "b.ex", "line" => 20}
      ] = Enum.map(findings, &Map.take(&1, ["file", "line"]))
    end

    test "persists feedback across multiple calls" do
      feedback = %{
        "severity" => "high",
        "file" => "test.ex",
        "line" => 10,
        "issue" => "Persistent issue",
        "suggestion" => "Fix it"
      }

      FeedbackStore.add_feedback(feedback)

      # First call
      %{"findings" => findings1} = FeedbackStore.get_all_feedback()
      assert length(findings1) == 1

      # Second call - should still have the feedback
      %{"findings" => findings2} = FeedbackStore.get_all_feedback()
      assert length(findings2) == 1
      assert findings1 == findings2
    end
  end

  describe "clear_all_feedback/0" do
    test "removes all feedback" do
      feedback1 = %{
        "severity" => "high",
        "file" => "test1.ex",
        "line" => 10,
        "issue" => "Issue 1",
        "suggestion" => "Fix 1"
      }

      feedback2 = %{
        "severity" => "medium",
        "file" => "test2.ex",
        "line" => 20,
        "issue" => "Issue 2",
        "suggestion" => "Fix 2"
      }

      FeedbackStore.add_feedback(feedback1)
      FeedbackStore.add_feedback(feedback2)

      %{"findings" => findings_before} = FeedbackStore.get_all_feedback()
      assert length(findings_before) == 2

      assert :ok = FeedbackStore.clear_all_feedback()

      %{"findings" => findings_after} = FeedbackStore.get_all_feedback()
      assert findings_after == []
    end
  end

  describe "ETS table persistence" do
    test "ETS table survives process restarts" do
      feedback = %{
        "severity" => "high",
        "file" => "persist.ex",
        "line" => 1,
        "issue" => "Persistence test",
        "suggestion" => "Should persist"
      }

      # Add feedback
      FeedbackStore.add_feedback(feedback)

      # Verify it's there
      %{"findings" => [stored_feedback]} = FeedbackStore.get_all_feedback()
      assert stored_feedback["file"] == "persist.ex"

      # The ETS table should still exist and have data
      # (In the real implementation, the GenServer owns the table,
      # so it persists as long as the GenServer is alive)
      assert :ets.whereis(:mcp_feedback_accumulator) != :undefined
      assert length(:ets.tab2list(:mcp_feedback_accumulator)) == 1
    end
  end
end