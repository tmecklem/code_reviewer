defmodule CodeReviewer.RuleGroups do
  @moduledoc """
  Defines rule groups for code review based on Tim's preferences.
  Each rule group will be evaluated separately with focused LLM calls.
  """

  @doc """
  Returns all rule groups in the order they should be evaluated.
  """
  def all do
    [
      blocking_issues(),
      testing_strategy(),
      code_organization(),
      database_and_performance(),
      api_design(),
      rails_patterns(),
      elixir_patterns(),
      error_handling(),
      code_quality()
    ]
  end

  @doc """
  Blocking issues that should always be caught.
  These are the highest priority and will fail the review if found.
  """
  def blocking_issues do
    %{
      name: "Blocking Issues",
      priority: :critical,
      rules: [
        "N+1 queries (almost always block - strong opinion, held loosely)",
        "Unrelated schema changes in PRs (re-ordering of columns, changes not in migrations)",
        "ActiveRecord models, Ecto structs, or app code entities referenced in point-in-time migrations",
        "Magic numbers/values without constants or descriptive names",
        "ENV variables read outside of initializers/configuration boundaries",
        "Excessive system specs for non-happy-path scenarios (should use request/model specs)",
        "ActiveRecord callbacks without Notification pattern (hate callbacks, prefer Saver classes)",
        "Rescuing exceptions in non-boundary code (should only rescue at controllers/service boundaries)"
      ],
      context: """
      You are reviewing code for BLOCKING ISSUES that should almost always prevent merge.
      Be strict about these rules - they represent strong technical opinions held by the reviewer.

      For each issue found:
      - Quote the exact code location
      - Explain why it's problematic
      - Suggest a specific fix

      Remember: N+1 is "strong opinion, held loosely" - if there's a good reason, acknowledge it.
      """
    }
  end

  def testing_strategy do
    %{
      name: "Testing Strategy",
      priority: :high,
      rules: [
        "MUST follow TDD (red-green-refactor) - tests should be written first",
        "System specs: minimum necessary, only for main paths and features resistant to lower tests",
        "Request specs: preferred for controllers (NO controller specs in Rails)",
        "Test through the database with real data - minimal mocking of owned code",
        "DO NOT mock/stub between layers of owned application code",
        "External APIs: prefer fake HTTP servers (Rack/Plug) over VCR",
        "Only mock: super-slow calculations, external APIs (with fakes)",
        "Test suite should run under 3 minutes ideally",
        "Setup code in `before` blocks, clear test intent in `it` blocks"
      ],
      context: """
      You are reviewing testing approach and test quality.

      Key philosophy:
      - Push tests down the hierarchy (system → request → model)
      - Real data over mocks for owned code
      - Fast test suite (under 3 minutes goal)
      - TDD workflow expected

      Check for:
      - System specs used for edge cases (should be request/model specs)
      - Excessive mocking of application code
      - VCR usage (prefer fake servers)
      - Tests not written first (if evident from commits)
      """
    }
  end

  def code_organization do
    %{
      name: "Code Organization",
      priority: :high,
      rules: [
        "Service objects for workflows crossing multiple resources or logical actions beyond CRUD",
        "Background jobs should be skinny - meat goes in services/classes",
        "Business logic belongs in models/services/modules, NOT in controllers/views",
        "Configuration objects (ActiveSupport::Configurable) for external integrations",
        "ENV variables only at boundary (initializers), never in application code",
        "Separation of concerns - UI logic separate from business logic",
        "Single responsibility principle for classes/modules",
        "Readable code > strict DRY - tolerate duplication if it improves readability"
      ],
      context: """
      You are reviewing code organization and architecture.

      Key principles:
      - Separation of concerns
      - Service objects for multi-resource operations
      - Skinny jobs, skinny controllers
      - Readability matters more than eliminating all duplication

      Look for:
      - Business logic in controllers/views (should be extracted)
      - Fat background jobs (logic should be in services)
      - ENV references outside initializers
      - Unnecessary abstraction that hurts readability
      """
    }
  end

  def database_and_performance do
    %{
      name: "Database & Performance",
      priority: :high,
      rules: [
        "N+1 queries almost always block (but context matters)",
        "Prefer ActiveRecord/Arel (Rails) or Ecto (Elixir) over raw SQL when possible",
        "NEVER reference AR models, Ecto structs in migrations (use raw SQL in migrations)",
        "Database indexes can be initial or later, minimize migrations reasonably",
        "Schema changes must be related to the PR's purpose"
      ],
      context: """
      You are reviewing database queries and performance.

      Critical rules:
      - No app code in migrations (will break when models change)
      - N+1 queries are usually a problem
      - Prefer ORM, but raw SQL in migrations is correct

      Check for:
      - N+1 patterns (missing includes/preloads)
      - Model references in migration files
      - Unrelated schema drift
      """
    }
  end

  def api_design do
    %{
      name: "API Design",
      priority: :medium,
      rules: [
        "Prefer REST conventions, but pragmatic deviations okay (/report vs /reports/show nesting)",
        "Use correct HTTP status codes",
        "Include helpful content in error responses",
        "Simple versioning - most APIs don't need complex versioning"
      ],
      context: """
      You are reviewing API design and HTTP conventions.

      Philosophy: Pragmatic REST
      - Follow REST when it makes sense
      - Don't force RESTful routes when awkward
      - Correct status codes matter
      - Helpful error messages
      """
    }
  end

  def rails_patterns do
    %{
      name: "Rails-Specific Patterns",
      priority: :high,
      rules: [
        "HATE ActiveRecord callbacks - only okay with Notification pub/sub pattern",
        "Prefer 'Saver' classes for orchestration over callbacks",
        "ActiveSupport Notification style pub/sub in callbacks is enjoyable (decouples listener)",
        "NO controller specs - only request specs",
        "Prefer ViewComponents over partials when functionality needed",
        "TurboStreamChannel for real-time updates using AR callback → Notification pub/sub",
        "No strong preference: scopes vs class methods"
      ],
      context: """
      You are reviewing Rails-specific patterns and conventions.

      Strong opinions:
      - Callbacks are bad (except Notification pattern)
      - Controller specs don't exist
      - ViewComponents > partials (when logic needed)

      The good callback pattern:
      - ActiveSupport::Notifications for pub/sub
      - Decouples callback from action
      - Similar to LiveView reactivity
      """
    }
  end

  def elixir_patterns do
    %{
      name: "Elixir/Phoenix Patterns",
      priority: :high,
      rules: [
        "LiveView whenever possible as default",
        "Contexts can be more granular than one-per-resource (within reason)",
        "Module attributes evaluated at compile-time - use defp for dynamic calculation",
        "No strong preference on specific Ecto patterns"
      ],
      context: """
      You are reviewing Elixir/Phoenix patterns.

      Preferences:
      - LiveView by default
      - Context granularity is flexible
      - Watch for compile-time vs runtime issues with module attributes
      """
    }
  end

  def error_handling do
    %{
      name: "Error Handling & Logging",
      priority: :medium,
      rules: [
        "Fail fast whenever possible",
        "Exception: batch operations (CSV uploads) - accumulate errors, present list, allow choice",
        "Rescue at boundaries only (controllers, external service calls)",
        "Rescuing elsewhere usually a code smell",
        "Logging is case-by-case, no strict rules",
        "Too much logging: whatever makes it hard to see big picture"
      ],
      context: """
      You are reviewing error handling and logging.

      Philosophy:
      - Fail fast (except batch operations)
      - Rescue at boundaries only
      - Pragmatic logging

      Look for:
      - Exception rescuing deep in application code
      - Lack of error accumulation in batch operations
      - Overly verbose logging
      """
    }
  end

  def code_quality do
    %{
      name: "Code Quality",
      priority: :medium,
      rules: [
        "Self-documenting code preferred: good names, clear structure, short methods",
        "Comments only for 'why' when needed, not 'what'",
        "Confusing variable names should be fixed",
        "Careful nil/blank handling (present? is true for false)",
        "Security awareness (OWASP patterns, information leakage)",
        "No magic numbers - use constants or descriptive names"
      ],
      context: """
      You are reviewing code quality and readability.

      Preferences:
      - Self-documenting code > comments
      - Clear naming
      - Short functions/methods
      - Single responsibility
      - Security conscious

      Watch for:
      - Magic numbers/strings
      - Confusing variable names
      - Unnecessary comments explaining obvious code
      - Security anti-patterns
      """
    }
  end
end
