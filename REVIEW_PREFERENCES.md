# Tim's Code Review Preferences

**Generated:** 2026-02-03
**Based on:** 1,241 comments across 392 PRs (2021-2026)

## Key Findings Summary

### Testing Philosophy

#### 1. **Push Tests Down the Hierarchy**
*Pattern found in 3 comments, strong conviction*

**DEFINITIVE RULES:**

**System Specs:**
- **Minimum necessary** - only for main paths through the application
- Only for features that are absolutely resistant to lower-level tests
- **Goal:** Test suite should run under 3 minutes ideally (not possible with comprehensive system specs)

**Request Specs:**
- Preferred for testing controllers in Rails (**NO controller specs**)
- Use for edge cases, error handling, and non-happy-path scenarios
- Test through the database (real data, not mocks)

**Model/Service Specs:**
- For business logic and data validation
- Test through the database

**Your own words:**
> "There should be a minimum of system tests, just enough to exercise the main paths through the application and to test anything that's just absolutely resistant to lower tests. The test suite should run very quickly, ideally under 3 minutes, which isn't possible with comprehensive system specs. Test models and requests through the database."

> "We do not write controller specs in Rails. Only request specs."

> "I have to constantly tell Cursor to push the system tests lower. There must be a huge body of unfortunate and slow system specs out there, because it's the thing I fight about the most with Cursor by far. I think we need some cursor rules about it. We're already slowing the spec runs down quite a bit from non-happy path system specs that could easily be request or model specs."

#### 2. **Minimal Mocking - Prefer Real Data**
*Pattern found in 5 comments*

**DEFINITIVE RULES:**

**DO NOT mock/stub between layers of your own application**
- Use real objects and real database data
- Let the full stack execute

**DO mock:**
- Super-slow calculations (if unavoidable)
- External APIs - BUT use fake HTTP servers, not VCR

