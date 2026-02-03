#!/usr/bin/env bash
# All configuration. No logic. Just data.
[[ -n "${_MCP_DB_CONFIG_LOADED:-}" ]] && return 0
readonly _MCP_DB_CONFIG_LOADED=1

readonly INSTALL_DIR="$HOME/.dbhub-bootstrap"
readonly REPO_URL="https://github.com/m-gris/dbhub-bootstrap.git"

readonly MCP_NAME="dbhub"
readonly MCP_CONFIG=".dbhub.toml"
readonly MCP_PACKAGE="@bytebase/dbhub"
readonly MCP_VERSION="0.1.5"  # Pin for reproducibility

readonly DSN_PATTERN='(database_url|db_|dsn|connection_string)'
