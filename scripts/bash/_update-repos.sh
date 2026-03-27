#!/usr/bin/env bash
# update-repos.sh — Bulk fetch/pull Git repositories (macOS + Linux)
# Bash equivalent of _update-repos.ps1 with the same parameters.
set -euo pipefail

# -------------------------------------------------------------------------
# Default root directory to scan for repositories
DEFAULT_ROOT_PATH="$HOME/repos"

# Prefix for immediate child folders to treat as repositories.
CHILD_FOLDER_PREFIX="Hydra"  # Use H for all or Htec for SLIBs
# -------------------------------------------------------------------------

# Status symbols (Unicode)
SYM_WARNING=$'\u26A0\uFE0F'      # ⚠️
SYM_ERROR=$'\u26D4'              # ⛔
SYM_SUCCESS=$'\u2705'            # ✅
SYM_FAILED=$'\U0001F534'         # 🔴
SYM_FORWARDED=$'\u23E9'          # ⏩
SYM_SKIPPED=$'\u23ED\uFE0F'      # ⏭️
SYM_INFO=$'\u2139\uFE0F'         # ℹ️
SYM_CHECK=$'\u2714'              # ✔
SYM_CROSS=$'\u2716'              # ✖
SYM_FETCHING=$'\u2B07\uFE0F'     # ⬇️
SYM_UPDATING=$'\U0001F504'       # 🔄
SYM_COMPLETE=$'\u2728'           # ✨

# ANSI colour codes
C_RESET=$'\033[0m'
C_RED=$'\033[31m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_BLUE=$'\033[34m'
C_MAGENTA=$'\033[35m'
C_CYAN=$'\033[36m'
C_WHITE=$'\033[37m'
C_BRIGHT_RED=$'\033[91m'
C_BRIGHT_GREEN=$'\033[92m'
C_BRIGHT_MAGENTA=$'\033[95m'

# Git error detection patterns
GIT_ERROR_PATTERN='error:|fatal:|CONFLICT|merge conflict|divergent branches'
STASH_CONFLICT_PATTERN='CONFLICT'

# -------------------------------------------------------------------------
# Formatting helpers
# -------------------------------------------------------------------------

fmt() {
    local text="$1" color="${2:-white}"
    case "$color" in
        red)            printf '%s%s%s' "$C_RED"            "$text" "$C_RESET" ;;
        green)          printf '%s%s%s' "$C_GREEN"          "$text" "$C_RESET" ;;
        yellow)         printf '%s%s%s' "$C_YELLOW"         "$text" "$C_RESET" ;;
        blue)           printf '%s%s%s' "$C_BLUE"           "$text" "$C_RESET" ;;
        magenta)        printf '%s%s%s' "$C_MAGENTA"        "$text" "$C_RESET" ;;
        cyan)           printf '%s%s%s' "$C_CYAN"           "$text" "$C_RESET" ;;
        bright_red)     printf '%s%s%s' "$C_BRIGHT_RED"     "$text" "$C_RESET" ;;
        bright_green)   printf '%s%s%s' "$C_BRIGHT_GREEN"   "$text" "$C_RESET" ;;
        bright_magenta) printf '%s%s%s' "$C_BRIGHT_MAGENTA" "$text" "$C_RESET" ;;
        *)              printf '%s%s%s' "$C_WHITE"          "$text" "$C_RESET" ;;
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

success_sym() { fmt "$SYM_CHECK" "green"; }
failure_sym() { fmt "$SYM_CROSS" "red"; }

get_status_icon() {
    local status="$1"
    if [[ "$status" =~ ^(Up\ to\ date|Already\ up\ to\ date)$ ]]; then
        fmt "$SYM_SUCCESS " "green"
    elif [[ "$status" =~ failed|error ]]; then
        fmt "$SYM_FAILED " "red"
    elif [[ "$status" =~ skipped|dirty ]]; then
        fmt "$SYM_SKIPPED " "yellow"
    elif [[ "$status" =~ fast-forwarded|forwarded ]]; then
        fmt "$SYM_FORWARDED " "cyan"
    else
        fmt "$SYM_INFO " "white"
    fi
}

# -------------------------------------------------------------------------
# Argument parsing
# -------------------------------------------------------------------------

