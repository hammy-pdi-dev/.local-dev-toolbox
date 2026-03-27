#!/usr/bin/env bash
# setup-distro.sh — Cross-platform dev environment bootstrap (macOS + Debian/Ubuntu)
# Idempotent: skips tools already installed unless --upgrade is set.
set -euo pipefail

# -------------------------------------------------------------------------
# Status symbols (Unicode)
SYM_SUCCESS=$'\u2705'           # ✅
SYM_FAILED=$'\U0001F534'        # 🔴
SYM_SKIPPED=$'\u23ED\uFE0F'     # ⏭️
SYM_STEP=$'\u25B6\uFE0F'        # ▶️
SYM_WARNING=$'\u26A0\uFE0F'     # ⚠️

# ANSI colour codes
C_RESET=$'\033[0m'
C_RED=$'\033[31m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_CYAN=$'\033[36m'
C_WHITE=$'\033[37m'
C_BRIGHT_GREEN=$'\033[92m'
C_BRIGHT_CYAN=$'\033[96m'

# -------------------------------------------------------------------------
# Formatting helpers
# -------------------------------------------------------------------------

fmt() {
    local text="$1" color="${2:-white}"
    case "$color" in
        red)          printf '%s%s%s' "$C_RED"          "$text" "$C_RESET" ;;
        green)        printf '%s%s%s' "$C_GREEN"        "$text" "$C_RESET" ;;
        yellow)       printf '%s%s%s' "$C_YELLOW"       "$text" "$C_RESET" ;;
        cyan)         printf '%s%s%s' "$C_CYAN"         "$text" "$C_RESET" ;;
        bright_green) printf '%s%s%s' "$C_BRIGHT_GREEN" "$text" "$C_RESET" ;;
        bright_cyan)  printf '%s%s%s' "$C_BRIGHT_CYAN"  "$text" "$C_RESET" ;;
        *)            printf '%s%s%s' "$C_WHITE"        "$text" "$C_RESET" ;;
    esac
}

msg() {
    local text="$1" color="${2:-white}" newline="${3:-true}"
    if [[ "$newline" == "true" ]]; then
        fmt "$text" "$color"
        printf '\n'
    else
        fmt "$text" "$color"
    fi
}

warn() { printf '%sWARNING: %s%s\n' "$C_YELLOW" "$1" "$C_RESET" >&2; }
err()  { printf '%sERROR: %s%s\n'   "$C_RED"    "$1" "$C_RESET" >&2; }

step()    { msg "$SYM_STEP $1" "cyan"; }
success() { msg "  $SYM_SUCCESS $1" "green"; }
failure() { msg "  $SYM_FAILED $1" "red"; }
skipped() { msg "  $SYM_SKIPPED $1" "yellow"; }

# -------------------------------------------------------------------------
# Platform detection (get_distro extended from .bashrc to include macOS)
# -------------------------------------------------------------------------

PLATFORM=""
PKG_MANAGER=""

get_distro() {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        echo "macos"
        return
    fi

    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        case "$ID" in
            ubuntu|debian|mint)                 echo "debian" ;;
            fedora|rhel|centos|rocky|almalinux) echo "redhat" ;;
            arch|manjaro|endeavouros)           echo "arch" ;;
            opensuse*|sles)                     echo "suse" ;;
            *)                                  echo "unknown" ;;
        esac
    else
        echo "unknown"
    fi
}

detect_platform() {
    local distro
    distro=$(get_distro)

    case "$distro" in
        macos)
            PLATFORM="macos"
            PKG_MANAGER="brew"
            # Install Homebrew if missing
            if ! command -v brew >/dev/null 2>&1; then
                step "Installing Homebrew..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
                eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null)"
                success "Homebrew (installed)"
            fi
            ;;
        debian)
            PLATFORM="debian"
            PKG_MANAGER="apt"
            ;;
        *)
            err "Unsupported platform: $distro. Only macOS and Debian/Ubuntu are supported."
            exit 1
            ;;
    esac
}

