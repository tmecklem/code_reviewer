#!/bin/bash
set -e

echo "=== Installing mise ==="
if ! command -v mise &> /dev/null && [ ! -f "$HOME/.local/bin/mise" ]; then
    curl https://mise.run | sh
else
    echo "mise already installed, skipping..."
fi

# Add mise to PATH for this script
export PATH="$HOME/.local/bin:$PATH"

# Activate mise in current shell
eval "$(~/.local/bin/mise activate bash)"

# Add mise shims to PATH for non-interactive shells
export PATH="$HOME/.local/share/mise/shims:$PATH"

# Set up mise in bashrc (activation + shims path) if not already present
if ! grep -q "mise activate" ~/.bashrc 2>/dev/null; then
    echo 'export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"' >> ~/.bashrc
    echo 'eval "$(mise activate bash)"' >> ~/.bashrc
fi

echo "=== Installing tools from .tool-versions ==="
cd "$(dirname "$0")/.."
mise install

echo "=== Installing hex and rebar ==="
mise exec -- mix local.hex --force
mise exec -- mix local.rebar --force

echo "=== Installing dependencies ==="
mise exec -- mix deps.get

echo "=== Compiling application ==="
mise exec -- mix compile

echo "=== Post-create setup complete ==="
