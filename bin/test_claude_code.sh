#!/bin/bash

# Test if Claude Code CLI supports ACP mode

echo "🔍 Testing Claude Code ACP Compatibility"
echo "========================================"
echo ""

# Find Claude Code
if [ -n "$CLAUDE_CODE_PATH" ]; then
    CLAUDE="$CLAUDE_CODE_PATH"
elif command -v claude-code &> /dev/null; then
    CLAUDE="claude-code"
elif command -v claude &> /dev/null; then
    CLAUDE="claude"
else
    echo "❌ Claude Code CLI not found!"
    echo ""
    echo "Please install Claude Code or set CLAUDE_CODE_PATH"
    exit 1
fi

echo "✓ Found Claude Code: $CLAUDE"
echo ""

# Check if it has help/version
echo "Testing Claude Code CLI..."
$CLAUDE --version 2>&1 | head -n 5 || true
echo ""

# Test ACP initialization
echo "Testing ACP protocol support..."
echo "Sending initialize message..."
echo ""

# Try to send an ACP initialize message
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{}}}' | timeout 2 $CLAUDE 2>&1 | head -n 10 || {
    echo ""
    echo "⚠️  No valid ACP response received"
    echo ""
    echo "This could mean:"
    echo "  1. Claude Code doesn't support ACP mode"
    echo "  2. It needs specific flags (try: $CLAUDE --help)"
    echo "  3. It needs authentication first"
    echo ""
}

echo ""
echo "If you see a JSON response above, Claude Code supports ACP!"
echo "If not, you may need to use OpenAI instead."
echo ""
echo "To use OpenAI:"
echo "  export OPENAI_API_KEY=\"sk-...\""
echo "  unset LLM_PROVIDER"
echo "  mix review owner/repo 123"
