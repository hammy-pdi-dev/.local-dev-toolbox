#!/usr/bin/env bash
# shellcheck disable=SC1091
# ~/.bashrc - Team-reusable WSL bashrc
# Personal overrides and secrets go in ~/.bashrc.local (sourced at the end)

# Only for interactive shells
[[ $- != *i* ]] && return

#################### INIT ####################

# System defaults and completion
[[ -f /etc/bashrc ]] && source /etc/bashrc
if [[ -f /usr/share/bash-completion/bash_completion ]]; then
    source /usr/share/bash-completion/bash_completion
elif [[ -f /etc/bash_completion ]]; then
    source /etc/bash_completion
fi

# Fast system info (use whichever is available)
if command -v fastfetch >/dev/null 2>&1; then
    fastfetch
elif command -v neofetch >/dev/null 2>&1; then
    neofetch
fi

#################### SHELL OPTIONS ####################

shopt -s checkwinsize histappend globstar
bind "set bell-style none" 2>/dev/null
bind "set completion-ignore-case on" 2>/dev/null
bind "set show-all-if-ambiguous on" 2>/dev/null
stty -ixon 2>/dev/null

#################### HISTORY ####################

export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTTIMEFORMAT="%F %T "
export HISTCONTROL="erasedups:ignoredups:ignorespace"
export PROMPT_COMMAND="history -a"

#################### ENV ####################

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

export EDITOR="${EDITOR:-vim}"
export VISUAL="${VISUAL:-$EDITOR}"
export CLICOLOR=1

# Coloured man pages / less
export LESS_TERMCAP_mb=$'\e[1;31m'
export LESS_TERMCAP_md=$'\e[1;31m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[1;44;33m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;32m'

if command -v bat >/dev/null 2>&1; then
    export MANPAGER="sh -c 'col -bx | bat -l man -p'"
fi

# Clipboard (WSL or native Linux)
if command -v clip.exe >/dev/null 2>&1; then
    alias copy='clip.exe'
    alias paste='powershell.exe -c Get-Clipboard'
elif command -v wl-copy >/dev/null 2>&1; then
    alias copy='wl-copy'
    alias paste='wl-paste'
elif command -v xclip >/dev/null 2>&1; then
    alias copy='xclip -selection clipboard'
    alias paste='xclip -selection clipboard -o'
fi

# PATH consolidation
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

# NVM
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
[[ -s "$NVM_DIR/nvm.sh" ]] && \. "$NVM_DIR/nvm.sh"
[[ -s "$NVM_DIR/bash_completion" ]] && \. "$NVM_DIR/bash_completion"

# FZF integration
if [[ -f "$HOME/.fzf.bash" ]]; then
    source "$HOME/.fzf.bash"
    export FZF_DEFAULT_COMMAND='fd --type f --strip-cwd-prefix --hidden --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
fi

#################### FUNCTIONS ####################

# Detect the Linux distribution family (debian, redhat, arch, suse) for distro-aware aliases
get_distro() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        case "$ID" in
            fedora|rhel|centos|rocky|almalinux) echo "redhat" ;;
            ubuntu|debian|mint)                 echo "debian" ;;
            arch|manjaro|endeavouros)           echo "arch" ;;
            opensuse*|sles)                     echo "suse" ;;
            *)                                  echo "unknown" ;;
        esac
    else
        echo "unknown"
    fi
}

# List directory contents using the best available tool (eza > exa > lsd > ls)
_list_dir() {
    if command -v eza >/dev/null 2>&1; then
        eza --icons --group-directories-first
    elif command -v exa >/dev/null 2>&1; then
        exa --icons --group-directories-first
    elif command -v lsd >/dev/null 2>&1; then
        lsd --group-dirs=first --icon=auto
    else
        ls -CF --color=auto
    fi
}

