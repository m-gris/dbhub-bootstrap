#!/usr/bin/env bash
set -euo pipefail

# Bootstrap is self-contained until repo is cloned.
# Inline minimal dependencies, then delegate to libs.

# =============================================================================
# DATA — no logic, just facts
# =============================================================================

AUTO=false  # Set by --auto or -y flag (non-interactive mode)

INSTALL_DIR="$HOME/.dbhub-bootstrap"
REPO_URL="https://github.com/m-gris/dbhub-bootstrap.git"
BIN_DIR="$HOME/.local/bin"

# Justfile paths (must be absolute for just to resolve)
JUST_CONFIG_DIR="$HOME/.config/just"
JUST_MCP_DIR="$JUST_CONFIG_DIR/mcp"
GLOBAL_JUSTFILE="$HOME/.justfile"

# Tool definitions: repo|version|binary_name
declare -A TOOLS=(
    [gum]="charmbracelet/gum|0.14.5|gum"
    [just]="casey/just|1.36.0|just"
)

# Platform suffixes: gum_suffix|just_suffix
declare -A PLATFORM_MAP=(
    [macos-arm64]="Darwin_arm64|aarch64-apple-darwin"
    [macos-x86_64]="Darwin_x86_64|x86_64-apple-darwin"
    [linux-arm64]="Linux_arm64|aarch64-unknown-linux-musl"
    [linux-x86_64]="Linux_x86_64|x86_64-unknown-linux-musl"
)

# =============================================================================
# COMPUTATIONS — pure functions, no side effects
# =============================================================================

# parse_args ARGS... -> sets AUTO flag
parse_args() {
    for arg in "$@"; do
        case "$arg" in
            --auto|-y) AUTO=true ;;
            --help|-h)
                cat <<EOF
Usage: bootstrap.sh [OPTIONS]

Options:
  --auto, -y    Non-interactive mode (skip confirmation prompts)
  --help, -h    Show this help message
EOF
                exit 0
                ;;
        esac
    done
}

detect_os() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux)  echo "linux" ;;
        *)      echo "unknown" ;;
    esac
}

detect_arch() {
    case "$(uname -m)" in
        x86_64)        echo "x86_64" ;;
        aarch64|arm64) echo "arm64" ;;
        *)             echo "unknown" ;;
    esac
}

# get_url TOOL OS ARCH -> URL
# Computes download URL from data tables
get_url() {
    local tool=$1 os=$2 arch=$3
    local tool_data=${TOOLS[$tool]}
    local platform_data=${PLATFORM_MAP["$os-$arch"]}

    local repo version binary
    IFS='|' read -r repo version binary <<< "$tool_data"

    local gum_suffix just_suffix
    IFS='|' read -r gum_suffix just_suffix <<< "$platform_data"

    # Each tool has slightly different URL patterns
    case "$tool" in
        gum)
            echo "https://github.com/$repo/releases/download/v${version}/gum_${version}_${gum_suffix}.tar.gz"
            ;;
        just)
            echo "https://github.com/$repo/releases/download/${version}/just-${version}-${just_suffix}.tar.gz"
            ;;
    esac
}

# missing_tools -> space-separated list of missing tools
missing_tools() {
    local missing=""
    for tool in "${!TOOLS[@]}"; do
        command -v "$tool" >/dev/null || missing="$missing $tool"
    done
    echo "$missing"
}

# =============================================================================
# ACTIONS — side effects, kept minimal and generic
# =============================================================================

# install_tool TOOL OS ARCH -> installs tool to BIN_DIR
install_tool() {
    local tool=$1 os=$2 arch=$3
    local url=$(get_url "$tool" "$os" "$arch")

    mkdir -p "$BIN_DIR"
    echo "  Installing $tool..."
    curl -fsSL "$url" | tar -xz -C "$BIN_DIR" "$tool"
    chmod +x "$BIN_DIR/$tool"
}

# install_via_brew TOOL -> installs via Homebrew if available
install_via_brew() {
    local tool=$1
    echo "  Installing $tool via Homebrew..."
    brew install "$tool"
}

# ensure_line FILE LINE -> ensures LINE exists in FILE (creates file if needed)
ensure_line() {
    local file=$1 line=$2
    if [[ ! -f "$file" ]]; then
        echo "$line" > "$file"
    elif ! grep -qF "$line" "$file"; then
        echo "$line" >> "$file"
    fi
}

# =============================================================================
# ORCHESTRATION — wires it all together
# =============================================================================

parse_args "$@"

OS=$(detect_os)
ARCH=$(detect_arch)

[[ "$OS" == "unknown" ]] && { echo "Unsupported OS: $(uname -s)"; exit 1; }
[[ "$ARCH" == "unknown" ]] && { echo "Unsupported arch: $(uname -m)"; exit 1; }

missing=$(missing_tools)

echo "⚡ Claude Database Setup"
echo "  Platform: $OS/$ARCH"
echo ""
if [[ -z "$missing" ]]; then
    echo "✓ All dependencies installed"
else
    for tool in $missing; do
        echo "  ⏳ $tool (will install)"
    done
fi
echo ""

if [[ "$AUTO" == false ]]; then
    read -p "Proceed? [Y/n] " -n 1 -r
    echo
    [[ $REPLY =~ ^[Nn]$ ]] && exit 0
fi

# Install missing tools
for tool in $missing; do
    if [[ "$OS" == "macos" ]] && command -v brew >/dev/null; then
        install_via_brew "$tool"
    else
        install_tool "$tool" "$OS" "$ARCH"
    fi
done

# Ensure BIN_DIR is in PATH for this session
export PATH="$BIN_DIR:$PATH"

# --- Phase 3: Clone repo and setup justfile ---

if [[ ! -d "$INSTALL_DIR" ]]; then
    gum spin --title "Cloning dbhub-bootstrap..." -- git clone "$REPO_URL" "$INSTALL_DIR"
fi

# Setup global justfile with mcp module
mkdir -p "$JUST_MCP_DIR"
ensure_line "$JUST_MCP_DIR/mod.just" "mod dbhub \"$INSTALL_DIR/config/just/dbhub.just\""
ensure_line "$GLOBAL_JUSTFILE" "mod mcp \"$JUST_MCP_DIR\""

# Now libs exist, source them
source "$INSTALL_DIR/lib/all.sh"

# --- Phase 4: Done ---

success "✅ Bootstrap complete!" "" "Run: just -g mcp dbhub init"
