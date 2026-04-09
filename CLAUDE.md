# Claude Code Review System - Critical Requirements

## ABSOLUTE REQUIREMENTS - NO EXCEPTIONS

### 1. MCP Tools MUST Work
- **NO FALLBACK TO BASH**: The review agent must use MCP tools exclusively
- The `git_diff` MCP tool must work on first attempt - no recovery via Bash commands
- If MCP tools fail, the review must fail - do not work around with Bash
- Ensure proper git branch setup so `git diff base...head` works immediately

### 2. Test-Driven Development (TDD)
- **Write tests FIRST, then implementation**
- Every feature must have tests before coding
- Mock all external dependencies (GitHub API, ACP binary, etc.)
- Integration tests must use mocks - NO skipping with `:integration` tag
- All tests MUST pass - no "acceptable failures"

### 3. Test Suite Requirements
- **100% of tests must pass** - no exceptions
- Mock the ACP binary properly for all tests
- Mock GitHub API calls - never make real API requests in tests
- Fix the 4 failing tests in ACPClientTest and ResilientGitHubPostingTest
- Remove all `:skip` and `:integration` exclusion tags

### 4. Docker Requirements
- Dockerfile must properly build and run
- Must pass through all required environment variables:
  - `GITHUB_TOKEN`
  - `OPENAI_API_KEY` (when using OpenAI)
  - `CLAUDE_CODE_PATH`
  - MCP server configuration
- Must mount necessary volumes for Claude settings
- Production and development Dockerfiles must both work

### 5. Process Management
- **NEVER run review commands without explicit permission**
- Do not leave background processes running
- Always check for running processes before starting new ones
- Clean up all processes when done

## Current Issues to Fix

### MCP Tool Issues
1. Git branches not properly set up in cloned repos
   - Both base and head branches must exist locally
   - Use `git checkout -B branch origin/branch` for both
   - Verify with `git branch -a` that both exist

2. MCP server configuration
   - Fix the "Invalid params" error for HTTP type MCP servers
   - Ensure proper JSON-RPC communication
   - Add proper error handling for MCP tool failures

### Test Failures to Fix
1. **ResilientGitHubPostingTest** - Making real API calls instead of using mocks
2. **ACPClientTest::send_additional_prompt** - Port mock not working (ArgumentError: not a port)
3. **ACPClientTest::run_persistent_session** - MCP server params validation failing
4. Integration tests being skipped - need proper mocks

### Architecture Requirements
1. **Single ACP Session**
   - One session for ALL rule groups
   - Reuse session with `send_additional_prompt`
   - Do NOT create 9 separate sessions

2. **MCP Feedback Accumulator**
   - Deduplication by file:line
   - ETS table for state management
   - Clear feedback at start of review

3. **Resilient GitHub Posting**
   - Try inline comments individually
   - Collect failures for PR-level comment
   - Include failed comments in summary with proper formatting

4. **Temperature Control**
   - Set to 0.2 for consistency
   - Avoid hallucinations in reviews

## Implementation Checklist

- [ ] Fix git branch setup in `clone_repo_internal`
- [ ] Fix MCP server HTTP configuration
- [ ] Create proper mocks for all GitHub API calls
- [ ] Create proper mocks for ACP binary Port operations
- [ ] Fix the 4 failing tests
- [ ] Remove all `:skip` tags from tests
- [ ] Create mocked integration tests (not skipped)
- [ ] Verify Docker builds and runs correctly
- [ ] Test environment variable pass-through in Docker
- [ ] Document all MCP tools and their expected behavior

## Testing Strategy

### Unit Tests
- Mock all external dependencies
- Test each module in isolation
- Use Mox for behavior-based mocks

### Integration Tests (Mocked)
- Mock the entire review flow
- Mock ACP binary responses
- Mock GitHub API responses
- Mock MCP server responses
- Verify complete workflow

### No Real External Calls
- No real GitHub API calls
- No real ACP binary execution in tests
- No real network requests
- All tests must be deterministic

## Docker Configuration

```dockerfile
# Required environment variables
ENV GITHUB_TOKEN=""
ENV CLAUDE_CODE_PATH="/usr/local/bin/claude"
ENV MCP_PORT="4567"

# Required volumes
VOLUME /root/.claude  # Claude settings
VOLUME /app/.claude   # App-specific settings

# Required build args
ARG MIX_ENV=prod
```

## MCP Tool Specifications

### git_diff
- **Purpose**: Get diff between branches
- **Required**: Both branches must exist locally
- **Parameters**: `{"ref1": "base", "ref2": "head", "three_dot": true}`
- **No fallback**: Must work or fail completely

### add_feedback
- **Purpose**: Add review feedback with deduplication
- **Parameters**: severity, file, line, issue, suggestion, quote
- **Deduplication**: By file:line combination

### get_feedback
- **Purpose**: Retrieve accumulated feedback
- **Returns**: All unique feedback entries

### clear_feedback
- **Purpose**: Clear feedback at start of review
- **Must be called**: At beginning of each review session

## NEVER DO
1. Run `mix review` without permission
2. Leave background processes running
3. Skip tests or accept failures
4. Use Bash as fallback for MCP tools
5. Make real API calls in tests
6. Create multiple ACP sessions per review
7. Ignore Docker configuration issues
8. Implement without tests first (TDD)

## ALWAYS DO
1. Write tests BEFORE implementation
2. Mock all external dependencies
3. Ensure all tests pass
4. Use MCP tools exclusively (no Bash fallback)
5. Clean up processes when done
6. Verify Docker configuration
7. Use single ACP session for entire review
8. Set temperature to 0.2