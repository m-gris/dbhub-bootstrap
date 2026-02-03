#!/usr/bin/env bash
set -euo pipefail

# Bootstrap is self-contained until repo is cloned.
# Inline minimal dependencies, then delegate to libs.

INSTALL_DIR="$HOME/.dbhub-bootstrap"
REPO_URL="https://github.com/m-gris/dbhub-bootstrap.git"

# --- Phase 1: Minimal inline detection (no libs yet) ---

missing_brew() { command -v brew >/dev/null || echo "brew"; }
missing_gum()  { command -v gum  >/dev/null || echo "gum"; }
missing_just() { command -v just >/dev/null || echo "just"; }

missing=$(missing_brew; missing_gum; missing_just)

echo "⚡ Claude Database Setup"
echo ""
if [[ -z "$missing" ]]; then
    echo "✓ All dependencies installed"
else
    echo "$missing" | while read -r d; do [[ -n "$d" ]] && echo "  ⏳ $d (will install)"; done
fi
echo ""

# Confirm (inline, no gum yet)
read -p "Proceed? [Y/n] " -n 1 -r
echo
[[ $REPLY =~ ^[Nn]$ ]] && exit 0

# --- Phase 2: Install prerequisites ---

install_if_missing() {
    command -v "$1" >/dev/null && return 0
    echo "Installing $1..."
    brew install "$1" || { echo "FAIL: brew install $1" >&2; exit 1; }
}

# Brew must exist (manual install if missing)
if ! command -v brew >/dev/null; then
    echo "Homebrew required. Install from https://brew.sh"
    exit 1
fi

install_if_missing gum
install_if_missing just

# --- Phase 3: Clone repo, then use libs ---

if [[ ! -d "$INSTALL_DIR" ]]; then
    gum spin --title "Cloning mcp-db..." -- git clone "$REPO_URL" "$INSTALL_DIR"
fi

# Now libs exist, source them
source "$INSTALL_DIR/lib/all.sh"

# --- Phase 4: Done ---

success "✅ Bootstrap complete!" "" "Run: just -g mcp dbhub init"