**External API Testing Strategy:**
- **Prefer:** Stand up a fake HTTP server (Rack in Ruby, Plug in Elixir)
- Have it return realistic HTTP responses based on captured data from the real API
- Fake should be dynamic enough to handle basic scenarios like the real API
- **Avoid:** VCR (if it's established pattern, fine, but not preferred)

**Your own words:**
> "Test models and requests through the database. If there's an external API, prefer standing up a fake server (eg rack or plug) and have it return realistic HTTP responses based on captured data from the real API. Super-slow calculations can be mocked, but generally do not mock or stub between layers of the application that we own."

> "I do not like VCR. If it's an established pattern, fine. But my preference is for an actual http server fake that can do some basic dynamic things like the real external API."

> "I don't like all the mocking of this data at all. It should just use real data since that's fast enough and a better test of the actual behavior of the system."

> "I prefer to just use the real thing for this kind of test. Claude likes to mock. A lot."

#### 3. **TDD Workflow**

**DEFINITIVE RULE:**
- **Always TDD** in the traditional red-green-refactor sense
- Write failing test first
- Make it pass
- Refactor

**Your own words:**
> "I prefer to TDD everything, in the traditional red green refactor sense."

#### 4. **Test Organization & Clarity**
*Pattern found in multiple comments*

**Your own words:**
> "This should be in a before. It detracts from the tests communication of intent in the it block."

You value:
- Setup code in `before` blocks
- Clear test intent in `it` blocks
- Good test coverage for edge cases
- Testing error cases explicitly

### Code Organization

#### 1. **Separation of Concerns**
*Very strong pattern - 162 organization-related comments*

You consistently advocate for proper layering:
- **Business logic** → Models, services, or dedicated modules (NOT in controllers/views)
- **External integrations** → Service objects with configuration
- **UI logic** → Keep separate from business logic

**Your own words:**
> "Business logic like this belongs somewhere other than the UI code layer. Either in an existing context function, perhaps in a schema module, or in a separate new module dedicated to it. It's kind of hidden here."

#### 2. **Service Objects for Complex Operations**

**WHEN TO CREATE A SERVICE OBJECT:**
- When the workflow crosses multiple resources
- When encapsulating a logical action in the application (beyond a single resourceful CRUD action)
- For easier testing (can be tested in isolation)

**WHEN NOT TO CREATE A SERVICE OBJECT:**
- Single resource CRUD operations (keep in model/controller)

**Configuration:**
- Use configuration objects (`ActiveSupport::Configurable`)
- Environment-based configuration in initializers

**Your own words:**
> "Service object when the workflow crosses multiple resources or encapsulates a logical action in the application over a single resourceful CRUD action."

> "Extract the job code to services if needed for easier testing."

#### 3. **Environment Variable Handling**

**DEFINITIVE RULE:**
- ENV variables should **ONLY** be read at the boundary (in initializers)
- **NEVER** read ENV directly in application code
- Use configuration objects instead

**Your own words:**
> "ENV variables should only be read at the boundary (eg in the initializers), not in the application code."

#### 4. **Background Jobs**

**DEFINITIVE RULE:**
- Jobs should be "skinny"
- The meat of the job's work should be in a separate service or class/module
- Single responsibility principle applies

**Your own words:**
> "I prefer jobs to be 'skinny' and for the meat of the job's work to be in a separate service or class/module with a single responsibility."

#### 5. **DRY Principle - With Nuance**

**DEFINITIVE RULE:**
- Don't like duplication
- **BUT** can tolerate it when the tradeoff is less readable code
- Readability > Strict DRY

**Your own words:**
> "I do not like duplication, but I can tolerate it when the tradeoff is less readable code."

#### 6. **Refactoring Philosophy**
You identify refactoring opportunities but often defer them:

**Your own words:**
> "I'd propose we do that in followup work... (We're in a time crunch, and that seems useful as separate work anyway)"

> "Feel free to ignore either of these in the interest of time or disagreement or 'I just don't want to, Tim'."

**This shows pragmatism:** Perfect is the enemy of done, but technical debt should be acknowledged.

### Code Quality Standards

#### 1. **Database Schema Changes**

**DEFINITIVE RULE:**
- Unrelated schema changes should be removed from PRs
- This includes:
  - Re-ordering of columns not addressed in the migration
  - Schema changes not part of the PR's purpose
  - Auto-generated schema drift

**Your own words:**
> "Unrelated schema changes (re-ordering of columns and changes not addressed in migrations) should be removed from the PR"

#### 2. **No Magic Numbers/Values**
*Consistent enforcement*

**Your own words:**
> "these magic numbers aren't great. Either refactor the magic bookingType numbers to a helper method, or define them somewhere instead of using them as integer strings in the view."

#### 3. **Naming Matters**
You call out confusing variable names:

**Your own words:**
> "I would expect hasNoReceiptLineItems to be false (or the variable name to be changed to remove the `No`) in the case where there _are_ ReceiptLineItems."

#### 4. **Nil Handling**
You're careful about nil/blank edge cases:

**Your own words:**
> "present is true for false, had to change it to a nil check here and a few other places further along this chain."

#### 5. **Security Awareness**
You catch security issues:

**Your own words:**
> "I think there's a security concern with how we have passwordless implemented... it potentially leaks who has signed up for the service... OWASP reference: [link]"

### Database & Performance

#### 1. **N+1 Queries**

**DEFINITIVE RULE:**
- Almost always block the PR
- **Strong opinion, held loosely** (context matters)

**Your own words:**
> "N+1 is almost always a block, but it's a strong opinion held loosely"

#### 2. **Raw SQL vs ORM**

**DEFINITIVE RULE:**
- **Prefer:** ActiveRecord/Arel (Rails) or Ecto (Elixir) when possible
- **CRITICAL EXCEPTION:** **NEVER** reference an ActiveRecord model, Ecto struct, or other app code entity in a point-in-time migration
  - This is a recipe for headaches
  - Migrations should use raw SQL or only reference schema primitives

**Your own words:**
> "Prefer ActiveRecord or arel when possible, same for ecto and others. Big caveat is *never reference an ActiveRecord model, Ecto struct, or other app code entity in a point in time migration*. This is a recipe for headaches."

#### 3. **Database Indexes**

**No strong preference:**
- Can be added in the initial schema change
- Can be added later as needed
- Minimize migrations reasonably

**Your own words:**
> "Database indexes can be added in the initial schema change or later as needed. No preference other than minimizing migrations reasonably."

### API Design

#### 1. **REST Conventions**

**DEFINITIVE RULE:**
- **Prefer REST** as default
- Pragmatic deviations are okay (e.g., `/report` rather than forcing `/reports/show` nesting just to be RESTful)
- Use correct HTTP status codes
- Include content in error responses when helpful

**Your own words:**
> "Prefer REST, but okay with other things like /report rather than /reports/show nesting just to get RESTful"

> "Prefer correct HTTP status code responses, content if needed even in the error ones"

#### 2. **API Versioning**

**No strong preference:**
- Simple is better
- Most APIs don't need complex versioning

**Your own words:**
> "no preference on versioning strategy for APIs. Simple is better. Most APIs don't need complex versioning."

---

### Rails-Specific Patterns

#### 1. **ActiveRecord Callbacks - STRONG DISLIKE**

**DEFINITIVE RULE:**
- **HATE callbacks in ActiveRecord**
- Okay only under very specific circumstances
- **Prefer:** "Saver" classes that handle orchestration of events and pub/sub

**EXCEPTION - The Good Pattern:**
- ActiveSupport Notification style of pub/sub in a callback
- This decouples the callback from the listener and action performed
- **Enjoyable pattern** - similar to LiveView's reactivity

**Your own words:**
> "Hate callbacks in AR. Okay under very specific circumstances, but prefer the concept of 'Saver' classes that handle orchestration of events and pub sub. The one caveat to this is the newer ActiveSupport Notification style of pub sub in a callback. This decouples the callback from the listener and action performed and is an enjoyable pattern"

#### 2. **Scopes vs Class Methods**

**No strong preference**

**Your own words:**
> "No preference on scopes vs class methods"

#### 3. **ViewComponents vs Partials**

**DEFINITIVE RULE:**
- **Prefer ViewComponents** in most cases where there might be functionality alongside the view to encapsulate

**Your own words:**
> "Prefer viewcomponents in most cases where there might be functionality alongside the view to encapsulate"

#### 4. **Hotwire/Turbo Patterns**

**Real-time Updates:**
- Prefer TurboStreamChannel when an update needs to be real-time to the user
- Use the AR callback to Notification pub/sub style (makes it like LiveView)

**Concerns about Direct Model Broadcasting:**
You have reservations about tight coupling in direct Hotwire patterns:

**Your own words:**
> "I'm not a super big fan of these kinds of direct broadcasts from the model... my brain melts with the whole conflation of concerns and tight coupling of model to its representation. I much prefer the active support Notification as a pub sub mechanism."

> "In Rails prefer TurboStreamChannel whenever an update needs to be realtime to the user, using the AR callback to Notification pubsub style that makes it like LiveView."

---

### Elixir/Phoenix-Specific Patterns

#### 1. **LiveView - Strong Preference**

**DEFINITIVE RULE:**
- **LiveView whenever possible as a default**

**Your own words:**
> "LiveView whenever possible as a default."

#### 2. **Phoenix Contexts**

**No strong preference on granularity:**
- Likes a little more than "one per resource" within reason

**Your own words:**
> "no preference on context granularity. I think I like a little more than 'one per resource' within reason."

#### 3. **Ecto Patterns**

**No strong preference**

**Your own words:**
> "no preference on ecto patterns."

#### 4. **Module Attributes**

**Technical correctness:**
- Module attributes are evaluated at compile-time
- Should be in a defp or somewhere else that will be dynamically calculated each time it is called

**Your own words:**
> "Module attributes are evaluated at compile-time... This should be in a defp or somewhere else that will be dynamically calculated each time it is called."

### Development Environment

#### 1. **Low-Config Development**
You value minimal setup for new developers:

**Your own words:**
> "Goal of the fake is to have as close to a zero config dev environment that's still realistic."

> "my default is to minimize the number of external keys and services needed for a new dev to the project to get up and running."

#### 2. **Cross-Platform Support**
**Your own words:**
> "I want non-linux environments to still work without the dev container... I don't care about native Windows support though, since WSL is the way to go there."

---

## Review Tone & Style

### Tone Distribution (814 comments analyzed)
- **Directive** (168 instances): "should", "must", "need to"
- **Positive** (118 instances): "nice", "good", "great", "love"
- **Questioning** (87 instances): Using questions to prompt thinking
- **Suggestive** (64 instances): "could", "might", "consider"
- **Cautionary** (12 instances): "concern", "worry", "careful"

### Common Opening Phrases
1. "This looks good to me" (9x)
2. "Looks good overall" (7x)
3. "This looks good" (6x)
4. "Good work overall" (2x)
5. "This is great" (2x)

### Review Style Characteristics

**1. You balance positive feedback with constructive criticism:**
- Start with "looks good" or similar
- Then provide specific improvement suggestions
- Often close with approval or "this is fine for now"

**2. You're pragmatic about technical debt:**
- Acknowledge when things aren't ideal but are "good enough"
- Suggest refactoring in follow-up work
- Give explicit permission to defer improvements

**3. You call out AI-generated code patterns:**
- Note when Claude/Cursor has over-engineered
- Identify when AI has added unnecessary mocking
- Question patterns that seem AI-driven rather than intentional

---

## Error Handling & Observability

### 1. **Error Handling Philosophy**

**DEFINITIVE RULE:**
- **Fail fast whenever possible**
- **Exception:** For batch operations (e.g., large CSV upload), prefer accumulating validation errors and presenting them as a list to the user, allowing choice to proceed

**Your own words:**
> "Fail fast whenever possible. For something like a large CSV upload, prefer accumulating validation or errors and presenting them as a list to the user and allowing choice to proceed."

### 2. **Rescuing Exceptions**

**DEFINITIVE RULE:**
- **Rescue at the boundaries** (in controllers, in service calls to external services)
- Rescuing in other application code is **usually a smell**

**Your own words:**
> "Rescue at the boundaries (eg in controllers or in service calls to external services). Rescuing in other application code is usually a smell."

### 3. **Error Messages**

**No strong preference:**
- Case by case for user-facing vs internal error messages

**Your own words:**
> "no preference on error messages"

### 4. **Logging**

**DEFINITIVE RULE:**
- **Case by case** - no blanket rules on what to log
- **Too much logging:** Whatever makes it hard to see the big picture
- **No preference** on structured logging format

**Your own words:**
> "logging is a case by case"
> "no preference on logging structure"
> "too much logging is whatever makes it hard to see the big picture"

---

## Documentation & Communication

### 1. **Code Comments**

**DEFINITIVE RULE:**
- **Prefer self-documenting code:** Good names and clear, concise structure
  - Short functions/methods
  - Classes/modules with single responsibility
- **Comments only as necessary** where the "why" of a thing needs to be conveyed
- **No preference** on inline vs method/class documentation style

**Your own words:**
> "prefer code to be self-documenting with good names and clear concise structure (short functions/methods, classes/modules with single responsibility). Comments only as necessary where the 'why' of a thing needs to be conveyed."

> "no preference on inline vs method/class"

### 2. **Pull Request Descriptions**

**DEFINITIVE RULE:**
- Explain **why** and **tradeoffs**
- Include an **executive summary** that lets someone skip the rest if in a hurry and not the primary reviewer
- Checklists are fine
- Keep it **concise**

**Your own words:**
> "PR description should explain why and tradeoffs. Checklists are fine. Concise with a good executive summary that lets someone skip the rest if in a hurry and not primary reviewer"

### 3. **Test Plans in PRs**

**DEFINITIVE RULE:**
- Only needed if **not automated** in the PR
- Rarely needed (testing should be automated)

**Your own words:**
> "Test plan only needed if not automated in the PR (rarely needed)"

### 4. **Git Commit Messages**

**DEFINITIVE RULE:**
- **Semantic commits** in imperative mood
- Format: "(If committed this commit will) [verb] [what]"
- Example: "Change user_role from column to join table"

**Your own words:**
> "semantic git commits: (If committed this commit will) 'Change user_role from column to join table' etc"

### 5. **Git History**

**DEFINITIVE RULE:**
- **Rebase and squash are friends**
- **Linear git history preferred**

**Your own words:**
> "Rebase and squash are friends. Linear git history preferred."

---

## Summary: High-Priority Review Focuses

Based on analysis of 1,241 comments and interview, these are your top concerns:

### 🚨 Always Check (Blocking Issues)
1. **N+1 queries** (almost always block)
2. **Unrelated schema changes** in PRs
3. **AR models/Ecto structs referenced in migrations** (recipe for headaches)
4. **Magic numbers/values** without constants
5. **ENV variables** read outside of initializers
6. **Excessive system specs** for non-happy-path scenarios
7. **ActiveRecord callbacks** (without Notification pattern)
8. **Rescuing exceptions** in non-boundary code

### ✅ Strong Preferences
1. **TDD everything** (red-green-refactor)
2. **Test through the database** (minimal mocking of owned code)
3. **Fake HTTP servers** for external APIs (not VCR)
4. **Skinny background jobs** (logic in services)
5. **Service objects** for multi-resource operations
6. **ViewComponents** over partials (when functionality needed)
7. **LiveView** as default (Phoenix)
8. **Self-documenting code** over comments
9. **Linear git history** (rebase/squash)

### 🤔 Context-Dependent
1. **Duplication** (okay if it improves readability)
2. **Technical debt** (acknowledge but pragmatic about deferring)
3. **Database indexes** (initial PR or later, minimize migrations)
4. **REST deviations** (pragmatic, not dogmatic)

### 😊 Tone
- Start positive ("looks good")
- Be directive about issues ("should", "must")
- Ask questions to prompt thinking
- Give permission to defer ("feel free to ignore in the interest of time")
- Call out AI over-engineering
