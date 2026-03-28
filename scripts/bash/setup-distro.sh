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

success() {
    msg "  $SYM_SUCCESS $1" "green"
    if [[ "$1" == *"(already installed"* ]]; then
        ((COUNT_SKIPPED++)) || true
    else
        ((COUNT_INSTALLED++)) || true
    fi
}

failure() {
    msg "  $SYM_FAILED $1" "red"
    ((COUNT_FAILED++)) || true
}

skipped() {
    msg "  $SYM_SKIPPED $1" "yellow"
    ((COUNT_SKIPPED++)) || true
}

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

ALL_CATEGORIES="dotfiles core cli shell languages cloud web containers powershell"

# Resolve DEV_TOOLBOX from this script's location
DEV_TOOLBOX="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPGRADE=false
ONLY_CATEGORIES=""
SKIP_CATEGORIES=""
INVALID_ARGS=()

COUNT_INSTALLED=0
COUNT_SKIPPED=0
COUNT_FAILED=0

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

Categories: dotfiles, core, cli, shell, languages, cloud, web, containers, powershell
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
# Category: dotfiles
# -------------------------------------------------------------------------

link_dotfile() {
    local src="$1" dest="$2" name
    name="$(basename "$dest")"

    if [[ -L "$dest" && "$(readlink -f "$dest")" == "$(readlink -f "$src")" ]]; then
        success "$name (already linked)"
        return
    fi

    # Back up existing file if it's not a symlink to our source
    if [[ -e "$dest" || -L "$dest" ]]; then
        mv "$dest" "${dest}.bak.$(date +%Y%m%d%H%M%S)"
        warn "$name — existing file backed up to ${dest}.bak.*"
    fi

    if ln -sf "$src" "$dest"; then
        success "$name → $src (linked)"
    else
        failure "$name (failed to link)"
    fi
}

install_dotfiles() {
    step "Linking dotfiles from DEV_TOOLBOX..."

    # Symlink shell config files so edits in the toolbox are reflected automatically
    link_dotfile "$DEV_TOOLBOX/.bashrc"       "$HOME/.bashrc"
    link_dotfile "$DEV_TOOLBOX/.bash_profile"  "$HOME/.bash_profile"

    # Copy .bashrc.local if it exists in the toolbox (gitignored, user-specific)
    if [[ -f "$HOME/.bashrc.local" ]]; then
        success ".bashrc.local (already exists)"
    elif [[ -f "$DEV_TOOLBOX/.bashrc.local" ]]; then
        cp "$DEV_TOOLBOX/.bashrc.local" "$HOME/.bashrc.local"
        success ".bashrc.local (copied from toolbox)"
    elif [[ -f "$DEV_TOOLBOX/.bashrc.local.example" ]]; then
        sed "s|<SET_BY_SETUP_DISTRO>|$DEV_TOOLBOX|g" \
            "$DEV_TOOLBOX/.bashrc.local.example" > "$HOME/.bashrc.local"
        success ".bashrc.local (created from template — edit with: nano ~/.bashrc.local)"
    else
        skipped ".bashrc.local (skipped — no .bashrc.local or template found)"
    fi

    msg "  DEV_TOOLBOX=$DEV_TOOLBOX" "cyan"
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
    trap 'rm -rf "$tmpdir"' RETURN

    if curl -fsSL "$url" -o "${tmpdir}/gitleaks.tar.gz" && \
       tar xzf "${tmpdir}/gitleaks.tar.gz" -C "$tmpdir" && \
       sudo install -m 755 "${tmpdir}/gitleaks" /usr/local/bin/gitleaks; then
        success "gitleaks v${latest_tag} (installed)"
    else
        failure "gitleaks (failed)"
    fi
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
    install_tailscale
}