# Override cd to automatically list directory contents after changing directory
cd() {
    if [[ $# -eq 0 ]]; then
        builtin cd ~ && _list_dir
    else
        builtin cd "$@" && _list_dir
    fi
}

# Prompt the user for yes/no confirmation. Usage: prompt_continue "Continue?" && do_thing
prompt_continue() {
    local prompt_message="$1"
    read -p "$prompt_message (y/n): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# Extract any common archive format. Usage: extract file.tar.gz [file2.zip ...]
extract() {
    for file in "$@"; do
        if [[ -f "$file" ]]; then
            case "$file" in
                *.tar.bz2) tar xjf "$file" ;;
                *.tar.gz)  tar xzf "$file" ;;
                *.tar.xz)  tar xJf "$file" ;;
                *.bz2)     bunzip2 "$file" ;;
                *.rar)     unrar x "$file" ;;
                *.gz)      gunzip "$file" ;;
                *.tar)     tar xf "$file" ;;
                *.tbz2)    tar xjf "$file" ;;
                *.tgz)     tar xzf "$file" ;;
                *.zip)     unzip "$file" ;;
                *.Z)       uncompress "$file" ;;
                *.7z)      7z x "$file" ;;
                *)         echo "Unknown archive format: $file" ;;
            esac
        else
            echo "File not found: $file"
        fi
    done
}

# Create a directory and cd into it in one step. Usage: mkcd my-project
mkcd() { mkdir -p "$1" && cd "$1" || return; }

# Create a .bak copy of a file or directory. Usage: bak config.yml
bak()  { cp -r "$1" "$1.bak"; }

# Navigate up N parent directories. Usage: up 3 (goes up ../../..)
up() {
    local levels=${1:-1} path=""
    for ((i=0; i<levels; i++)); do path="../$path"; done
    cd "$path" || return
}

# Search file contents recursively using rg (ripgrep) or grep. Usage: search_files "TODO"
search_files() {
    if command -v rg >/dev/null 2>&1; then
        rg -n --color=always "$1" | less -R
    else
        grep -RIn --color=always "$1" . | less -R
    fi
}

# Show internal (LAN) and external (public) IP addresses
myip() {
    echo "Internal IP:"
    ip route get 1.1.1.1 | awk '{print $7}' 2>/dev/null || echo "Not connected"
    echo "External IP:"
    curl -s ifconfig.me || echo "Unable to fetch"
}

# Quick git commit: stage all and commit with message. Usage: gcom "fix typo"
gcom()  { git add . && git commit -m "$1"; }

# Quick git commit and push in one go. Usage: lazy "quick fix"
lazy()  { git add . && git commit -m "$1" && git push; }

# Prune remote-tracking refs and delete local branches already merged into current branch
gclean() {
    git fetch -p
    git branch --merged | grep -E -v '(^\*|main|master|dev)' | xargs -r git branch -d
}

# Look up a command cheatsheet from cht.sh. Usage: cheat curl, cheat python/lambda
cheat() { curl -s "cht.sh/$1"; }

# FZF-powered interactive functions (require fzf + fd)
if command -v fzf >/dev/null 2>&1; then
    # Fuzzy-find and open a file in your editor. Usage: fe [query]
    fe() {
        local file
        file=$(fd --type f --hidden --exclude .git | fzf --query="$1" --select-1 --exit-0)
        [[ -n "$file" ]] && ${EDITOR:-vim} "$file"
    }

    # Fuzzy-find and cd into a directory. Usage: fcd [query]
    fcd() {
        local dir
        dir=$(fd --type d --hidden --exclude .git | fzf --query="$1" --select-1 --exit-0)
        [[ -n "$dir" ]] && cd "$dir"
    }

    # Fuzzy-find and kill a running process. Usage: fkill [signal]
    fkill() {
        local pid
        pid=$(ps -ef | sed 1d | fzf -m | awk '{print $2}')
        [[ -n "$pid" ]] && echo "$pid" | xargs kill -"${1:-9}"
    }

    # Fuzzy-find and preview a file with bat syntax highlighting. Usage: fshow [query]
    fshow() {
        local file
        file=$(fd --type f --hidden --exclude .git | fzf --query="$1" --select-1 --exit-0 \
            --preview "bat --color=always --style=numbers --line-range=:500 {}")
        [[ -n "$file" ]] && bat "$file"
    }
