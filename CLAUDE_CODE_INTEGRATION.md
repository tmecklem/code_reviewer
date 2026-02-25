# Claude Code Integration

CodeReviewer can use the Claude Code CLI's `--print` mode for AI-powered code reviews, providing an alternative to direct OpenAI API integration.

## How It Works

CodeReviewer calls the `claude` CLI with the `--print` flag for non-interactive, programmatic code reviews. This uses Claude Code's built-in support for automation and scripting, with structured JSON output via `--output-format json` and `--json-schema` for validated responses.

## Quick Start

### 1. Install Claude Code CLI

First, ensure you have the Claude Code CLI installed. Check if it's available:

```bash
which claude-code
# or
which claude
```

If not installed, set the path explicitly:

```bash
export CLAUDE_CODE_PATH="/path/to/claude-code"
```

### 2. Set Environment Variables

```bash
export GITHUB_TOKEN="ghp_your_github_token"
export LLM_PROVIDER="claude_code"  # Use Claude Code instead of OpenAI
```

Note: You don't need `OPENAI_API_KEY` when using Claude Code!

### 3. Run Reviews

```bash
# Review using Claude Code
mix review owner/repo 123

# Or post directly to GitHub
mix review owner/repo 123 --post
```

CodeReviewer will:
1. Call `claude --print` with your review prompt
2. Use `--json-schema` to enforce structured output
3. Parse the JSON response with findings
4. Format and display/post results

## How It Works

When you set `LLM_PROVIDER=claude_code`, CodeReviewer:

1. **Finds Claude CLI** - Locates `claude` command in PATH or `CLAUDE_CODE_PATH`
2. **Builds Review Prompt** - For each rule group, creates a focused prompt with:
   - Rule group context and rules
   - PR information (title, author, description)
   - Diff content
   - JSON schema for response validation
3. **Calls Claude** - Executes `claude --print <prompt> --output-format json --json-schema <schema>`
4. **Parses Response** - Extracts structured findings from JSON output
5. **Aggregates Results** - Combines findings from all rule groups
6. **Formats Output** - Uses OutputFormatter to create comments and summary

## Example Usage

```bash
# Set up environment
export GITHUB_TOKEN="ghp_..."
export LLM_PROVIDER="claude_code"

# Run a review
mix review tmecklem/equipment_tracker 1
```

Expected output:
```
🔍 Reviewing PR #1 in tmecklem/equipment_tracker...
Starting Claude Code at: /usr/local/bin/claude-code
Initialized Claude Code connection
Sending review prompt to Claude Code...

## Review Summary for Add new feature

I've reviewed the changes and have some feedback organized by priority.

### Issues Found
- **High**: 2 issues
- **Medium**: 3 issues

## 📝 Draft Comments (5)

📍 lib/app.ex:42
⚠️ High Issue
...
```

## Architecture

### Components

- **ClaudeCodeProvider**: Executes `claude --print` with review prompts and parses JSON responses
- **Reviewer**: Orchestrator that chooses between OpenAI or Claude Code based on `LLM_PROVIDER`
- **RuleGroups**: 9 focused rule groups for different review aspects
- **OutputFormatter**: Formats findings into GitHub-ready comments

### Command Flow

```
┌──────────────────┐
│  CodeReviewer    │
│  mix review      │
└────────┬─────────┘
         │
         ▼
   ┌──────────────────┐
   │ Reviewer         │
   │ (orchestrator)   │
   └────────┬─────────┘
            │
            ├─ LLM_PROVIDER=openai ────▶ OpenAI API (HTTP)
            │
            └─ LLM_PROVIDER=claude_code ▶ claude --print (CLI)
                                           │
                                           ▼
                                    Claude Code CLI
                                    - Reads prompt
                                    - Enforces JSON schema
                                    - Returns structured findings
```

## Implementation Details

### ClaudeCodeProvider API

```elixir
def review_code(rule_group, diff_content, pr_info) do
  with {:ok, claude_path} <- find_claude_code(),
       {:ok, prompt} <- build_review_prompt(rule_group, diff_content, pr_info),
       {:ok, result} <- call_claude_code(claude_path, prompt) do
    parse_response(result)
  end
end
```

