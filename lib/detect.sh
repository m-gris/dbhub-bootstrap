#!/usr/bin/env bash
# Detection functions. Read-only. Line-oriented output.
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

# missing_deps :: () -> line per missing dep (or empty)
missing_deps() {
    command -v brew >/dev/null || echo "brew"
    command -v gum  >/dev/null || echo "gum"
    command -v just >/dev/null || echo "just"
}

# dsns :: () -> line per DSN env var (VAR=value)
dsns() {
    env | grep -iE "$DSN_PATTERN" | grep -E '://' || true
}

# project_root :: () -> path
project_root() {
    git rev-parse --show-toplevel 2>/dev/null || pwd
}
