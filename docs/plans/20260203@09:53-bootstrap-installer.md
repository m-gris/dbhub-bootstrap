# Plan: Add Bootstrap Installer to mcp-db

## Goal
Create a plug-and-play onboarding experience for colleagues to set up database access for Claude Code.

**Entry point:**
```bash
curl -fsSL https://raw.githubusercontent.com/m-gris/mcp-db/main/bootstrap.sh | bash
```

---

## Configuration (No Magic Values)

All configurable values live in `lib/config.sh`:

```bash
#!/usr/bin/env bash
# lib/config.sh - All configuration in one place
# Every "magic" value is defined here with clear documentation

# ══════════════════════════════════════════════════════════════
# PATHS
# ══════════════════════════════════════════════════════════════

readonly MCP_DB_INSTALL_DIR="$HOME/.mcp-db"
readonly JUST_CONFIG_DIR="$HOME/.config/just"
readonly JUST_CONFIG_FILE="$JUST_CONFIG_DIR/justfile"

# ══════════════════════════════════════════════════════════════
# EXTERNAL RESOURCES (pinned versions where possible)
# ══════════════════════════════════════════════════════════════

readonly REPO_URL="https://github.com/m-gris/mcp-db.git"
readonly REPO_BRANCH="main"

readonly BREW_INSTALLER_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"

# Pin dbhub version for reproducibility (update deliberately)
readonly DBHUB_PACKAGE="@bytebase/dbhub"
readonly DBHUB_VERSION="latest"  # TODO: pin to specific version for production

# ══════════════════════════════════════════════════════════════
# MCP SERVER CONFIG
# ══════════════════════════════════════════════════════════════

readonly MCP_SERVER_NAME="dbhub"
readonly MCP_CONFIG_FILENAME=".dbhub.toml"

# ══════════════════════════════════════════════════════════════
# DSN DETECTION
# ══════════════════════════════════════════════════════════════

# Pattern to find database-related env vars (case-insensitive)
readonly DSN_ENV_PATTERN='(database_url|db_url|db_connection|dsn|connection_string|postgres|mysql|mongodb)'

# Pattern to identify a DSN (must contain protocol)
readonly DSN_VALUE_PATTERN='://.*@'

# ══════════════════════════════════════════════════════════════
# DEFAULTS
# ══════════════════════════════════════════════════════════════

readonly DEFAULT_MAX_ROWS=1000
readonly DEFAULT_READONLY=true

# ══════════════════════════════════════════════════════════════
# REQUIRED DEPENDENCIES
# ══════════════════════════════════════════════════════════════

# Array of (name, install_cmd, verify_cmd)
declare -a REQUIRED_DEPS=(
    "gum:brew install gum:command -v gum"
    "just:brew install just:command -v just"
    "fzf:brew install fzf:command -v fzf"
)
```

---

## FP-Unix Design Philosophy

### The Problem with Monoliths

