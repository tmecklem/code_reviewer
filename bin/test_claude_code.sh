#!/bin/bash

# Test if Claude Code CLI works with --print mode

echo "🔍 Testing Claude Code CLI Compatibility"
echo "========================================"
echo ""

# Find Claude Code
if [ -n "$CLAUDE_CODE_PATH" ]; then
    CLAUDE="$CLAUDE_CODE_PATH"
elif command -v claude &> /dev/null; then
    CLAUDE="claude"
elif command -v claude-code &> /dev/null; then
    CLAUDE="claude-code"
else
    echo "❌ Claude Code CLI not found!"
    echo ""
    echo "Please install Claude Code or set CLAUDE_CODE_PATH"
    echo "  Install: npm install -g @anthropic-ai/claude-code"
    exit 1
fi

echo "✓ Found Claude Code: $CLAUDE"
echo ""

# Check version
echo "Testing Claude Code CLI..."
$CLAUDE --version 2>&1 | head -n 5 || true
echo ""

# Test --print mode
echo "Testing --print mode (non-interactive)..."
echo ""

# Try a simple prompt with --print
OUTPUT=$($CLAUDE --print "Say hello" --output-format json 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ Claude Code --print mode works!"
    echo ""
    echo "Sample output:"
    echo "$OUTPUT" | head -n 10
    echo ""
    echo "🎉 You can use Claude Code with CodeReviewer!"
    echo ""
    echo "To use it:"
    echo "  export GITHUB_TOKEN=\"ghp_...\""
    echo "  export LLM_PROVIDER=\"claude_code\""
    echo "  mix review owner/repo 123"
else
    echo "❌ Claude Code --print mode failed"
    echo ""
    echo "Error output:"
    echo "$OUTPUT" | head -n 10
    echo ""
    echo "This could mean:"
    echo "  1. You need to authenticate: $CLAUDE auth"
    echo "  2. Claude Code isn't installed properly"
    echo "  3. You need to use OpenAI instead"
    echo ""
    echo "To use OpenAI:"
    echo "  export OPENAI_API_KEY=\"sk-...\""
    echo "  unset LLM_PROVIDER"
    echo "  mix review owner/repo 123"
fi

echo ""