fi

#################### ALIASES ####################

# Navigation — shorthand for jumping up directories
alias ..='cd ..'                # up one level
alias ...='cd ../..'            # up two levels
alias ....='cd ../../..'        # up three levels
alias ~='cd ~'                  # home directory

# System — common shell shortcuts
alias c='clear'                                           # clear the terminal
alias cls='clear'                                         # clear (Windows muscle memory)
alias h='history'                                         # show command history
alias j='jobs -l'                                         # list background jobs with PIDs
alias path='echo -e "${PATH//:/\\n}"'                     # print PATH entries one per line
alias now='date +"%T"'                                    # current time (HH:MM:SS)
alias nowdate='date +"%d-%m-%Y"'                          # current date (DD-MM-YYYY)
alias reload='source ~/.bashrc'                           # reload this bashrc without restarting
alias please='sudo $(fc -ln -1)'                          # re-run last command with sudo
alias pathadd='export PATH="$PWD:$PATH" && echo "$PATH"'  # add current dir to PATH

# File ops — safe defaults (prompt before overwriting)
alias cp='cp -i'                                          # confirm before overwrite
alias mv='mv -i'                                          # confirm before overwrite
alias rm='rm -i'                                          # confirm before delete
alias mkdir='mkdir -pv'                                   # create parents, show what was made
command -v trash >/dev/null 2>&1 && alias rm='trash'      # use trash-cli instead of rm if available

# Listing — auto-detect best tool: ls=all files, l=short, la=all, ll=long, lt=tree
if command -v eza >/dev/null 2>&1; then
    alias ls='eza -a -1 --icons --group-directories-first'
    alias l='eza -1 --icons --group-directories-first'
    alias la='eza -a -1 --icons --group-directories-first'
    alias ll='eza -l --icons --group-directories-first --no-user --no-group --no-permissions --no-filesize --time=modified --time-style="%Y-%m-%d %H:%M"'
    alias lt='eza -T --level=2 --icons --group-directories-first'
elif command -v lsd >/dev/null 2>&1; then
    alias ls='lsd -a -1 --group-dirs=first --icon=auto'
    alias l='lsd -1 --group-dirs=first --icon=auto'
    alias la='lsd -a -1 --group-dirs=first --icon=auto'
    alias ll='lsd -l --group-dirs=first --icon=auto --blocks date,name --date "+%Y-%m-%d %H:%M"'
    alias lt='lsd --tree --depth 2 --group-dirs=first --icon=auto'
else
    alias ls='ls --color=auto -F'
    alias ll='ls -alF'
    alias la='ls -A'
    alias l='ls -1F'
    alias lt='ls -ltr'
fi
alias dir='ls -laht'                                      # detailed listing sorted by time
alias tree='tree -C'                                      # colourised tree view

# Text/IO — colourised grep (skips common build dirs), bat as cat replacement
alias grep='grep --color=auto --exclude-dir={.git,node_modules,vendor,build,dist}'
command -v bat >/dev/null 2>&1 && alias cat='bat'         # syntax-highlighted file viewer

# Archives — quick extract/compress shortcuts
alias untar='tar -xvf'                                    # extract a tarball
alias targz='tar -czvf'                                   # create a .tar.gz archive

# Monitoring — human-readable system info
alias df='df -h'                                          # disk usage (human-readable)
alias du='du -h'                                          # directory size (human-readable)
alias free='free -h'                                      # memory usage (human-readable)
alias ps='ps auxf'                                        # all processes as a tree
alias psg='ps aux | grep'                                 # search running processes
command -v htop >/dev/null 2>&1 && alias top='htop'       # interactive process viewer
if command -v netstat >/dev/null 2>&1; then
    alias ports='netstat -tulanp'                         # show listening ports
else
    command -v ss >/dev/null 2>&1 && alias ports='ss -tulpen'
fi