ROOT_PATH="$DEFAULT_ROOT_PATH"
NO_PULL=false
SKIP_DIRTY=false
STASH_DIRTY=false
USE_REBASE=false
FETCH_ALL_REMOTES=false
VERBOSE_BRANCHES=false
PARALLEL=4
INVALID_ARGS=()

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
            root-path)
                if [[ -z "$value" ]]; then
                    if [[ $# -ge 2 ]]; then shift; value="$1"; else INVALID_ARGS+=("$arg"); shift; continue; fi
                fi
                ROOT_PATH="$value"
                ;;
            no-pull)          NO_PULL=true ;;
            skip-dirty)       SKIP_DIRTY=true ;;
            stash-dirty)      STASH_DIRTY=true ;;
            use-rebase)       USE_REBASE=true ;;
            fetch-all-remotes|fetch-all) FETCH_ALL_REMOTES=true ;;
            verbose-branches|verbose)    VERBOSE_BRANCHES=true ;;
            parallel|p)
                if [[ -z "$value" ]]; then
                    if [[ $# -ge 2 ]]; then shift; value="$1"; else INVALID_ARGS+=("$arg"); shift; continue; fi
                fi
                PARALLEL="$value"
                ;;
            help)
                show_usage
                exit 0
                ;;
            *)
                if [[ "$arg" == -* ]]; then
                    INVALID_ARGS+=("$arg")
                elif [[ "$ROOT_PATH" == "$DEFAULT_ROOT_PATH" ]]; then
                    ROOT_PATH="$arg"
                else
                    INVALID_ARGS+=("$arg")
                fi
                ;;
        esac
        shift
    done
}

show_usage() {
    cat <<'EOF'
Usage: update-repos.sh [OPTIONS] [ROOT_PATH]

Bulk fetch and pull Git repositories under a root directory.

Options:
  --root-path <path>       Directory to scan for repositories (default: ~/repos)
  --no-pull                Only fetch, don't pull changes
  --skip-dirty             Skip repositories with uncommitted changes
  --stash-dirty            Stash changes before updating, restore afterwards
  --use-rebase             Use git pull --rebase instead of --ff-only
  --fetch-all-remotes      Fetch from all remotes, not just origin
  --verbose-branches       Show REPORT table and CHANGES diffstat after processing
  --verbose                Alias for --verbose-branches
  --parallel <n>           Number of concurrent workers (default: 4, 1 for sequential)
  -p <n>                   Alias for --parallel
  --help                   Show this help message

The first positional argument is treated as --root-path if no explicit --root-path is given.
EOF
}

# -------------------------------------------------------------------------
# Repository discovery
# -------------------------------------------------------------------------