A typical bootstrap script mixes everything:
- Detection (what's installed?)
- Computation (what needs to happen?)
- I/O (user prompts)
- Effects (actual installation)

This is hard to test, debug, and maintain.

### The FP-Unix Way

```
┌─────────────────────────────────────────────────────────────┐
│  DATA          Pure values, no side effects                 │
│  ─────────────────────────────────────────────────────────  │
│  • Detection results (JSON/text)                            │
│  • Config templates                                         │
│  • DSN list from environment                                │
├─────────────────────────────────────────────────────────────┤
│  COMPUTATIONS  Pure functions: input → output               │
│  ─────────────────────────────────────────────────────────  │
│  • Parse DSN → structured data                              │
│  • Generate TOML from DSN                                   │
│  • Compute diff (current state → desired state)             │
├─────────────────────────────────────────────────────────────┤
│  ACTIONS       Effects at the edges, clearly marked         │
│  ─────────────────────────────────────────────────────────  │
│  • Install package                                          │
│  • Write file                                               │
│  • Register MCP                                             │
│  • User prompts                                             │
├─────────────────────────────────────────────────────────────┤
│  ORCHESTRATION Compose the above                            │
│  ─────────────────────────────────────────────────────────  │
│  • init = detect | compute | confirm | apply                │
└─────────────────────────────────────────────────────────────┘
```

### Benefits

- **Testable**: Run detection separately, inspect output
- **Debuggable**: `just -g mcp dbhub _detect-dsns` shows what it found
- **Composable**: Mix and match pieces
- **Idempotent**: Detection is read-only, actions are explicit

---

## Architecture

### File Structure

```
~/DATA_PROG/TYPSCRIPT/mcp-db/
├── src/                              # existing TypeScript
├── bootstrap.sh                      # NEW: curl entry point (thin orchestrator)
├── lib/                              # NEW: composable shell functions
│   ├── detect.sh                     # Detection functions (read-only)
│   ├── compute.sh                    # Pure transformations
│   ├── actions.sh                    # Effects (installs, writes)
│   └── ui.sh                         # User interaction (gum wrappers)
├── config/
│   └── just/
│       ├── mcp.just                  # Entry point (imports modules)
│       └── modules/
│           └── dbhub/
│               ├── mod.just          # Orchestration recipes
│               ├── _detect.just      # Detection recipes (private)
│               └── _actions.just     # Action recipes (private)
└── README.md
```

### Recipe Decomposition (config/just/modules/dbhub/mod.just)

```just
# dbhub - Database access for Claude Code
# All configuration comes from variables (no magic values in recipes)

# ══════════════════════════════════════════════════════════════
# CONFIGURATION (all "magic" values defined here)
# ══════════════════════════════════════════════════════════════

_config_filename := ".dbhub.toml"
_mcp_server_name := "dbhub"
_dbhub_package := "@bytebase/dbhub"
_dbhub_version := "latest"
_default_max_rows := "1000"

# DSN detection patterns
_dsn_env_pattern := "(database_url|db_url|db_connection|dsn|connection_string|postgres|mysql)"
_dsn_value_pattern := "://.*@"

# ══════════════════════════════════════════════════════════════
# DETECTION (read-only, outputs data, no side effects)
# ══════════════════════════════════════════════════════════════

# _detect-dsns :: () -> [String]
# Outputs newline-separated list of env vars containing DSNs
_detect-dsns:
    @env | grep -iE '{{_dsn_env_pattern}}' | grep -E '{{_dsn_value_pattern}}' || echo ""

# _detect-project-root :: () -> String
# Outputs the git root or current directory
_detect-project-root:
    @git rev-parse --show-toplevel 2>/dev/null || pwd

# ══════════════════════════════════════════════════════════════
# COMPUTATIONS (pure transforms: input → output)
# ══════════════════════════════════════════════════════════════

# _gen-toml :: String -> String
# Generates TOML config from DSN. Pure function.
_gen-toml dsn:
    #!/usr/bin/env bash
    cat <<TOML
[[sources]]
id = "default"
dsn = "{{dsn}}"

[[tools]]
name = "execute_sql"
source = "default"
readonly = true
max_rows = {{_default_max_rows}}
TOML

# _mask-password :: String -> String
# Masks password in DSN for safe display. Pure function.
_mask-password dsn:
    @echo "{{dsn}}" | sed -E 's|(://[^:]+:)[^@]+(@)|\1****\2|'

# ══════════════════════════════════════════════════════════════
# ACTIONS (side effects, explicit errors)
# ══════════════════════════════════════════════════════════════

# _write-config :: (path: String, content: String) -> () | Error
# Writes content to path. Fails loudly on error.
[no-cd]
_write-config path content:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! echo "{{content}}" > "{{path}}"; then
        echo "ERROR: Failed to write {{path}}" >&2
        exit 1
    fi
    echo "Created: {{path}}" >&2

# _register-mcp :: String -> () | Error
# Registers MCP server. Fails loudly on error.
_register-mcp config_path:
    #!/usr/bin/env bash
    set -euo pipefail

    # Validate input
    if [[ ! -f "{{config_path}}" ]]; then
        echo "ERROR: Config file does not exist: {{config_path}}" >&2
        exit 1
    fi

    # Remove existing (idempotent)
    claude mcp remove "{{_mcp_server_name}}" 2>/dev/null || true

    # Register
    if ! claude mcp add "{{_mcp_server_name}}" -- \
        npx -y "{{_dbhub_package}}@{{_dbhub_version}}" \
        --transport stdio \
        --config "{{config_path}}"; then
        echo "ERROR: Failed to register MCP server" >&2
        exit 1
    fi
    echo "Registered: {{_mcp_server_name}}" >&2

# _gitignore-ensure :: (path: String, entry: String) -> ()
# Ensures entry is in gitignore. Idempotent.
[no-cd]
_gitignore-ensure path entry:
    #!/usr/bin/env bash
    if [[ ! -f "{{path}}" ]]; then
        exit 0  # No gitignore, nothing to do
    fi
    if grep -qxF "{{entry}}" "{{path}}" 2>/dev/null; then
        exit 0  # Already present
    fi
    echo "{{entry}}" >> "{{path}}"
    echo "Added {{entry}} to {{path}}" >&2

# ══════════════════════════════════════════════════════════════
# PUBLIC API (orchestration)
# ══════════════════════════════════════════════════════════════

# Initialize dbhub for current project
[no-cd]
init:
    #!/usr/bin/env bash
    set -euo pipefail

    # 1. DETECT: Find project root and DSNs
    project_root=$(just -g mcp dbhub _detect-project-root)
    config_path="$project_root/{{_config_filename}}"
    gitignore_path="$project_root/.gitignore"

    dsns=$(just -g mcp dbhub _detect-dsns)

    # 2. INTERACT: Pick DSN or enter manually
    if [[ -n "$dsns" ]]; then
        if command -v gum >/dev/null 2>&1; then
            selected=$(echo "$dsns" | gum choose --header "Select database:")
        elif command -v fzf >/dev/null 2>&1; then
            selected=$(echo "$dsns" | fzf --prompt="Select database: ")
        else
            echo "Available DSNs:"
            echo "$dsns"
            read -rp "Enter variable name: " varname
            selected=$(env | grep "^$varname=")
        fi
        dsn=$(echo "$selected" | cut -d= -f2-)
    else
        if command -v gum >/dev/null 2>&1; then
            dsn=$(gum input --placeholder "postgresql://user:pass@host:5432/db")
        else
            read -rp "Enter DSN: " dsn
        fi
    fi

    # 3. COMPUTE: Generate config
    toml=$(just -g mcp dbhub _gen-toml "$dsn")

    # 4. ACT: Write config, update gitignore, register MCP
    just -g mcp dbhub _write-config "$config_path" "$toml"
    just -g mcp dbhub _gitignore-ensure "$gitignore_path" "{{_config_filename}}"
    just -g mcp dbhub _register-mcp "$config_path"

    # 5. DISPLAY: Success
    masked=$(just -g mcp dbhub _mask-password "$dsn")
    if command -v gum >/dev/null 2>&1; then
        gum style --border normal --padding "1 2" \
            "✅ Done!" "" \
            "DSN: $masked" \
            "Config: $config_path" "" \
            "Restart Claude Code, then run /mcp to verify."
    else
        echo "✅ Done!"
        echo "DSN: $masked"
        echo "Config: $config_path"
        echo "Restart Claude Code, then run /mcp to verify."
    fi

# Show current dbhub configuration
[no-cd]
status:
    #!/usr/bin/env bash
    project_root=$(just -g mcp dbhub _detect-project-root)
    config_path="$project_root/{{_config_filename}}"

    echo "Project: $project_root"
    if [[ -f "$config_path" ]]; then
        echo "Config:  $config_path"
        dsn=$(grep -E "^dsn" "$config_path" | cut -d'"' -f2)
        masked=$(just -g mcp dbhub _mask-password "$dsn")
        echo "DSN:     $masked"
    else
        echo "Config:  (not found)"
    fi

    if claude mcp list 2>/dev/null | grep -q "{{_mcp_server_name}}"; then
        echo "MCP:     registered"
    else
        echo "MCP:     not registered"
    fi

# Remove dbhub MCP server
remove:
    #!/usr/bin/env bash
    if claude mcp remove "{{_mcp_server_name}}" 2>/dev/null; then
        echo "Removed: {{_mcp_server_name}}"
    else
        echo "Not registered: {{_mcp_server_name}}"
    fi
```

### bootstrap.sh (Thin Orchestrator)

```bash
#!/usr/bin/env bash
# bootstrap.sh - thin orchestrator, delegates to lib/ functions
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source composable libraries
source "$SCRIPT_DIR/lib/detect.sh"
source "$SCRIPT_DIR/lib/compute.sh"
source "$SCRIPT_DIR/lib/actions.sh"
source "$SCRIPT_DIR/lib/ui.sh"

main() {
    # 1. DETECT current state
    local state=$(detect_all)

    # 2. COMPUTE what needs to be done
    local plan=$(compute_plan "$state")

    # 3. INTERACT: show plan, get confirmation
    ui_show_plan "$plan"
    ui_confirm "Proceed?" || exit 0

    # 4. ACT: execute the plan
    execute_plan "$plan"

    # 5. DISPLAY: success
    ui_success
}

main "$@"
```

### lib/detect.sh (Read-Only, Explicit Contracts)

```bash
#!/usr/bin/env bash
# lib/detect.sh - Detection functions (read-only, no side effects)
#
# CONTRACTS:
# - All functions are pure: same input → same output
# - All functions output to stdout only
# - No side effects (no writes, no network calls, no state changes)
# - Errors go to stderr with explicit exit codes

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

# ══════════════════════════════════════════════════════════════
# EXIT CODES (explicit, not magic numbers)
# ══════════════════════════════════════════════════════════════

readonly EXIT_SUCCESS=0
readonly EXIT_UNSUPPORTED_OS=10
readonly EXIT_MISSING_DEPENDENCY=11

# ══════════════════════════════════════════════════════════════
# DETECTION FUNCTIONS
# ══════════════════════════════════════════════════════════════

# detect_os :: () -> "Darwin" | "Linux" | fails
# Returns the OS name or fails with EXIT_UNSUPPORTED_OS
detect_os() {
    local os
    os=$(uname -s)
    case "$os" in
        Darwin|Linux) echo "$os" ;;
        *) echo "Unsupported OS: $os" >&2; return $EXIT_UNSUPPORTED_OS ;;
    esac
}

# detect_command :: String -> "installed" | "missing"
# Check if a command exists in PATH
detect_command() {
    local cmd="$1"
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "installed"
    else
        echo "missing"
    fi
}

# detect_dsns :: () -> [String]
# Returns newline-separated list of env vars containing DSNs
# Empty output is valid (no DSNs found)
detect_dsns() {
    env | grep -iE "$DSN_ENV_PATTERN" | grep -E "$DSN_VALUE_PATTERN" || echo ""
}

# detect_config_state :: () -> "missing" | "exists" | "configured"
# Check state of just config file
detect_config_state() {
    if [[ ! -f "$JUST_CONFIG_FILE" ]]; then
        echo "missing"
    elif grep -qF "$MCP_DB_INSTALL_DIR" "$JUST_CONFIG_FILE" 2>/dev/null; then
        echo "configured"
    else
        echo "exists"
    fi
}

# detect_install_state :: () -> "missing" | "installed" | "outdated"
# Check if mcp-db is installed and up to date
detect_install_state() {
    if [[ ! -d "$MCP_DB_INSTALL_DIR" ]]; then
        echo "missing"
    elif [[ ! -d "$MCP_DB_INSTALL_DIR/.git" ]]; then
        echo "installed"  # installed but not via git
    else
        # Check if up to date with remote
        local local_head remote_head
        local_head=$(git -C "$MCP_DB_INSTALL_DIR" rev-parse HEAD 2>/dev/null)
        remote_head=$(git -C "$MCP_DB_INSTALL_DIR" rev-parse "@{u}" 2>/dev/null)
        if [[ "$local_head" == "$remote_head" ]]; then
            echo "installed"
        else
            echo "outdated"
        fi
    fi
}

# ══════════════════════════════════════════════════════════════
# AGGREGATE DETECTION
# ══════════════════════════════════════════════════════════════

# detect_all :: () -> JSON
# Aggregates all detection into a single JSON object
# This is the main entry point for detection
detect_all() {
    local os deps_json dsns_json

    os=$(detect_os) || return $?

    # Build deps object
    deps_json=$(cat <<EOF
{
    "brew": "$(detect_command brew)",
    "gum": "$(detect_command gum)",
    "just": "$(detect_command just)",
    "fzf": "$(detect_command fzf)",
    "git": "$(detect_command git)"
}
EOF
)

    # Build dsns array
    dsns_json=$(detect_dsns | jq -R -s 'split("\n") | map(select(. != ""))')

    # Combine into final output
    cat <<EOF
{
    "os": "$os",
    "deps": $deps_json,
    "config_state": "$(detect_config_state)",
    "install_state": "$(detect_install_state)",
    "dsns": $dsns_json
}
EOF
}
```

### lib/actions.sh (Effects, Explicit Errors)

```bash
#!/usr/bin/env bash
# lib/actions.sh - Side effects (installs, writes, network)
#
# CONTRACTS:
# - All functions have side effects (clearly marked in name)
# - All functions return explicit exit codes
# - Errors are loud and clear (no silent failures)
# - All paths/URLs come from config.sh (no magic values)

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

# ══════════════════════════════════════════════════════════════
# EXIT CODES
# ══════════════════════════════════════════════════════════════

readonly EXIT_INSTALL_FAILED=20
readonly EXIT_CLONE_FAILED=21
readonly EXIT_WRITE_FAILED=22
readonly EXIT_MCP_REGISTER_FAILED=23

# ══════════════════════════════════════════════════════════════
# INSTALLATION ACTIONS
# ══════════════════════════════════════════════════════════════

# action_install_brew :: () -> () | fails
# Installs Homebrew. Fails loudly if installation fails.
action_install_brew() {
    echo "Installing Homebrew..." >&2
    if ! /bin/bash -c "$(curl -fsSL "$BREW_INSTALLER_URL")"; then
        echo "ERROR: Failed to install Homebrew" >&2
        return $EXIT_INSTALL_FAILED
    fi
}

# action_install_package :: String -> () | fails
# Installs a package via brew. Fails loudly if installation fails.
action_install_package() {
    local pkg="$1"
    echo "Installing $pkg..." >&2
    if ! brew install "$pkg"; then
        echo "ERROR: Failed to install $pkg" >&2
        return $EXIT_INSTALL_FAILED
    fi
}

# ══════════════════════════════════════════════════════════════
# REPOSITORY ACTIONS
# ══════════════════════════════════════════════════════════════

# action_clone_or_update_repo :: () -> () | fails
# Clones the repo if missing, updates if present. Fails loudly.
action_clone_or_update_repo() {
    if [[ -d "$MCP_DB_INSTALL_DIR/.git" ]]; then
        echo "Updating $MCP_DB_INSTALL_DIR..." >&2
        if ! git -C "$MCP_DB_INSTALL_DIR" pull --ff-only; then
            echo "ERROR: Failed to update repo (merge conflict?)" >&2
            return $EXIT_CLONE_FAILED
        fi
    elif [[ -d "$MCP_DB_INSTALL_DIR" ]]; then
        echo "ERROR: $MCP_DB_INSTALL_DIR exists but is not a git repo" >&2
        return $EXIT_CLONE_FAILED
    else
        echo "Cloning to $MCP_DB_INSTALL_DIR..." >&2
        if ! git clone --branch "$REPO_BRANCH" "$REPO_URL" "$MCP_DB_INSTALL_DIR"; then
            echo "ERROR: Failed to clone repo" >&2
            return $EXIT_CLONE_FAILED
        fi
    fi
}

# ══════════════════════════════════════════════════════════════
# CONFIG FILE ACTIONS
# ══════════════════════════════════════════════════════════════

# action_ensure_import :: () -> () | fails
# Ensures the justfile imports our mcp.just. Non-destructive.
action_ensure_import() {
    local import_line="import '$MCP_DB_INSTALL_DIR/config/just/mcp.just'"

    # Ensure directory exists
    if ! mkdir -p "$JUST_CONFIG_DIR"; then
        echo "ERROR: Cannot create $JUST_CONFIG_DIR" >&2
        return $EXIT_WRITE_FAILED
    fi

    # Case 1: No justfile exists
    if [[ ! -f "$JUST_CONFIG_FILE" ]]; then
        echo "$import_line" > "$JUST_CONFIG_FILE"
        echo "Created $JUST_CONFIG_FILE" >&2
        return 0
    fi

    # Case 2: Justfile exists, already has our import
    if grep -qF "$MCP_DB_INSTALL_DIR" "$JUST_CONFIG_FILE"; then
        echo "Import already present in $JUST_CONFIG_FILE" >&2
        return 0
    fi

    # Case 3: Justfile exists, needs our import prepended
    local tmp
    tmp=$(mktemp) || return $EXIT_WRITE_FAILED
    {
        echo "$import_line"
        echo ""
        cat "$JUST_CONFIG_FILE"
    } > "$tmp"

    if ! mv "$tmp" "$JUST_CONFIG_FILE"; then
        rm -f "$tmp"
        echo "ERROR: Failed to update $JUST_CONFIG_FILE" >&2
        return $EXIT_WRITE_FAILED
    fi

    echo "Added import to $JUST_CONFIG_FILE" >&2
}

# ══════════════════════════════════════════════════════════════
# MCP ACTIONS
# ══════════════════════════════════════════════════════════════

# action_register_mcp :: String -> () | fails
# Registers the dbhub MCP server with the given config path.
action_register_mcp() {
    local config_path="$1"

    # Validate input
    if [[ -z "$config_path" ]]; then
        echo "ERROR: config_path is required" >&2
        return $EXIT_MCP_REGISTER_FAILED
    fi

    if [[ ! -f "$config_path" ]]; then
        echo "ERROR: Config file does not exist: $config_path" >&2
        return $EXIT_MCP_REGISTER_FAILED
    fi

    # Remove existing registration (ignore if not present)
    claude mcp remove "$MCP_SERVER_NAME" 2>/dev/null || true

    # Register new
    if ! claude mcp add "$MCP_SERVER_NAME" -- \
        npx -y "${DBHUB_PACKAGE}@${DBHUB_VERSION}" \
        --transport stdio \
        --config "$config_path"; then
        echo "ERROR: Failed to register MCP server" >&2
        return $EXIT_MCP_REGISTER_FAILED
    fi

    echo "Registered MCP server: $MCP_SERVER_NAME" >&2
}

# action_unregister_mcp :: () -> ()
# Removes the dbhub MCP server. Idempotent (no error if not present).
action_unregister_mcp() {
    if claude mcp remove "$MCP_SERVER_NAME" 2>/dev/null; then
        echo "Removed MCP server: $MCP_SERVER_NAME" >&2
    else
        echo "MCP server not registered: $MCP_SERVER_NAME" >&2
    fi
}
```

---

## Design Decisions

### Why This Structure?

| Principle | Implementation |
|-----------|----------------|
| **Separation of concerns** | detect.sh / compute.sh / actions.sh |
| **Effects at edges** | Only actions.sh modifies state |
| **Testable** | Run `detect_all` independently |
| **Composable** | Pipe detection → computation → action |
| **Debuggable** | Each layer outputs inspectable data |

### Private vs Public Recipes

```
just -g mcp dbhub init      # PUBLIC: user-facing orchestration
just -g mcp dbhub status    # PUBLIC: user-facing query
just -g mcp dbhub remove    # PUBLIC: user-facing action

just -g mcp dbhub _detect-dsns   # PRIVATE: debugging/testing
just -g mcp dbhub _gen-toml      # PRIVATE: debugging/testing
```

### Config Strategy: Clone + Import

Same as before - non-destructive, uses just's import feature.

---

## Files to Create

### In mcp-db repo (`~/DATA_PROG/TYPSCRIPT/mcp-db/`)

| File | Layer | Description |
|------|-------|-------------|
| `lib/config.sh` | DATA | All configuration constants |
| `lib/detect.sh` | DATA | Read-only detection functions |
| `lib/compute.sh` | COMPUTATION | Pure transformation functions |
| `lib/actions.sh` | ACTIONS | Side effect functions |
| `lib/ui.sh` | ACTIONS | User interaction (gum wrappers) |
| `bootstrap.sh` | ORCHESTRATION | Thin entry point |
| `config/just/mcp.just` | ORCHESTRATION | Recipe entry point (imports modules) |
| `config/just/modules/dbhub/mod.just` | MIXED | Composed recipes (follows same layers) |

---

## Anti-Patterns Avoided

| Bad Pattern | What We Do Instead |
|-------------|---------------------|
| `\|\| true` (silent failure) | Explicit error handling with exit codes |
| Magic strings (`$HOME/.mcp-db`) | All values in `lib/config.sh` |
| Hardcoded URLs/versions | Constants with documentation |
| `2>/dev/null` (hiding errors) | Errors go to stderr with clear messages |
| Monolithic functions | Layered: detect → compute → act |
| Implicit dependencies | Explicit function contracts in comments |

---

## Verification

```bash
# Test config is loaded
source lib/config.sh && echo "$MCP_DB_INSTALL_DIR"

# Test detection layer independently
source lib/detect.sh && detect_all | jq .

# Test individual detection functions
source lib/detect.sh && detect_command brew
source lib/detect.sh && detect_dsns

# Test actions in isolation
source lib/actions.sh && action_clone_or_update_repo

# Test full bootstrap flow
./bootstrap.sh

# Test just recipes
just -g mcp dbhub _detect-dsns        # Private: see what it finds
just -g mcp dbhub _detect-project-root # Private: verify path detection
just -g mcp dbhub init                 # Public: full flow
just -g mcp dbhub status               # Public: check state
just -g mcp dbhub remove               # Public: cleanup
```

---

## Implementation Order

1. `lib/config.sh` — Define all constants first
2. `lib/detect.sh` — Detection (depends on config)
3. `lib/actions.sh` — Actions (depends on config)
4. `lib/ui.sh` — UI helpers (depends on config)
5. `lib/compute.sh` — Pure transforms (optional, may inline)
6. `bootstrap.sh` — Thin orchestrator (sources all libs)
7. `config/just/modules/dbhub/mod.just` — Just recipes
8. `config/just/mcp.just` — Entry point (imports dbhub)
9. `README.md` — Documentation