install_tailscale() {
    if ! needs_install tailscale; then
        success "tailscale (already installed)"
        return
    fi

    if [[ "$PLATFORM" == "macos" ]]; then
        if brew install --cask tailscale 2>/dev/null; then
            success "tailscale (installed)"
        else
            failure "tailscale (failed)"
        fi
        return
    fi

    # Linux: official install script
    if curl -fsSL https://tailscale.com/install.sh | sh >/dev/null 2>&1; then
        success "tailscale (installed)"
    else
        failure "tailscale (failed)"
    fi
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
        [[ "$tool" == "bat" && "$PLATFORM" == "debian" ]] && cmd="batcat"

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
    trap 'rm -rf "$tmpdir"' RETURN

    if curl -fsSL "$url" -o "${tmpdir}/${font_name}.zip"; then
        mkdir -p "$font_dir"
        unzip -o "${tmpdir}/${font_name}.zip" -d "$font_dir" >/dev/null
        fc-cache -f "$font_dir" 2>/dev/null || true
        success "Nerd Font $font_name $latest_tag (installed)"
    else
        failure "Nerd Font $font_name (failed)"
    fi
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

# -------------------------------------------------------------------------
# Category: cloud
# -------------------------------------------------------------------------

install_awscli() {
    if ! needs_install aws; then
        success "aws-cli (already installed)"
        return
    fi

    if [[ "$PLATFORM" == "macos" ]]; then
        if pkg_install awscli 2>/dev/null; then
            success "aws-cli (installed)"
        else
            failure "aws-cli (failed)"
        fi
        return
    fi

    # Linux: official installer
    local tmpdir
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' RETURN

    if curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o "${tmpdir}/awscliv2.zip" && \
       unzip -o "${tmpdir}/awscliv2.zip" -d "$tmpdir" >/dev/null && \
       sudo "${tmpdir}/aws/install" --update >/dev/null 2>&1; then
        success "aws-cli v2 (installed)"
    else
        failure "aws-cli (failed)"
    fi
}

install_azure_cli() {
    if ! needs_install az; then
        success "azure-cli (already installed)"
        return
    fi

    if [[ "$PLATFORM" == "macos" ]]; then
        if pkg_install azure-cli 2>/dev/null; then
            success "azure-cli (installed)"
        else
            failure "azure-cli (failed)"
        fi
        return
    fi

    # Linux: Microsoft install script
    if curl -fsSL https://aka.ms/InstallAzureCLIDeb | sudo bash >/dev/null 2>&1; then
        success "azure-cli (installed)"
    else
        failure "azure-cli (failed)"
    fi
}

install_wrangler() {
    if ! needs_install wrangler; then
        success "wrangler (already installed)"
        return
    fi

    if ! cmd_exists npm; then
        skipped "wrangler (skipped — npm not available, install languages category first)"
        return
    fi

    if npm install -g wrangler >/dev/null 2>&1; then
        success "wrangler (installed)"
    else
        failure "wrangler (failed)"
    fi
}

install_cloud() {
    step "Installing cloud CLIs..."
    install_awscli
    install_azure_cli
    install_wrangler
}

# -------------------------------------------------------------------------
# Category: web
# -------------------------------------------------------------------------

install_web() {
    step "Installing web server tools..."

    # nginx
    if ! needs_install nginx; then
        success "nginx (already installed)"
    else
        if pkg_install nginx 2>/dev/null; then
            success "nginx (installed)"
        else
            failure "nginx (failed)"
        fi
    fi

    # certbot
    if ! needs_install certbot; then
        success "certbot (already installed)"
    else
        if [[ "$PLATFORM" == "debian" ]]; then
            if pkg_install certbot python3-certbot-nginx 2>/dev/null; then
                success "certbot (installed)"
            else
                failure "certbot (failed)"
            fi
        else
            if pkg_install certbot 2>/dev/null; then
                success "certbot (installed)"
            else
                failure "certbot (failed)"
            fi
        fi
    fi

    # mkcert
    if ! needs_install mkcert; then
        success "mkcert (already installed)"
    else
        if pkg_install mkcert 2>/dev/null; then
            success "mkcert (installed)"
        else
            failure "mkcert (failed)"
        fi
    fi
}

# -------------------------------------------------------------------------
# Category: containers
# -------------------------------------------------------------------------

install_containers() {
    step "Installing container tools..."

    if ! needs_install docker; then
        success "docker (already installed)"
        return
    fi

    if [[ "$PLATFORM" == "macos" ]]; then
        if brew install --cask docker 2>/dev/null; then
            success "docker desktop (installed)"
        else
            failure "docker (failed)"
        fi
        return
    fi

    # Linux: official install script
    if curl -fsSL https://get.docker.com | sudo sh >/dev/null 2>&1; then
        # Add current user to docker group
        sudo usermod -aG docker "$USER" 2>/dev/null || true
        success "docker + compose (installed — log out and back in for group changes)"
    else
        failure "docker (failed)"
    fi
}

# -------------------------------------------------------------------------
# Category: powershell
# -------------------------------------------------------------------------

install_powershell() {
    step "Installing PowerShell..."

    if ! needs_install pwsh; then
        success "powershell (already installed)"
        return
    fi

    if [[ "$PLATFORM" == "macos" ]]; then
        if brew install --cask powershell 2>/dev/null; then
            success "powershell (installed)"
        else
            failure "powershell (failed)"
        fi
        return
    fi

    # Debian/Ubuntu: Microsoft package repo
    if ! [[ -f /etc/apt/sources.list.d/microsoft-prod.list ]] && \
       ! [[ -f /etc/apt/sources.list.d/microsoft.list ]]; then
        local release_id release_version deb_url
        source /etc/os-release
        release_id="${ID}"
        release_version="${VERSION_ID}"

        # Use Ubuntu repo for Ubuntu, Debian repo for Debian
        deb_url="https://packages.microsoft.com/config/${release_id}/${release_version}/packages-microsoft-prod.deb"

        local tmpdir
        tmpdir=$(mktemp -d)
        trap 'rm -rf "$tmpdir"' RETURN
        if curl -fsSL "$deb_url" -o "${tmpdir}/packages-microsoft-prod.deb"; then
            sudo dpkg -i "${tmpdir}/packages-microsoft-prod.deb" >/dev/null 2>&1
            sudo apt update >/dev/null 2>&1
        fi
    fi

    if sudo apt install -y powershell 2>/dev/null; then
        success "powershell (installed)"
    else
        failure "powershell (failed)"
    fi
}

# -------------------------------------------------------------------------
# Main
# -------------------------------------------------------------------------

main() {
    detect_platform
    msg "Platform: $PLATFORM ($PKG_MANAGER)" "bright_cyan"
    printf '\n'

    # Update package index
    step "Updating package index..."
    pkg_update >/dev/null 2>&1
    success "Package index updated"
    printf '\n'

    # Run categories in dependency order
    local categories=(dotfiles core cli shell languages cloud web containers powershell)
    local ran=0

    for category in "${categories[@]}"; do
        if should_run_category "$category"; then
            "install_${category}"
            printf '\n'
            ((ran++)) || true
        fi
    done

    if [[ $ran -eq 0 ]]; then
        warn "No categories selected. Run with --help for usage."
        exit 0
    fi

    # Summary
    printf '\n'
    msg "Summary:" "bright_cyan"
    msg "  Installed: $COUNT_INSTALLED" "green"
    msg "  Skipped:   $COUNT_SKIPPED" "yellow"
    msg "  Failed:    $COUNT_FAILED" "red"
    printf '\n'

    if [[ $COUNT_FAILED -gt 0 ]]; then
        msg "$SYM_WARNING Setup completed with $COUNT_FAILED failure(s)." "yellow"
    else
        msg "$SYM_SUCCESS Setup complete." "bright_green"
    fi
}

# -------------------------------------------------------------------------
# Entry point
# -------------------------------------------------------------------------

parse_args "$@"

if [[ ${#INVALID_ARGS[@]} -gt 0 ]]; then
    msg "Unrecognised option(s):" "red"
    for arg in "${INVALID_ARGS[@]}"; do
        msg "  $arg" "red"
    done
    show_usage
    exit 2
fi

main
