# Agent Client Protocol (ACP) Integration

CodeReviewer uses the [Agent Client Protocol (ACP)](https://agentclientprotocol.com/) to call Claude Code for AI-powered code reviews, providing an alternative to direct OpenAI API integration.

## What is ACP?

The Agent Client Protocol is a standardized JSON-RPC 2.0 based protocol for communication between code editors and AI coding agents. CodeReviewer acts as an ACP **client**, spawning Claude Code and sending it review requests via stdio.

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
1. Spawn Claude Code via ACP
2. Send review prompts for each rule group
3. Receive structured findings
4. Format and display/post results

## How It Works

When you set `LLM_PROVIDER=claude_code`, CodeReviewer:

1. **Spawns Claude Code** - Uses ACP to start the Claude Code CLI process
2. **Initializes Session** - Establishes protocol handshake and creates a conversation session
3. **Sends Review Prompts** - For each rule group, sends a focused review prompt with:
   - Rule group context and rules
   - PR information (title, author, description)
   - Diff content
   - Response format specification (JSON)
4. **Receives Responses** - Claude Code returns structured findings
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

- **ACPEx**: Elixir implementation of the Agent Client Protocol
- **ClaudeCodeClient**: Implements `ACPex.Client` behavior - responds to file/terminal requests from Claude Code
- **ClaudeCodeProvider**: High-level API for spawning Claude Code and sending review prompts
- **Reviewer**: Orchestrator that chooses between OpenAI or Claude Code based on `LLM_PROVIDER`

### Protocol Flow

```
┌──────────────────┐         ┌─────────────┐
│  CodeReviewer    │────────▶│ Claude Code │
│  (ACP Client)    │◀────────│ (ACP Agent) │
└──────────────────┘  stdio  └─────────────┘
   ClaudeCodeClient          JSON-RPC over stdio
         │
         │ spawns & manages
         ▼
   ┌──────────────────┐
   │ Reviewer         │
   │ ├─ RuleGroups    │
   │ ├─ GitHubClient  │ ──────▶ GitHub API (via gh)
   │ └─ Provider      │
   │    ├─ OpenAI     │ ──────▶ OpenAI API (direct)
   │    └─ Claude Code│ ──────▶ Claude Code (via ACP)
   └──────────────────┘
```

### Message Flow

1. **CodeReviewer → Claude Code**: `initialize` (protocol handshake)
2. **CodeReviewer → Claude Code**: `authenticate` (optional)
3. **CodeReviewer → Claude Code**: `new` (create session)
4. **CodeReviewer → Claude Code**: `prompt` (review request with rule group context)
5. **Claude Code → CodeReviewer**: File read requests (if needed)
6. **Claude Code → CodeReviewer**: Session updates (streaming thoughts/progress)
7. **Claude Code → CodeReviewer**: Prompt response (structured JSON with findings)

## Implementation Details

### ClaudeCodeProvider API

```elixir
def review_code(rule_group, diff_content, pr_info) do
  with {:ok, claude_path} <- find_claude_code(),
       {:ok, conn_pid} <- start_claude_code(claude_path),
       {:ok, session_id} <- initialize_session(conn_pid),
       {:ok, response} <- send_review_prompt(conn_pid, session_id, rule_group, diff_content, pr_info) do
    stop_claude_code(conn_pid)
    parse_response(response)
  end
end
```

### ClaudeCodeClient Callbacks

The client implements `ACPex.Client` behavior to respond to Claude Code's requests:

```elixir
@impl ACPex.Client
def handle_fs_read_text_file(%FsReadTextFileRequest{} = request, state) do
  case File.read(resolve_path(request.path, state.cwd)) do
    {:ok, content} ->
      response = %FsReadTextFileResponse{content: content}
      {:ok, response, state}
    {:error, reason} ->
      {:error, %{code: -32_001, message: "Failed to read file"}, state}
  end
end

@impl ACPex.Client
def handle_session_update(%UpdateNotification{} = notification, state) do
  # Collect streaming updates (thoughts, progress, tool calls)
  updated_state = %{state | updates: state.updates ++ [notification.update]}
  {:noreply, updated_state}
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
# Check if Claude Code CLI is available
which claude-code

# Test Claude Code directly
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1}}' | claude-code
```

## Troubleshooting

### Claude Code Not Found

**Problem**: "Claude Code CLI not found"

**Solution**:
1. Install Claude Code CLI from Anthropic
2. Ensure it's in your PATH: `which claude-code`
3. Or set explicitly: `export CLAUDE_CODE_PATH="/path/to/claude-code"`

### Claude Code Doesn't Support ACP

**Problem**: "Input must be provided either through stdin or as a prompt argument"

**Solution**: Your Claude Code CLI may not support ACP mode. This can happen if:
- You're using the wrong version of Claude Code
- Claude Code CLI doesn't have ACP support built-in
- You need to pass specific flags (e.g., `--acp`)

**Workaround**: Use OpenAI instead:
```bash
export OPENAI_API_KEY="sk-..."
unset LLM_PROVIDER  # or set LLM_PROVIDER=openai
mix review owner/repo 123
```

### Connection Initialization Fails

**Problem**: Timeout or error during `initialize_session`

**Solution**:
1. Verify Claude Code CLI works standalone
2. Check if it requires authentication first
3. Try starting it manually to see what arguments it expects

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

### No Response from Agent

**Problem**: Commands sent but no response received

**Solution**:
1. Check agent logs for errors
2. Verify JSON-RPC message format
3. Ensure session was created before sending prompts
4. Check that stdin/stdout aren't being buffered

## Resources

- **ACP Specification**: https://agentclientprotocol.com/
- **ACPex Library**: https://hexdocs.pm/acpex/
- **Tidewave ACP Integration**: https://tidewave.ai/blog/the-future-of-coding-agents-is-vertical-integration
- **Zed ACP Implementation**: https://github.com/zed-industries/claude-code-acp

## Development

To modify the ACP integration:

1. Edit `lib/code_reviewer/acp_agent.ex`
2. Implement additional `ACPex.Agent` callbacks as needed
3. Update command parsing in `parse_review_command/1`
4. Test with: `mix acp`

The agent leverages all existing CodeReviewer functionality:
- `CodeReviewer.Reviewer` - Orchestration
- `CodeReviewer.GitHubClient` - PR data fetching
- `CodeReviewer.LLMClient` - OpenAI integration
- `CodeReviewer.OutputFormatter` - Response formatting