# Package management (distro-aware)
DISTRO=$(get_distro)
case "$DISTRO" in
    debian)
        alias install='sudo apt install'
        alias update='sudo apt update && sudo apt full-upgrade'
        alias search='apt search'
        alias remove='sudo apt remove && sudo apt autoremove'
        ;;
    redhat)
        alias install='sudo dnf install'
        alias update='sudo dnf upgrade --refresh'
        alias search='dnf search'
        alias remove='sudo dnf remove && sudo dnf autoremove'
        ;;
    arch)
        alias install='sudo pacman -S'
        alias update='sudo pacman -Syu'
        alias search='pacman -Ss'
        alias remove='sudo pacman -R'
        ;;
esac

# Git — common workflow shortcuts
alias g='git'                                             # shorthand for git
alias gs='git status'                                     # working tree status
alias gst='git status -sb'                                # short status with branch
alias ga='git add'                                        # stage files
alias gc='git commit'                                     # commit staged changes
alias gp='git push'                                       # push to remote
alias gl='git log --oneline'                              # compact log
alias gd='git diff'                                       # show unstaged changes
alias gco='git checkout'                                  # switch branch or restore files
alias gb='git branch --all'                               # list all branches
alias ggraph='git log --graph --decorate --oneline --all' # visual branch graph
alias gamend='git commit --amend --no-edit'               # amend last commit (keep message)
alias gca='git commit --amend'                            # amend last commit (edit message)
alias gcp='git cherry-pick'                               # apply a commit from another branch
alias gprune='git fetch --prune'                          # remove stale remote-tracking refs
alias guncommit='git reset --soft HEAD~1'                 # undo last commit, keep changes staged

# Docker — container management shortcuts
alias d='docker'                                          # shorthand for docker
alias dc='docker compose'                                 # shorthand for docker compose
alias dps='docker ps'                                     # list running containers
alias di='docker images'                                  # list local images
alias dclean='docker system prune -af'                    # remove all unused images/containers
alias dcu='docker compose up -d'                          # start services in background
alias dcd='docker compose down'                           # stop and remove services
alias dcb='docker compose build'                          # build service images
alias dcl='docker compose logs -f'                        # follow service logs
alias dexec='docker exec -it'                             # exec into a running container

# Networking — sensible defaults for common network tools
alias ping='ping -c 5'                                    # limit to 5 pings by default
alias wget='wget -c'                                      # resume partial downloads
alias curl='curl -L'                                      # follow redirects automatically
alias ippublic='curl -s https://ifconfig.me'              # show public IP address
alias serve='python3 -m http.server 8000'                 # quick local HTTP server on port 8000

#################### KEYBINDINGS ####################

# Ctrl+F — invoke zoxide interactive (zi) for fuzzy directory jumping
bind '"\C-f":"zi\n"' 2>/dev/null

#################### PROMPT / ENHANCEMENTS ####################

# Starship — cross-shell customisable prompt (https://starship.rs)
export STARSHIP_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/starship/starship.toml"
command -v starship >/dev/null 2>&1 && eval "$(starship init bash)"

# Zoxide — smarter cd that learns your most-used directories (https://github.com/ajeetdsouza/zoxide)
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init bash)"

#################### EXTERNAL ####################

[[ -f "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env"
[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"
[[ -f "$HOME/.deno/env" ]] && . "$HOME/.deno/env"

# Deno completion
[[ -f "$HOME/.local/share/bash-completion/completions/deno.bash" ]] && \
    source "$HOME/.local/share/bash-completion/completions/deno.bash"

# Bash aliases file (if maintained separately)
[[ -f ~/.bash_aliases ]] && . ~/.bash_aliases

#################### LOCAL OVERRIDES ####################
# Personal settings, secrets, API tokens, and machine-specific config.
# Create ~/.bashrc.local with your own exports:
#   export AWS_PROFILE=my-profile
#   export AZURE_DEVOPS_PAT=xxx
#   export ATLASSIAN_API_TOKEN=xxx
#   alias cdproject="cd /mnt/d/repos/my-project"
[[ -f ~/.bashrc.local ]] && . ~/.bashrc.local
