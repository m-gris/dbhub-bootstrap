#!/usr/bin/env bash
# Side effects. Each function does ONE thing.
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

# install :: pkg -> ()
install() { brew install "$1" || { echo "FAIL: brew install $1" >&2; exit 1; }; }

# clone_repo :: () -> ()
clone_repo() {
    [[ -d "$INSTALL_DIR" ]] && return 0
    git clone "$REPO_URL" "$INSTALL_DIR" || { echo "FAIL: clone" >&2; exit 1; }
}

# write_file :: path content -> ()
write_file() { printf '%s\n' "$2" > "$1" || { echo "FAIL: write $1" >&2; exit 1; }; }

# register_mcp :: config_path -> ()
register_mcp() {
    claude mcp remove "$MCP_NAME" 2>/dev/null || true
    claude mcp add "$MCP_NAME" -- npx -y "${MCP_PACKAGE}@${MCP_VERSION}" --transport stdio --config "$1"
}

# gitignore_add :: path entry -> ()
gitignore_add() {
    [[ -f "$1" ]] || return 0  # No gitignore, skip silently
    grep -qxF "$2" "$1" || echo "$2" >> "$1"
}
