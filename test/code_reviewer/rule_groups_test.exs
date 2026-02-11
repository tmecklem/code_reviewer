defmodule CodeReviewer.RuleGroupsTest do
  use ExUnit.Case, async: true

  alias CodeReviewer.RuleGroups

  describe "all/0" do
    test "returns all rule groups in priority order" do
      groups = RuleGroups.all()

      assert is_list(groups)
      assert length(groups) == 9

      # First group should be blocking issues (highest priority)
      assert hd(groups).name == "Blocking Issues"
      assert hd(groups).priority == :critical
    end

    test "each group has required fields" do
      for group <- RuleGroups.all() do
        assert is_binary(group.name)
        assert group.priority in [:critical, :high, :medium, :low]
        assert is_list(group.rules)
        assert length(group.rules) > 0
        assert is_binary(group.context)
      end
    end
  end

  describe "blocking_issues/0" do
    test "returns blocking issues group" do
      group = RuleGroups.blocking_issues()

      assert group.name == "Blocking Issues"
      assert group.priority == :critical
      first_rule = Enum.at(group.rules, 0)
      assert first_rule =~ "N+1 queries"
    end

    test "includes all critical rules" do
      group = RuleGroups.blocking_issues()

      rule_text = Enum.join(group.rules, " ")

      assert rule_text =~ "N+1"
      assert rule_text =~ "schema changes"
      assert rule_text =~ "Magic numbers"
      assert rule_text =~ "ENV variables"
      assert rule_text =~ "system specs"
      assert rule_text =~ "callbacks"
      assert rule_text =~ "Rescuing"
    end
  end

  describe "testing_strategy/0" do
    test "emphasizes TDD and minimal mocking" do
      group = RuleGroups.testing_strategy()

      rule_text = Enum.join(group.rules, " ")

      assert rule_text =~ "TDD"
      assert rule_text =~ "red-green-refactor"
      assert rule_text =~ "minimal mocking"
      assert rule_text =~ "fake HTTP servers"
      assert rule_text =~ "3 minutes"
    end
  end

  describe "code_organization/0" do
    test "emphasizes separation of concerns" do
      group = RuleGroups.code_organization()

      rule_text = Enum.join(group.rules, " ")

      assert rule_text =~ "Service objects"
      assert rule_text =~ "skinny"
      assert rule_text =~ "Business logic"
      assert rule_text =~ "Single responsibility"
    end
  end

  describe "rails_patterns/0" do
    test "includes callback hatred" do
      group = RuleGroups.rails_patterns()

      rule_text = Enum.join(group.rules, " ")

      assert rule_text =~ "HATE"
      assert rule_text =~ "callbacks"
      assert rule_text =~ "NO controller specs"
      assert rule_text =~ "ViewComponents"
    end
  end
end