# Archive extraction helper (from .bashrc)
extract() {
    for file in "$@"; do
        if [[ -f "$file" ]]; then
            case "$file" in
                *.tar.bz2) tar xjf "$file" ;;
                *.tar.gz)  tar xzf "$file" ;;
                *.tar.xz)  tar xJf "$file" ;;
                *.bz2)     bunzip2 "$file" ;;
                *.gz)      gunzip "$file" ;;
                *.tar)     tar xf "$file" ;;
                *.tbz2)    tar xjf "$file" ;;
                *.tgz)     tar xzf "$file" ;;
                *.zip)     unzip -o "$file" ;;
                *.7z)      7z x "$file" ;;
                *)         warn "Unknown archive format: $file" ;;
            esac
        else
            warn "File not found: $file"
        fi
    done
}

# -------------------------------------------------------------------------
# Package manager abstraction
# -------------------------------------------------------------------------

# Translate package names across platforms
pkg_name() {
    local name="$1"
    if [[ "$PKG_MANAGER" == "brew" ]]; then
        case "$name" in
            build-essential)       echo "" ;;
            python3-pip)           echo "" ;;
            python3-venv)          echo "" ;;
            python3-certbot-nginx) echo "" ;;
            fd-find)               echo "fd" ;;
            *)                     echo "$name" ;;
        esac
    else
        echo "$name"
    fi
}

# Install one or more packages via the detected package manager
pkg_install() {
    local resolved=()
    for name in "$@"; do
        local translated
        translated=$(pkg_name "$name")
        [[ -n "$translated" ]] && resolved+=("$translated")
    done

    [[ ${#resolved[@]} -eq 0 ]] && return 0

    case "$PKG_MANAGER" in
        brew) brew install "${resolved[@]}" ;;
        apt)  sudo apt install -y "${resolved[@]}" ;;
    esac
}

# Refresh package index
pkg_update() {
    case "$PKG_MANAGER" in
        brew) brew update ;;
        apt)  sudo apt update ;;
    esac
}

# Upgrade specific packages
pkg_upgrade() {
    local resolved=()
    for name in "$@"; do
        local translated
        translated=$(pkg_name "$name")
        [[ -n "$translated" ]] && resolved+=("$translated")
    done

    [[ ${#resolved[@]} -eq 0 ]] && return 0

    case "$PKG_MANAGER" in
        brew) brew upgrade "${resolved[@]}" 2>/dev/null || true ;;
        apt)  sudo apt install --only-upgrade -y "${resolved[@]}" ;;
    esac
}

# Check if a command exists on PATH
cmd_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install via curl | bash pattern
curl_install() {
    local url="$1"
    shift
    curl -fsSL "$url" | bash "$@"
}

# Guard: skip if command exists and --upgrade is not set
needs_install() {
    local cmd="$1"
    if cmd_exists "$cmd" && [[ "$UPGRADE" == "false" ]]; then
        return 1
    fi
    return 0
}

# -------------------------------------------------------------------------
# Configuration
# -------------------------------------------------------------------------

ALL_CATEGORIES="core cli shell languages cloud web containers powershell"
UPGRADE=false
ONLY_CATEGORIES=""
SKIP_CATEGORIES=""
INVALID_ARGS=()

# -------------------------------------------------------------------------
# Argument parsing
# -------------------------------------------------------------------------

show_usage() {
    cat <<'EOF'
Usage: setup-distro.sh [OPTIONS]

Cross-platform dev environment bootstrap (macOS + Debian/Ubuntu).

Options:
  --all                Install all categories (default)
  --only=<csv>         Install only these categories (e.g. --only=core,cli)
  --skip=<csv>         Skip these categories (e.g. --skip=cloud,containers)
  --upgrade            Re-install/upgrade tools even if already present
  --help               Show this help message

Categories: core, cli, shell, languages, cloud, web, containers, powershell
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        local arg="$1"
        local name="" value=""

        # Handle --key=value syntax
        if [[ "$arg" =~ ^(--?[^=]+)=(.+)$ ]]; then
            name="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
        else
            name="$arg"
        fi

        # Normalise: strip leading dashes, lowercase
        local normalised
        normalised="$(printf '%s' "$name" | sed 's/^-*//' | tr '[:upper:]' '[:lower:]')"

        case "$normalised" in
            all)      ;;  # default behaviour, no-op
            only)
                if [[ -z "$value" ]]; then
                    if [[ $# -ge 2 ]]; then shift; value="$1"; else INVALID_ARGS+=("$arg"); shift; continue; fi
                fi
                ONLY_CATEGORIES="$value"
                ;;
            skip)
                if [[ -z "$value" ]]; then
                    if [[ $# -ge 2 ]]; then shift; value="$1"; else INVALID_ARGS+=("$arg"); shift; continue; fi
                fi
                SKIP_CATEGORIES="$value"
                ;;
            upgrade)  UPGRADE=true ;;
            help)     show_usage; exit 0 ;;
            *)        INVALID_ARGS+=("$arg") ;;
        esac
        shift
    done

    # Validate mutual exclusivity
    if [[ -n "$ONLY_CATEGORIES" && -n "$SKIP_CATEGORIES" ]]; then
        err "--only and --skip are mutually exclusive."
        exit 2
    fi
}