discover_repos() {
    local root="$1"
    local repos=()

    if [[ ! -d "$root" ]]; then
        warn "Root path '$root' does not exist"
        return 1
    fi

    for dir in "$root"/"${CHILD_FOLDER_PREFIX}"*/; do
        [[ -d "$dir" ]] || continue
        if [[ -d "${dir}.git" ]]; then
            # Remove trailing slash
            repos+=("${dir%/}")
        fi
    done

    if [[ ${#repos[@]} -eq 0 ]]; then
        warn "No repositories found matching '${CHILD_FOLDER_PREFIX}*' in '$root'"
        return 1
    fi

    printf '%s\n' "${repos[@]}"
}

# -------------------------------------------------------------------------
# Git operations
# -------------------------------------------------------------------------

get_repo_status() {
    local path="$1"
    local output branch dirty

    output=$(git -C "$path" status --porcelain -b 2>/dev/null) || {
        echo "(error)|false|true"
        return
    }

    local branch_line
    branch_line=$(head -1 <<< "$output")

    if [[ "$branch_line" =~ ^##\ (.+)\.\.\. ]]; then
        branch="${BASH_REMATCH[1]}"
    elif [[ "$branch_line" =~ ^##\ (.+)$ ]]; then
        local branch_name="${BASH_REMATCH[1]}"
        if [[ "$branch_name" == "HEAD (no branch)" ]]; then
            local short_sha
            short_sha=$(git -C "$path" rev-parse --short HEAD 2>/dev/null || echo "")
            if [[ -n "$short_sha" ]]; then
                branch="(detached at $short_sha)"
            else
                branch="(detached)"
            fi
        else
            branch="$branch_name"
        fi
    else
        branch="(unknown)"
    fi

    # Lines beyond the branch line indicate uncommitted changes
    local line_count
    line_count=$(wc -l <<< "$output")
    if [[ "$line_count" -gt 1 ]]; then
        dirty=true
    else
        dirty=false
    fi

    echo "${branch}|${dirty}|false"
}

git_fetch() {
    local path="$1" all="${2:-false}"

    if [[ "$all" == "true" ]]; then
        git -C "$path" fetch --all --prune >/dev/null 2>&1
    else
        git -C "$path" fetch origin --prune >/dev/null 2>&1
    fi
    return $?
}

git_pull() {
    local path="$1" branch="$2" rebase="${3:-false}"
    local pull_args output success=true
    local error_messages=() diffstat_lines=()

    if [[ "$branch" =~ ^\(detached ]]; then
        echo "false|Detached HEAD (fetched)|"
        return
    fi

    if [[ "$rebase" == "true" ]]; then
        pull_args=(pull --rebase --stat origin "$branch")
    else
        pull_args=(pull --ff-only --stat origin "$branch")
    fi

    output=$(git -C "$path" "${pull_args[@]}" 2>&1) || success=false

    while IFS= read -r line; do
        if [[ "$line" =~ $GIT_ERROR_PATTERN ]]; then
            success=false
            error_messages+=("$line")
        fi
        if [[ "$line" =~ ^[[:space:]]+[^[:space:]].*\| ]] || [[ "$line" =~ ^[[:space:]]+[0-9]+' file' ]]; then
            diffstat_lines+=("$line")
        fi
    done <<< "$output"

    local status_text
    if [[ "$success" == true ]]; then
        if [[ "$rebase" == "true" ]]; then
            status_text="Rebased"
        else
            status_text="Fast-forwarded"
        fi
    else
        if [[ ${#error_messages[@]} -gt 0 ]]; then
            status_text="Pull failed: ${error_messages[0]}"
        else
            status_text="Pull failed"
        fi
    fi

    local diffstat_joined=""
    if [[ ${#diffstat_lines[@]} -gt 0 ]]; then
        diffstat_joined=$(printf '%s\n' "${diffstat_lines[@]}")
    fi

    echo "${success}|${status_text}|${diffstat_joined}"
}

push_stash() {
    local path="$1"
    local stash_msg="WIP_$(date '+%Y%m%d-%H%M%S')"

    git -C "$path" stash push -u -m "$stash_msg" >/dev/null 2>&1

    local stash_entry
    stash_entry=$(git -C "$path" stash list 2>/dev/null | grep "$stash_msg" | head -1)

    if [[ -z "$stash_entry" ]]; then
        echo ""
        return
    fi

    # Format: "stash@{0}: On branch: message" -> "stash@{0}: message"
    local ref msg
    ref=$(echo "$stash_entry" | cut -d: -f1)
    msg=$(echo "$stash_entry" | cut -d: -f3- | sed 's/^ *//')
    echo "${ref}: ${msg}"
}

pop_stash() {
    local path="$1"
    local output
    output=$(git -C "$path" stash pop 2>&1) || true

    if echo "$output" | grep -q "$STASH_CONFLICT_PATTERN"; then
        echo "false"
    else
        echo "true"
    fi
}

# -------------------------------------------------------------------------
# Single repository processing
# -------------------------------------------------------------------------

process_repo() {
    local path="$1"
    local name
    name=$(basename "$path")

    # Check origin exists
    local remotes
    remotes=$(git -C "$path" remote 2>/dev/null)
    if ! echo "$remotes" | grep -qx 'origin'; then
        echo "NAME=${name}|BRANCH=|DIRTY=No|PULLED=No origin|STATUS=Skipped (no origin)|HASREMOTE=false|STASH=|PULL_MSG=|DIFFSTAT="
        return
    fi

    # Get branch + dirty state
    local status_raw branch dirty status_error
    status_raw=$(get_repo_status "$path")
    IFS='|' read -r branch dirty status_error <<< "$status_raw"

    # Handle dirty + skip
    if [[ "$dirty" == "true" && "$SKIP_DIRTY" == "true" ]]; then
        echo "NAME=${name}|BRANCH=${branch}|DIRTY=Yes|PULLED=Skipped|STATUS=Dirty / skipped|HASREMOTE=true|STASH=|PULL_MSG=|DIFFSTAT="
        return
    fi

    # Handle dirty + stash
    local stash_ref="" stash_msg=""
    if [[ "$dirty" == "true" && "$STASH_DIRTY" == "true" ]]; then
        stash_ref=$(push_stash "$path")
        if [[ -n "$stash_ref" ]]; then
            stash_msg="Stashed changes: ${stash_ref}"
        fi
    fi

    # Fetch
    git_fetch "$path" "$FETCH_ALL_REMOTES" || true

    local pulled="No" status_note="Fetched" pull_msg="" diffstat=""

    if [[ "$NO_PULL" == "true" ]]; then
        status_note="Fetched only"
    elif [[ "$branch" =~ ^\(detached ]]; then
        status_note="Detached HEAD (fetched)"
    else
        local pull_raw pull_success pull_status pull_diffstat
        pull_raw=$(git_pull "$path" "$branch" "$USE_REBASE")
        IFS='|' read -r pull_success pull_status pull_diffstat <<< "$pull_raw"

        status_note="$pull_status"
        if [[ "$pull_success" == "true" ]]; then
            pulled="Yes"
        else
            pull_msg="Pull failed (merge/rebase needed). Manual intervention required."
        fi
        diffstat="$pull_diffstat"
    fi

    # Pop stash if we stashed earlier
    if [[ -n "$stash_ref" ]]; then
        local stash_ref_only
        stash_ref_only=$(echo "$stash_ref" | cut -d: -f1)
        local pop_ok
        pop_ok=$(pop_stash "$path")
        if [[ "$pop_ok" == "true" ]]; then
            status_note="${status_note} (Stash ${stash_ref_only} restored)"
        else
            status_note="${status_note} (Stash ${stash_ref_only} conflicts)"
        fi

        # Re-check dirty state
        local quick_status
        quick_status=$(git -C "$path" status --porcelain 2>/dev/null)
        if [[ -n "$quick_status" ]]; then
            dirty=true
        else
            dirty=false
        fi
    fi

    local dirty_str
    if [[ "$dirty" == "true" ]]; then dirty_str="Yes"; else dirty_str="No"; fi

    echo "NAME=${name}|BRANCH=${branch}|DIRTY=${dirty_str}|PULLED=${pulled}|STATUS=${status_note}|HASREMOTE=true|STASH=${stash_msg}|PULL_MSG=${pull_msg}|DIFFSTAT=${diffstat}"
}

# -------------------------------------------------------------------------
# Result parsing helpers
# -------------------------------------------------------------------------

parse_field() {
    local result="$1" field="$2"
    echo "$result" | tr '|' '\n' | grep "^${field}=" | head -1 | sed "s/^${field}=//"
}

# -------------------------------------------------------------------------
# Output / progress
# -------------------------------------------------------------------------

print_repo_progress() {
    local result="$1" index="$2" total="$3"

    local name branch status has_remote stash_msg pull_msg dirty
    name=$(parse_field "$result" "NAME")
    branch=$(parse_field "$result" "BRANCH")
    status=$(parse_field "$result" "STATUS")
    has_remote=$(parse_field "$result" "HASREMOTE")
    stash_msg=$(parse_field "$result" "STASH")
    pull_msg=$(parse_field "$result" "PULL_MSG")

    local padded_index padded_total
    padded_index=$(printf '%02d' "$index")
    padded_total=$(printf '%02d' "$total")

    # Build progress line
    printf '%s %s %s' \
        "$(fmt "[$padded_index/$padded_total]" "white")" \
        "$(fmt "$name" "cyan")" \
        "$(fmt "($branch)" "magenta")"

    # Stash message
    if [[ -n "$stash_msg" ]]; then
        printf '\n'
        msg "  $stash_msg" "cyan"
        printf '%s %s %s' \
            "$(fmt "[$padded_index/$padded_total]" "white")" \
            "$(fmt "$name" "cyan")" \
            "$(fmt "($branch)" "magenta")"
    fi

    # Pull message
    if [[ -n "$pull_msg" ]]; then
        printf '\n'
        msg "  $pull_msg" "red"
        printf '%s %s %s' \
            "$(fmt "[$padded_index/$padded_total]" "white")" \
            "$(fmt "$name" "cyan")" \
            "$(fmt "($branch)" "magenta")"
    fi

    if [[ "$has_remote" == "false" ]]; then
        msg " $SYM_WARNING No origin" "yellow"
        return
    fi

    if [[ "$status" == "Dirty / skipped" ]]; then
        msg " $SYM_ERROR Dirty / skipped" "yellow"
        return
    fi

    local icon
    icon=$(get_status_icon "$status")
    printf ' %s%s\n' "$icon" "$status"
}

print_summary() {
    local elapsed="$1" total="$2"
    shift 2
    local results=("$@")

    printf '\n'
    msg "REPORT:" "bright_magenta"

    # Sort results by name
    local sorted
    sorted=$(printf '%s\n' "${results[@]}" | sort -t'|' -k1)

    # Check if all are up to date
    local all_up_to_date=true
    while IFS= read -r result; do
        local status
        status=$(parse_field "$result" "STATUS")
        if [[ "$status" != "Up to date" && "$status" != "Already up to date" ]]; then
            all_up_to_date=false
            break
        fi
    done <<< "$sorted"

    # Calculate column widths
    local max_name=4 max_branch=6
    while IFS= read -r result; do
        local name branch
        name=$(parse_field "$result" "NAME")
        branch=$(parse_field "$result" "BRANCH")
        [[ ${#name} -gt $max_name ]] && max_name=${#name}
        [[ ${#branch} -gt $max_branch ]] && max_branch=${#branch}
    done <<< "$sorted"

    # Header
    if [[ "$all_up_to_date" == "true" ]]; then
        printf "  %-${max_name}s  %-${max_branch}s  %-5s  %-6s\n" "Name" "Branch" "Clean" "Pulled"
        printf "  %-${max_name}s  %-${max_branch}s  %-5s  %-6s\n" \
            "$(printf '%*s' "$max_name" '' | tr ' ' '-')" \
            "$(printf '%*s' "$max_branch" '' | tr ' ' '-')" \
            "-----" "------"
    else
        printf "  %-${max_name}s  %-${max_branch}s  %-5s  %-6s  %s\n" "Name" "Branch" "Clean" "Pulled" "Status"
        printf "  %-${max_name}s  %-${max_branch}s  %-5s  %-6s  %s\n" \
            "$(printf '%*s' "$max_name" '' | tr ' ' '-')" \
            "$(printf '%*s' "$max_branch" '' | tr ' ' '-')" \
            "-----" "------" "------"
    fi

    # Rows
    local repos_with_changes=()
    while IFS= read -r result; do
        [[ -z "$result" ]] && continue
        local name branch dirty pulled status diffstat
        name=$(parse_field "$result" "NAME")
        branch=$(parse_field "$result" "BRANCH")
        dirty=$(parse_field "$result" "DIRTY")
        pulled=$(parse_field "$result" "PULLED")
        status=$(parse_field "$result" "STATUS")
        diffstat=$(parse_field "$result" "DIFFSTAT")

        # Format branch (highlight non-standard branches)
        local branch_fmt="$branch"
        if [[ "$branch" != "develop" && "$branch" != "master" && "$branch" != "main" && "$branch" != "(detached)" && -n "$branch" ]]; then
            branch_fmt=$(fmt "$branch" "magenta")
        fi

        # Symbols
        local clean_sym pulled_sym
        if [[ "$dirty" == "Yes" ]]; then clean_sym=$(failure_sym); else clean_sym=$(success_sym); fi
        if [[ "$pulled" == "Yes" ]]; then pulled_sym=$(success_sym); else pulled_sym=$(failure_sym); fi

        if [[ "$all_up_to_date" == "true" ]]; then
            printf "  %-${max_name}s  %-${max_branch}s  %s      %s\n" "$name" "$branch_fmt" "$clean_sym" "$pulled_sym"
        else
            local status_icon
            status_icon=$(get_status_icon "$status")
            printf "  %-${max_name}s  %-${max_branch}s  %s      %s       %s%s\n" "$name" "$branch_fmt" "$clean_sym" "$pulled_sym" "$status_icon" "$status"
        fi

        # Track repos with diffstat
        if [[ -n "$diffstat" ]]; then
            repos_with_changes+=("$name|$diffstat")
        fi
    done <<< "$sorted"

    # Show diffstat for repos that had changes
    if [[ ${#repos_with_changes[@]} -gt 0 ]]; then
        printf '\n'
        msg "CHANGES:" "bright_magenta"
        for entry in "${repos_with_changes[@]}"; do
            local repo_name repo_diffstat
            repo_name="${entry%%|*}"
            repo_diffstat="${entry#*|}"
            msg "  $repo_name" "cyan"
            while IFS= read -r line; do
                [[ -n "$line" ]] && msg "    $line" "white"
            done <<< "$repo_diffstat"
        done
    fi

    printf '\n'
    msg "$(printf 'Completed in %.1fs for %d repositories.' "$elapsed" "$total")" "green"
    printf '\n'
}

# -------------------------------------------------------------------------
# Parallel processing
# -------------------------------------------------------------------------

process_repos_parallel() {
    local repos=("$@")
    local total=${#repos[@]}
    local results=()
    local completed=0
    local pids=() repo_map=()
    local tmpdir
    tmpdir=$(mktemp -d)

    # Limit concurrency
    local throttle=$PARALLEL
    [[ $throttle -gt $total ]] && throttle=$total

    local running=0 repo_idx=0

    while [[ $completed -lt $total ]]; do
        # Launch jobs up to the throttle limit
        while [[ $running -lt $throttle && $repo_idx -lt $total ]]; do
            local repo="${repos[$repo_idx]}"
            local outfile="${tmpdir}/${repo_idx}.result"

            (
                process_repo "$repo" > "$outfile"
            ) &

            pids+=($!)
            repo_map+=("$repo_idx")
            ((running++)) || true
            ((repo_idx++)) || true
        done

        # Wait for any one job to finish
        for i in "${!pids[@]}"; do
            local pid="${pids[$i]}"
            if ! kill -0 "$pid" 2>/dev/null; then
                wait "$pid" 2>/dev/null || true
                local idx="${repo_map[$i]}"
                local outfile="${tmpdir}/${idx}.result"

                ((completed++)) || true
                ((running--)) || true

                local result=""
                [[ -f "$outfile" ]] && result=$(cat "$outfile")
                results+=("$result")

                print_repo_progress "$result" "$completed" "$total"

                # Remove from tracking arrays
                unset 'pids[i]'
                unset 'repo_map[i]'
                pids=("${pids[@]}")
                repo_map=("${repo_map[@]}")
                break
            fi
        done

        # Brief sleep to avoid busy-waiting
        if [[ $completed -lt $total ]]; then
            sleep 0.1
        fi
    done

    rm -rf "$tmpdir"

    # Return results via global
    COLLECTED_RESULTS=("${results[@]}")
}

process_repos_sequential() {
    local repos=("$@")
    local total=${#repos[@]}
    local results=()

    for i in "${!repos[@]}"; do
        local repo="${repos[$i]}"
        local result
        result=$(process_repo "$repo")
        results+=("$result")
        print_repo_progress "$result" "$((i + 1))" "$total"
    done

    COLLECTED_RESULTS=("${results[@]}")
}

# -------------------------------------------------------------------------
# Elapsed time helper (portable macOS + Linux)
# -------------------------------------------------------------------------

get_epoch_ms() {
    if command -v gdate >/dev/null 2>&1; then
        # macOS with coreutils
        gdate +%s%N | cut -b1-13
    elif date +%s%N >/dev/null 2>&1 && [[ "$(date +%s%N)" != *N* ]]; then
        # Linux
        date +%s%N | cut -b1-13
    else
        # macOS fallback (second precision)
        echo "$(date +%s)000"
    fi
}

# -------------------------------------------------------------------------
# Main
# -------------------------------------------------------------------------

COLLECTED_RESULTS=()

main() {
    # Validate path
    if [[ ! -d "$ROOT_PATH" ]]; then
        err "Root path '$ROOT_PATH' does not exist or is not a directory."
        exit 1
    fi

    # Discover repos
    msg "Scanning '$ROOT_PATH' for repositories starting with '${CHILD_FOLDER_PREFIX}'..." "cyan"

    local repo_list
    repo_list=$(discover_repos "$ROOT_PATH") || exit 1

    local repos=()
    while IFS= read -r repo; do
        [[ -n "$repo" ]] && repos+=("$repo")
    done <<< "$repo_list"

    local total=${#repos[@]}
    msg "Found $total repositories." "cyan"
    printf '\n'

    # Process
    local start_ms end_ms elapsed_s
    start_ms=$(get_epoch_ms)

    if [[ "$PARALLEL" -le 1 ]]; then
        process_repos_sequential "${repos[@]}"
    else
        process_repos_parallel "${repos[@]}"
    fi

    end_ms=$(get_epoch_ms)
    elapsed_s=$(awk "BEGIN { printf \"%.1f\", ($end_ms - $start_ms) / 1000 }")

    # Summary
    if [[ "$VERBOSE_BRANCHES" == "true" ]]; then
        print_summary "$elapsed_s" "$total" "${COLLECTED_RESULTS[@]}"
    else
        printf '\n'
        msg "$(printf 'Completed in %ss for %d repositories.' "$elapsed_s" "$total")" "green"
        printf '\n'
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
    msg "Run with --help for supported parameters." "yellow"
    exit 2
fi

main
