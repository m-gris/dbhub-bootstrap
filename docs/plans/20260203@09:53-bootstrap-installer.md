# Plan: Bootstrap Installer for mcp-db

## Goal

Plug-and-play onboarding for Claude Code database access.

**Entry point:**
```bash
curl -fsSL https://raw.githubusercontent.com/m-gris/mcp-db/main/bootstrap.sh | bash
```

---

## Structure

```
~/.mcp-db/                     # Installed by bootstrap
├── lib/
│   ├── config.sh              # Constants only
│   ├── detect.sh              # Read-only queries
│   ├── actions.sh             # Atomic effects
│   ├── ui.sh                  # Gum wrappers
│   ├── compute.sh             # Pure transforms
│   └── all.sh                 # Sources everything
├── bin/
│   ├── dbhub-init             # Init orchestration
│   ├── dbhub-status           # Status orchestration
│   └── dbhub-remove           # Remove orchestration
├── config/just/
│   └── dbhub.just             # Thin recipes (1-liners)
└── bootstrap.sh               # Installs prereqs
```

---

## Design Principles

```
DATA         → lib/config.sh     (constants, no logic)
DETECT       → lib/detect.sh     (read-only, line-oriented output)
COMPUTE      → lib/compute.sh    (pure transforms, string → string)
ACTIONS      → lib/actions.sh    (atomic effects, fail fast)
UI           → lib/ui.sh         (thin gum wrappers)
ORCHESTRATE  → bin/*             (compose the above)
RECIPES      → dbhub.just        (1-line calls to bin/)
```

Each file: **< 25 lines**. Each function: **1-4 lines**. One job.

---

## Files

### `lib/config.sh`
```bash
#!/usr/bin/env bash
# All configuration. No logic. Just data.

readonly INSTALL_DIR="$HOME/.mcp-db"
readonly REPO_URL="https://github.com/m-gris/mcp-db.git"

readonly MCP_NAME="dbhub"
readonly MCP_CONFIG=".dbhub.toml"
readonly MCP_PACKAGE="@bytebase/dbhub"
readonly MCP_VERSION="0.1.5"  # Pin for reproducibility

readonly DSN_PATTERN='(database_url|db_|dsn|connection_string)'
```

### `lib/detect.sh`
```bash
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
```

### `lib/actions.sh`
```bash
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
```

### `lib/ui.sh`
```bash
#!/usr/bin/env bash
# User interaction. Thin wrappers around gum.

confirm() { gum confirm "$1"; }
choose()  { gum choose --header "$1"; }
input()   { gum input --placeholder "$1"; }
spin()    { gum spin --title "$1" -- "${@:2}"; }
success() { gum style --border normal --padding "1 2" --foreground 2 "$@"; }
warn()    { gum style --foreground 3 "⚠ $1"; }
fail()    { gum style --foreground 1 "✗ $1" >&2; }
```

### `lib/compute.sh`
```bash
#!/usr/bin/env bash
# Pure functions. No I/O. String transforms only.
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

# toml :: dsn -> toml string
toml() {
    cat <<EOF
[[sources]]
id = "default"
dsn = "$1"

[[tools]]
name = "execute_sql"
source = "default"
readonly = true
max_rows = 1000
EOF
}

# mask_password :: dsn -> masked dsn
mask_password() { echo "$1" | sed -E 's|(://[^:]+:)[^@]+(@)|\1****\2|'; }

# config_path :: root_path -> path  (pure: takes input, no side effects)
config_path() { echo "$1/$MCP_CONFIG"; }
```

### `lib/all.sh`
```bash
#!/usr/bin/env bash
# Sources all libs. Use this in bin/ scripts.
_dir="$(dirname "${BASH_SOURCE[0]}")"
source "$_dir/config.sh"
source "$_dir/detect.sh"
source "$_dir/actions.sh"
source "$_dir/ui.sh"
source "$_dir/compute.sh"
```

### `bin/dbhub-init`
```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/all.sh"

root=$(project_root)
found=$(dsns)
[[ -n "$found" ]] && dsn=$(echo "$found" | choose "Select database:" | cut -d= -f2-) || dsn=$(input "postgresql://user:pass@host:5432/db")

path=$(config_path "$root")
toml "$dsn" > "$path"
gitignore_add "$root/.gitignore" "$MCP_CONFIG"
register_mcp "$path"

success "✅ Done!" "DSN: $(mask_password "$dsn")" "Config: $path" "" "Restart Claude Code, run /mcp to verify."
```

### `bin/dbhub-status`
```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/all.sh"

root=$(project_root)
path=$(config_path "$root")
echo "Project: $root"
[[ -f "$path" ]] && echo "Config:  $path" || echo "Config:  (none)"
claude mcp list 2>/dev/null | grep -q "$MCP_NAME" && echo "MCP:     registered" || echo "MCP:     not registered"
```

### `bin/dbhub-remove`
```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/all.sh"

claude mcp remove "$MCP_NAME" 2>/dev/null && echo "Removed: $MCP_NAME" || echo "Not registered"
```

### `bootstrap.sh`
```bash
#!/usr/bin/env bash
set -euo pipefail

# Bootstrap is self-contained until repo is cloned.
# Inline minimal dependencies, then delegate to libs.

INSTALL_DIR="$HOME/.mcp-db"
REPO_URL="https://github.com/m-gris/mcp-db.git"

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
```

### `config/just/dbhub.just`
```just
# dbhub - Database access for Claude Code

_bin := "$HOME/.mcp-db/bin"

# Initialize dbhub for current project
[no-cd]
init:
    {{_bin}}/dbhub-init

# Show current configuration
[no-cd]
status:
    {{_bin}}/dbhub-status

# Remove dbhub
remove:
    {{_bin}}/dbhub-remove
```

---

## Usage

```bash
# New user (nothing installed)
curl -fsSL https://raw.githubusercontent.com/m-gris/mcp-db/main/bootstrap.sh | bash

# After bootstrap
just -g mcp dbhub init      # set up database
just -g mcp dbhub status    # check config
just -g mcp dbhub remove    # clean up
```

---

## Verification

```bash
# Test libs independently
source lib/all.sh && missing_deps
source lib/all.sh && dsns
source lib/all.sh && toml "postgres://test@localhost/db"

# Test bin scripts
./bin/dbhub-status

# Test full flow
./bootstrap.sh
just -g mcp dbhub init
just -g mcp dbhub status
just -g mcp dbhub remove
```
