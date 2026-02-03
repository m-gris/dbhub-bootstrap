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