### Calling Claude Code

The provider executes Claude Code CLI with `--print` mode:

```elixir
defp call_claude_code(claude_path, prompt) do
  args = [
    "--print",
    prompt,
    "--output-format", "json",
    "--json-schema", @json_schema,
    "--tools", "",  # Disable tools for safety
    "--dangerously-skip-permissions"  # Skip prompts (read-only operation)
  ]

  case System.cmd(claude_path, args) do
    {output, 0} -> parse_claude_output(output)
    {error, code} -> {:error, "Claude exited with code #{code}: #{error}"}
  end
end
```

### Environment Variables

- **`CLAUDE_CODE_PATH`** - Explicit path to Claude Code CLI (optional if in PATH)
- **`LLM_PROVIDER`** - Set to `"claude_code"` to use Claude Code instead of OpenAI
- **`GITHUB_TOKEN`** - Required for GitHub operations

## Testing the Integration

### Manual Test with OpenAI (Default)

```bash
export GITHUB_TOKEN="ghp_..."
export OPENAI_API_KEY="sk-..."
mix review owner/repo 123
```

### Test with Claude Code

```bash
export GITHUB_TOKEN="ghp_..."
export LLM_PROVIDER="claude_code"
export CLAUDE_CODE_PATH="/usr/local/bin/claude-code"  # if not in PATH

mix review owner/repo 123
```

### Verify Claude Code is Working

```bash
# Check if Claude CLI is available
which claude

# Test Claude CLI with --print mode
./bin/test_claude_code.sh

# Or test manually
claude --print "Say hello" --output-format json
```

## Troubleshooting

### Claude Code Not Found

**Problem**: "Claude Code CLI not found"

**Solution**:
1. Install Claude Code CLI from Anthropic
2. Ensure it's in your PATH: `which claude-code`
3. Or set explicitly: `export CLAUDE_CODE_PATH="/path/to/claude-code"`

### Claude Code Authentication Required

**Problem**: Claude CLI returns authentication errors

**Solution**:
1. Authenticate with Claude: `claude auth`
2. Verify authentication: `claude --print "hello" --output-format json`
3. Check your Claude Code subscription is active

### Claude Code Command Fails

**Problem**: "Claude Code exited with code X"

**Solution**:
1. Test Claude CLI works: `claude --version`
2. Try a simple test: `claude --print "Say hello" --output-format json`
3. Check Claude Code logs for errors
4. Ensure you have an active Claude subscription

**Workaround**: Use OpenAI instead:
```bash
export OPENAI_API_KEY="sk-..."
unset LLM_PROVIDER  # or set LLM_PROVIDER=openai
mix review owner/repo 123
```

### GitHub Authentication Fails

**Problem**: "gh command failed" errors

**Solution**:
1. Verify GITHUB_TOKEN is set and valid
2. Test `gh` CLI manually: `gh auth status`
3. Ensure token has `repo` scope

### OpenAI API Errors

**Problem**: "OPENAI_API_KEY environment variable not set"

**Solution**:
1. Set OPENAI_API_KEY: `export OPENAI_API_KEY="sk-..."`
2. Verify API key is valid
3. Check OpenAI account has credits

## Resources

- **Claude Code CLI Documentation**: https://code.claude.com/docs/en/headless
- **Claude Code --print mode guide**: https://code.claude.com/docs/en/headless
- **Claude Product Page**: https://claude.com/product/claude-code

## Development

To modify the Claude Code integration:

1. Edit `lib/code_reviewer/claude_code_provider.ex`
2. Update the JSON schema if needed (`@json_schema`)
3. Modify prompt building in `build_review_prompt/3`
4. Test with: `export LLM_PROVIDER=claude_code && mix review owner/repo 123`

The provider leverages all existing CodeReviewer functionality:
- `CodeReviewer.Reviewer` - Orchestration
- `CodeReviewer.GitHubClient` - PR data fetching
- `CodeReviewer.LLMClient` - OpenAI integration (alternative)
- `CodeReviewer.OutputFormatter` - Response formatting