# Check whether a category should run
should_run_category() {
    local category="$1"

    if [[ -n "$ONLY_CATEGORIES" ]]; then
        [[ ",$ONLY_CATEGORIES," == *",$category,"* ]]
        return
    fi

    if [[ -n "$SKIP_CATEGORIES" ]]; then
        [[ ",$SKIP_CATEGORIES," != *",$category,"* ]]
        return
    fi

    return 0
}

# -------------------------------------------------------------------------
# Category: core
# -------------------------------------------------------------------------

install_gitleaks() {
    if ! needs_install gitleaks; then
        success "gitleaks (already installed)"
        return
    fi

    local os arch url tmpdir
    os="$(uname -s)"
    arch="$(uname -m)"

    case "$os" in
        Darwin) os="darwin" ;;
        Linux)  os="linux" ;;
        *)      failure "gitleaks — unsupported OS: $os"; return ;;
    esac

    case "$arch" in
        x86_64)  arch="x64" ;;
        aarch64|arm64) arch="arm64" ;;
        *)       failure "gitleaks — unsupported arch: $arch"; return ;;
    esac

    # Fetch latest release tag from GitHub API
    local latest_tag
    latest_tag=$(curl -fsSL "https://api.github.com/repos/gitleaks/gitleaks/releases/latest" \
        | grep '"tag_name"' | head -1 | sed 's/.*"v\([^"]*\)".*/\1/')

    if [[ -z "$latest_tag" ]]; then
        failure "gitleaks — could not determine latest version"
        return
    fi

    url="https://github.com/gitleaks/gitleaks/releases/download/v${latest_tag}/gitleaks_${latest_tag}_${os}_${arch}.tar.gz"
    tmpdir=$(mktemp -d)

    if curl -fsSL "$url" -o "${tmpdir}/gitleaks.tar.gz" && \
       tar xzf "${tmpdir}/gitleaks.tar.gz" -C "$tmpdir" && \
       sudo install -m 755 "${tmpdir}/gitleaks" /usr/local/bin/gitleaks; then
        success "gitleaks v${latest_tag} (installed)"
    else
        failure "gitleaks (failed)"
    fi

    rm -rf "$tmpdir"
}

install_core() {
    step "Installing core tools..."

    local tools=(curl wget git unzip build-essential)
    for tool in "${tools[@]}"; do
        local cmd="$tool"
        [[ "$tool" == "build-essential" ]] && cmd="gcc"

        if ! needs_install "$cmd"; then
            success "$tool (already installed)"
            continue
        fi

        if pkg_install "$tool" 2>/dev/null; then
            success "$tool (installed)"
        else
            failure "$tool (failed)"
        fi
    done

    install_gitleaks
}

# -------------------------------------------------------------------------
# Category: cli
# -------------------------------------------------------------------------

