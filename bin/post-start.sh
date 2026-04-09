#!/bin/bash
set -e

# Set up mise PATH and activate for this script
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"
eval "$(~/.local/bin/mise activate bash)"

echo "=== Checking gh authentication ==="
if [ -n "$GITHUB_TOKEN" ]; then
    echo "GITHUB_TOKEN found, authenticating gh CLI..."
    echo "$GITHUB_TOKEN" | gh auth login --with-token
    gh auth status
else
    echo "Warning: GITHUB_TOKEN not set. You'll need to authenticate manually."
fi

echo "=== Post-start setup complete ==="