install_cli() {
    step "Installing CLI tools..."

    local tools=(bat ripgrep fzf zoxide fastfetch htop)
    for tool in "${tools[@]}"; do
        local cmd="$tool"
        [[ "$tool" == "ripgrep" ]] && cmd="rg"

        if ! needs_install "$cmd"; then
            success "$tool (already installed)"
            continue
        fi

        if pkg_install "$tool" 2>/dev/null; then
            success "$tool (installed)"
        else
            failure "$tool (failed)"
        fi
    done
}

# -------------------------------------------------------------------------
# Category: shell
# -------------------------------------------------------------------------

install_nerd_font() {
    local font_name="FiraCode"
    local font_dir

    if [[ "$PLATFORM" == "macos" ]]; then
        if brew list --cask "font-fira-code-nerd-font" >/dev/null 2>&1 && [[ "$UPGRADE" == "false" ]]; then
            success "Nerd Font $font_name (already installed)"
            return
        fi

        brew tap homebrew/cask-fonts 2>/dev/null || true
        if brew install --cask "font-fira-code-nerd-font" 2>/dev/null; then
            success "Nerd Font $font_name (installed)"
        else
            failure "Nerd Font $font_name (failed)"
        fi
        return
    fi

    # Linux: download to ~/.local/share/fonts
    font_dir="$HOME/.local/share/fonts/NerdFonts"
    if [[ -d "$font_dir" && "$(ls -A "$font_dir" 2>/dev/null)" ]] && [[ "$UPGRADE" == "false" ]]; then
        success "Nerd Font $font_name (already installed)"
        return
    fi

    local tmpdir latest_tag url
    latest_tag=$(curl -fsSL "https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest" \
        | grep '"tag_name"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/')

    if [[ -z "$latest_tag" ]]; then
        failure "Nerd Font $font_name — could not determine latest version"
        return
    fi

    url="https://github.com/ryanoasis/nerd-fonts/releases/download/${latest_tag}/${font_name}.zip"
    tmpdir=$(mktemp -d)

    if curl -fsSL "$url" -o "${tmpdir}/${font_name}.zip"; then
        mkdir -p "$font_dir"
        unzip -o "${tmpdir}/${font_name}.zip" -d "$font_dir" >/dev/null
        fc-cache -f "$font_dir" 2>/dev/null || true
        success "Nerd Font $font_name $latest_tag (installed)"
    else
        failure "Nerd Font $font_name (failed)"
    fi

    rm -rf "$tmpdir"
}

install_shell() {
    step "Installing shell enhancements..."

    # Starship prompt
    if ! needs_install starship; then
        success "starship (already installed)"
    else
        if curl -fsSL https://starship.rs/install.sh | sh -s -- -y >/dev/null 2>&1; then
            success "starship (installed)"
        else
            failure "starship (failed)"
        fi
    fi

    # Nerd Font
    install_nerd_font
}

# -------------------------------------------------------------------------
# Category: languages
# -------------------------------------------------------------------------

install_languages() {
    step "Installing language runtimes..."

    # NVM + Node LTS
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    if [[ -s "$NVM_DIR/nvm.sh" ]] && [[ "$UPGRADE" == "false" ]]; then
        success "nvm (already installed)"
    else
        if curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash >/dev/null 2>&1; then
            success "nvm (installed)"
        else
            failure "nvm (failed)"
        fi
    fi

    # Source nvm so we can install node
    [[ -s "$NVM_DIR/nvm.sh" ]] && \. "$NVM_DIR/nvm.sh"

    if cmd_exists node && [[ "$UPGRADE" == "false" ]]; then
        success "node LTS (already installed — $(node --version))"
    else
        if cmd_exists nvm; then
            if nvm install --lts >/dev/null 2>&1; then
                success "node LTS (installed — $(node --version))"
            else
                failure "node LTS (failed)"
            fi
        else
            skipped "node LTS (skipped — nvm not available)"
        fi
    fi

    # Python3 + pip
    if cmd_exists python3 && [[ "$UPGRADE" == "false" ]]; then
        success "python3 (already installed — $(python3 --version))"
    else
        if pkg_install python3 python3-pip python3-venv 2>/dev/null; then
            success "python3 + pip (installed)"
        else
            failure "python3 (failed)"
        fi
    fi
}
