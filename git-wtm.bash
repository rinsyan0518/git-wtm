#!/bin/bash

# git-wtm: Git Worktree Manager
# A convenient wrapper for git worktree with organized directory structure

set -euo pipefail

# Configuration
SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME
readonly GIT_WTM_WORKTREE_BASE_DIR="${GIT_WTM_WORKTREE_BASE_DIR:-$HOME/.git-worktree}"
readonly GIT_WTM_EDITOR="${GIT_WTM_EDITOR:-${EDITOR:-vim}}"
readonly GIT_WTM_AI="${GIT_WTM_AI:-claude}"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# ============================================================================
# Logging functions
# ============================================================================

# Print formatted info message
# Args: message
info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Print formatted success message
# Args: message
success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Print formatted warning message
# Args: message
warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Print formatted error message to stderr
# Args: message
error() {
    echo -e "${RED}✗${NC} $1" >&2
}

# ============================================================================
# Dependency checking functions
# ============================================================================

# Check if fzf is installed and available
require_fzf() {
    if ! command -v fzf >/dev/null 2>&1; then
        error "fzf is required but not installed"
        echo "Install fzf: https://github.com/junegunn/fzf#installation"
        exit 1
    fi
}

# Check if GitHub CLI is installed and available
require_gh() {
    if ! command -v gh >/dev/null 2>&1; then
        error "GitHub CLI (gh) is required for PR commands"
        echo "Install gh: https://cli.github.com/"
        exit 1
    fi
}

# Check if fzf is installed and available
# Ensure we're running inside a git repository
# Exits with error if not in a git repository
ensure_git_repo() {
    if ! command -v git >/dev/null 2>&1; then
        echo "Git is required but not installed"
        exit 1
    fi

    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        echo -e "${RED}Error: Not in a git repository${NC}" >&2
        exit 1
    fi
}

# Display help information and usage examples
usage() {
    cat << EOF
$SCRIPT_NAME - Git Worktree Manager

USAGE:
    $SCRIPT_NAME <command> [options]

COMMANDS:
    add <branch|tag> [path]    Create a new worktree from branch or tag
    pr [number|url]            Create a worktree for PR review
    list                       List all worktrees
    path                       Get path of a worktree (interactive)
    edit                       Open a worktree in editor (interactive)
    ai                         Open a worktree in AI (interactive)
    tool <command>             Run custom command in selected worktree (supports {} placeholder)
    remove                     Remove a worktree (interactive)
    prune                      Clean up stale worktrees
    status                     Show status of all worktrees
    help                       Show this help message

DIRECTORY STRUCTURE:
    ${GIT_WTM_WORKTREE_BASE_DIR}/\$REPOSITORY_NAME/\$BRANCH_NAME/
    ${GIT_WTM_WORKTREE_BASE_DIR}/\$REPOSITORY_NAME/pr-\$NUMBER/

EXAMPLES:
    $SCRIPT_NAME add feature-branch
    $SCRIPT_NAME add v1.0.0       # Create worktree from tag
    $SCRIPT_NAME pr 123
    $SCRIPT_NAME pr https://github.com/owner/repo/pull/123
    $SCRIPT_NAME pr              # Interactive PR selection (requires gh CLI)
    $SCRIPT_NAME list
    $SCRIPT_NAME path
    $SCRIPT_NAME edit            # Open worktree in ${GIT_WTM_EDITOR}
    $SCRIPT_NAME ai              # Open worktree in ${GIT_WTM_AI}
    $SCRIPT_NAME tool "code {}"  # Open worktree in VS Code (supports {} placeholder)
    $SCRIPT_NAME remove

ENVIRONMENTS:
    \$GIT_WTM_WORKTREE_BASE_DIR: ${GIT_WTM_WORKTREE_BASE_DIR}
    \$GIT_WTM_EDITOR:            ${GIT_WTM_EDITOR}
    \$GIT_WTM_AI:                ${GIT_WTM_AI}
EOF
}

# ============================================================================
# Main entry point
# ============================================================================

# Main entry point - parses commands and routes to appropriate handlers
# Args: all command line arguments
main() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi

    local command="$1"
    shift

    case "$command" in
        add)
            cmd_add "$@"
            ;;
        pr)
            cmd_pr "$@"
            ;;
        list|ls)
            cmd_list "$@"
            ;;
        path)
            cmd_path "$@"
            ;;
        edit)
            cmd_run_external_command "${GIT_WTM_EDITOR}" "$@"
            ;;
        ai)
            cmd_run_external_command "${GIT_WTM_AI}" "$@"
            ;;
        tool)
            cmd_run_external_command "$@"
            ;;
        remove|rm)
            cmd_remove "$@"
            ;;
        prune)
            cmd_prune "$@"
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown command '$command'${NC}" >&2
            usage
            exit 1
            ;;
    esac
}

# ============================================================================
# Command implementations
# ============================================================================

# Create a new worktree for the specified branch
# Args: branch_name [custom_path]
cmd_add() {
    ensure_git_repo

    # Validate arguments
    if [[ $# -eq 0 ]]; then
        error "Branch name is required"
        return 1
    fi

    local branch="$1"
    if [[ -z "$branch" || "$branch" =~ ^[[:space:]]*$ ]]; then
        error "Branch name cannot be empty or whitespace"
        return 1
    fi

    local custom_path="${2:-}"
    local worktree_path

    # Determine worktree path
    if [[ -n "$custom_path" ]]; then
        worktree_path="$custom_path"
    else
        worktree_path=$(get_worktree_path "$branch")
    fi

    # Check if worktree already exists
    if [[ -d "$worktree_path" ]]; then
        error "Worktree already exists: $worktree_path"
        return 1
    fi

    # Create base directory
    local worktree_base
    worktree_base=$(get_worktree_base)
    mkdir -p "$worktree_base"

    info "Creating worktree for branch '$branch' at: $worktree_path"

    # Create worktree with fallback strategies
    if create_worktree_with_fallback "$worktree_path" "$branch"; then
        info "Worktree location: $worktree_path"
        return 0
    else
        return 1
    fi
}

# Create a worktree for PR review
# Args: [pr_number_or_url] (interactive selection if no args)
cmd_pr() {
    ensure_git_repo
    require_gh
    require_fzf

    local pr_number

    if [[ $# -eq 0 ]]; then
        # Interactive selection mode
        if pr_number=$(handle_interactive_pr_selection); then
            create_pr_worktree "$pr_number"
        else
            return 1
        fi
    else
        # Argument provided mode
        if pr_number=$(process_pr_argument "$1"); then
            create_pr_worktree "$pr_number"
        else
            return 1
        fi
    fi
}

# Get the path of a selected worktree (interactive)
# Outputs: worktree path to stdout
cmd_path() {
    ensure_git_repo
    require_fzf

    local selected_path
    local status
    selected_path=$(select_worktree "Get worktree path")
    status=$?

    if [[ $status -ne 0 ]]; then
        return 1
    fi

    echo "$selected_path"
}

# Open a selected worktree in an external command (editor, AI, etc.)
# Args: command_name
# Returns: 0 on success, 1 on failure
cmd_run_external_command() {
    ensure_git_repo
    require_fzf

    local cmd="${1}"

    local selected_path
    local status
    selected_path=$(select_worktree "Open worktree")
    status=$?

    if [[ $status -ne 0 ]]; then
        return 1
    fi

    info "Opening worktree: $selected_path"

    cd "$selected_path"

    local expanded_cmd
    expanded_cmd="${cmd//\{\}/$selected_path}"

    # Execute the external command in the worktree directory
    eval "${expanded_cmd}"
}

# Remove a selected worktree (interactive with confirmation)
# Includes safety checks for current/main worktree
cmd_remove() {
    ensure_git_repo
    require_fzf

    local selected_path
    local status
    selected_path=$(select_worktree "Remove worktree")
    status=$?

    if [[ $status -ne 0 ]]; then
        return 0
    fi

    # Check if we're trying to remove the main worktree
    local main_worktree
    main_worktree=$(git rev-parse --show-toplevel)
    if [[ "$selected_path" == "$main_worktree" ]]; then
        error "Cannot remove the main worktree"
        return 1
    fi

    # Check if we're currently in the worktree to be removed
    if is_current_worktree "$selected_path"; then
        error "Cannot remove the current worktree. Please switch to another worktree first."
        return 1
    fi

    # Check for uncommitted changes
    if has_git_changes "$selected_path"; then
        warn "Worktree has uncommitted changes:"
        echo -e "  Path: ${BLUE}$selected_path${NC}"
        echo
        echo -n "Are you sure you want to remove it? [y/N]: "
        read -r confirmation
        if [[ "$confirmation" != "y" && "$confirmation" != "Y" ]]; then
            info "Operation cancelled"
            return 0
        fi
    fi

    info "Removing worktree: $selected_path"

    # Remove worktree
    if git worktree remove "$selected_path" --force 2>/dev/null; then
        success "Worktree removed successfully"

        # Try to remove empty parent directories
        local parent_dir
        parent_dir=$(dirname "$selected_path")
        if [[ -d "$parent_dir" ]] && [[ -z "$(ls -A "$parent_dir" 2>/dev/null)" ]]; then
            rmdir "$parent_dir" 2>/dev/null && info "Removed empty directory: $parent_dir"
        fi
    else
        error "Failed to remove worktree. You may need to remove it manually:"
        echo "  git worktree remove '$selected_path' --force"
        return 1
    fi
}

# Clean up stale worktree references and empty directories
cmd_prune() {
    ensure_git_repo

    info "Cleaning up stale worktree references..."

    # Run git worktree prune
    if git worktree prune --verbose; then
        success "Stale worktree references cleaned up"
    else
        warn "No stale worktree references found or cleanup failed"
    fi

    # Also clean up empty directories in our managed structure
    local worktree_base
    worktree_base=$(get_worktree_base)

    if [[ -d "$worktree_base" ]]; then
        info "Checking for empty directories in: $worktree_base"

        # Find and remove empty directories
        local removed_count=0
        while IFS= read -r -d '' empty_dir; do
            if rmdir "$empty_dir" 2>/dev/null; then
                info "Removed empty directory: $empty_dir"
                ((removed_count++))
            fi
        done < <(find "$worktree_base" -type d -empty -print0 2>/dev/null)

        if [[ $removed_count -eq 0 ]]; then
            info "No empty directories found"
        else
            success "Removed $removed_count empty directories"
        fi
    fi
}

# List all worktrees with detailed status information
cmd_list() {
    ensure_git_repo

    local worktrees
    worktrees=$(git worktree list --porcelain)

    if [[ -z "$worktrees" ]]; then
        warn "No worktrees found"
        return 0
    fi

    echo -e "${BLUE}Repository: $(get_repo_name)${NC}"
    echo

    # Parse worktrees
    parse_worktree_porcelain "list_worktree_callback" "$worktrees"
}

# ============================================================================
# Core worktree parsing and utility functions
# ============================================================================

# Core worktree parsing functions

# Parse git worktree porcelain output and execute callback for each entry
# Args: callback_function worktree_data
parse_worktree_porcelain() {
    local callback_func="$1"
    local worktrees="$2"

    local current_path="" current_branch="" current_commit="" is_bare=false

    while IFS= read -r line; do
        if [[ "$line" =~ ^worktree\ (.+) ]]; then
            current_path="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^branch\ refs/heads/(.+) ]]; then
            current_branch="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^HEAD\ ([a-f0-9]+) ]]; then
            current_commit="${BASH_REMATCH[1]}"
        elif [[ "$line" == "bare" ]]; then
            is_bare=true
        elif [[ -z "$line" ]] && [[ -n "$current_path" ]]; then
            # End of worktree entry, process it
            "$callback_func" "$current_path" "$current_branch" "$current_commit" "$is_bare"

            # Reset variables
            current_path="" current_branch="" current_commit="" is_bare=false
        fi
    done <<< "$worktrees"

    # Process the last entry if it exists (no trailing empty line)
    if [[ -n "$current_path" ]]; then
        "$callback_func" "$current_path" "$current_branch" "$current_commit" "$is_bare"
    fi
}

# Check if the given path is the current worktree
# Args: worktree_path
# Returns: 0 if current worktree, 1 otherwise
is_current_worktree() {
    local path="$1"
    local current_pwd
    current_pwd=$(pwd)
    [[ "$path" == "$current_pwd" ]] || [[ "$current_pwd" == "$path"* ]]
}

# Check if worktree has any uncommitted changes
# Args: worktree_path
# Returns: 0 if changes exist, 1 if clean
has_git_changes() {
    local worktree_path="$1"

    if [[ ! -d "$worktree_path" ]]; then
        return 1
    fi

    # Use git status porcelain to check all changes at once
    local status_output
    if ! status_output=$(execute_git_in_worktree "$worktree_path" status --porcelain); then
        return 1
    fi

    # If status output is not empty, there are changes
    [[ -n "$status_output" ]]
}

# Get formatted git status string for worktree
# Args: worktree_path
# Outputs: colored status string
get_git_status() {
    local worktree_path="$1"
    local git_status="" has_changes=false

    if [[ ! -d "$worktree_path" ]]; then
        echo "${RED}missing directory${NC}"
        return
    fi

    # Use git status porcelain for efficient status parsing
    local status_output modified_count=0 staged_count=0 untracked_count=0
    if status_output=$(execute_git_in_worktree "$worktree_path" status --porcelain); then
        # Process lines using compatible while loop instead of readarray
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            case "${line:0:2}" in
                ' M'|' D'|'??') ((untracked_count++)) ;;
                'M '|'A '|'D '|'R '|'C ') ((staged_count++)) ;;
                'MM'|'AM'|'AD'|'MD'|'DM') ((modified_count++)); ((staged_count++)) ;;
                *) ((modified_count++)) ;;
            esac
        done <<< "$status_output"
    fi

    # Build status string based on counts
    if [[ $modified_count -gt 0 ]]; then
        git_status+="${YELLOW}modified${NC} "
        has_changes=true
    fi

    if [[ $staged_count -gt 0 ]]; then
        git_status+="${GREEN}staged${NC} "
        has_changes=true
    fi

    if [[ $untracked_count -gt 0 ]]; then
        git_status+="${RED}untracked($untracked_count)${NC} "
        has_changes=true
    fi

    if $has_changes; then
        echo "$git_status"
    else
        echo "${GREEN}clean${NC}"
    fi
}

# ============================================================================
# Basic utility functions
# ============================================================================

# Helper function to execute git commands in a specific worktree directory
# Args: worktree_path git_command [args...]
# Returns: git command exit code
execute_git_in_worktree() {
    local worktree_path="$1"
    shift

    if [[ ! -d "$worktree_path" ]]; then
        return 1
    fi

    (cd "$worktree_path" && git "$@" 2>/dev/null)
}

# Extract repository name from remote URL or fallback to directory name
# Returns: repository name string
get_repo_name() {
    local repo_name

    # Try to get repository name from remote URL
    if git remote get-url origin >/dev/null 2>&1; then
        repo_name=$(git remote get-url origin | sed 's|.*[/:]||; s|\.git$||; s|/$||')
    else
        # Fallback to git root directory name
        repo_name=$(basename "$(git rev-parse --show-toplevel)")
    fi

    echo "$repo_name"
}

# Get the base directory path for worktrees of current repository
# Returns: absolute path to worktree base directory
get_worktree_base() {
    local repo_name
    repo_name=$(get_repo_name)
    echo "$GIT_WTM_WORKTREE_BASE_DIR/$repo_name"
}

# Generate worktree directory path for a given branch
# Args: branch_name
# Returns: absolute path for branch worktree
get_worktree_path() {
    local branch="$1"
    local worktree_base
    worktree_base=$(get_worktree_base)

    # Sanitize branch name for filesystem (replace problematic chars)
    local sanitized_branch
    sanitized_branch=$(echo "$branch" | sed -e 's|[/:]|-|g' -e 's|[<>"\|?*]|_|g')

    echo "$worktree_base/$sanitized_branch"
}

# Callback function for detailed worktree list output
# Args: path branch commit is_bare
list_worktree_callback() {
    local current_path="$1" current_branch="$2" current_commit="$3" is_bare="$4"

    # Only show non-bare worktrees
    if ! $is_bare; then
        local status_icon="📂" status_color="$NC" status_text=""

        # Check if it's the current worktree
        if is_current_worktree "$current_path"; then
            status_icon="📍"
            status_color="$GREEN"
            status_text=" (current)"
        fi

        # Show branch and path
        echo -e "${status_color}${status_icon} ${current_branch:-detached}${status_text}${NC}"
        echo -e "   Path: $current_path"

        # Show git status
        local git_status
        git_status=$(get_git_status "$current_path")
        echo -e "   Status: $git_status"

        echo
    fi
}

# Callback function for formatting worktree selection list
# Args: path branch commit is_bare
selection_worktree_callback() {
    local current_path="$1" current_branch="$2" current_commit="$3" is_bare="$4"

    # Only output non-bare worktrees
    if ! $is_bare; then
        local status_prefix=""

        # Mark current worktree
        if is_current_worktree "$current_path"; then
            status_prefix="[*] "
        else
            status_prefix="    "
        fi

        printf "%s%s\t%s\n" "$status_prefix" "${current_branch:-detached}" "$current_path"
    fi
}

# Get formatted list of worktrees for interactive selection
# Returns: formatted worktree list for fzf
get_worktrees_for_selection() {
    local worktrees
    worktrees=$(git worktree list --porcelain)

    if [[ -z "$worktrees" ]]; then
        return 1
    fi

    parse_worktree_porcelain "selection_worktree_callback" "$worktrees"
}

# Interactive worktree selection using fzf
# Args: [prompt_text]
# Returns: selected worktree path
select_worktree() {
    local prompt="${1:-Select a worktree}"

    local worktree_list
    worktree_list=$(get_worktrees_for_selection)

    if [[ -z "$worktree_list" ]]; then
        error "No worktrees available"
        return 1
    fi

    local selected
    selected=$(echo "$worktree_list" | fzf --prompt="$prompt > " --height=15 --border)

    if [[ -z "$selected" ]]; then
        error "No worktree selected"
        return 1
    fi

    # Extract path after the tab delimiter
    local selected_path
    selected_path=$(echo "$selected" | cut -d$'\t' -f2)

    if [[ ! -d "$selected_path" ]]; then
        error "Worktree directory does not exist: $selected_path"
        return 1
    fi

    echo "$selected_path"
}

# Create worktree with multiple fallback strategies
# Args: worktree_path branch_name
# Returns: 0 on success, 1 on failure
create_worktree_with_fallback() {
    local worktree_path="$1"
    local branch="$2"

    # Strategy 1: Create from tag
    if git show-ref --verify --quiet "refs/tags/$branch"; then
        local tag_branch="tags-$branch"
        if git worktree add "$worktree_path" -b "$tag_branch" "$branch"; then
            success "Created worktree from tag '$branch' as branch '$tag_branch'"
            return 0
        else
            error "Failed to create worktree from tag"
            return 1
        fi
    fi

    # Strategy 2: Use existing branch
    if git worktree add "$worktree_path" "$branch" 2>/dev/null; then
        success "Worktree created successfully"
        return 0
    fi

    # Strategy 3: Create new local branch
    if git worktree add "$worktree_path" -b "$branch" 2>/dev/null; then
        success "Created new branch '$branch' and worktree"
        return 0
    fi

    # Strategy 4: Create from remote branch
    if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
        if git worktree add "$worktree_path" -b "$branch" "origin/$branch"; then
            success "Created worktree from remote branch 'origin/$branch'"
            return 0
        else
            error "Failed to create worktree from remote branch"
            return 1
        fi
    else
        error "Branch '$branch' not found locally, remotely, or as tag"
        return 1
    fi
}

# Extract PR number from various input formats
# Args: input (number or GitHub PR URL)
# Returns: PR number or fails with exit code 1
parse_pr_number() {
    local input="$1"

    # If it's already a number, return it
    if [[ "$input" =~ ^[0-9]+$ ]]; then
        echo "$input"
        return 0
    fi

    # Try to extract PR number from GitHub URL
    if [[ "$input" =~ /pull/([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi

    # No valid PR number found
    return 1
}

# Generate worktree path for PR review
# Args: pr_number
# Returns: absolute path for PR worktree
get_pr_worktree_path() {
    local pr_number="$1"
    local worktree_base
    worktree_base=$(get_worktree_base)
    echo "$worktree_base/pr-$pr_number"
}

# Create and setup worktree for PR review
# Args: pr_number
# Fetches PR branch and creates worktree
create_pr_worktree() {
    local pr_number="$1"
    local worktree_path
    worktree_path=$(get_pr_worktree_path "$pr_number")

    # Check if worktree already exists
    if [[ -d "$worktree_path" ]]; then
        success "PR worktree already exists: $worktree_path"
        echo "To switch to this worktree, run:"
        echo -e "${BLUE}cd '$worktree_path'${NC}"
        return 0
    fi

    info "Creating worktree for PR #$pr_number..."

    # Create base directory if it doesn't exist
    local worktree_base
    worktree_base=$(get_worktree_base)
    mkdir -p "$worktree_base"

    # Fetch PR using GitHub's pull request refs
    info "Fetching PR #$pr_number from GitHub..."
    if git fetch origin "pull/$pr_number/head:pr-$pr_number" 2>/dev/null; then
        info "Successfully fetched PR branch"
    else
        error "Failed to fetch PR #$pr_number. Make sure it exists and you have access."
        return 1
    fi

    # Create worktree
    if git worktree add "$worktree_path" "pr-$pr_number"; then
        success "PR #$pr_number worktree created at: $worktree_path"
        echo "To switch to this worktree, run:"
        echo -e "${BLUE}cd '$worktree_path'${NC}"
    else
        error "Failed to create worktree for PR #$pr_number"
        # Clean up the branch if worktree creation failed
        git branch -D "pr-$pr_number" 2>/dev/null
        return 1
    fi
}

# Handle interactive PR selection using GitHub CLI
# Returns: PR number on success, empty on failure/cancellation
handle_interactive_pr_selection() {
    info "Fetching open PRs..."
    local pr_list
    pr_list=$(gh pr list --json number,title --template '{{range .}}{{.number}} - {{.title}}{{"\n"}}{{end}}' 2>/dev/null)

    if [[ -z "$pr_list" ]]; then
        warn "No open PRs found or failed to fetch PR list"
        return 1
    fi

    local selected
    selected=$(echo "$pr_list" | fzf --prompt="Select PR > " --height=15 --border)

    if [[ -n "$selected" ]]; then
        echo "$selected" | cut -d' ' -f1
        return 0
    else
        warn "No PR selected"
        return 1
    fi
}

# Process PR input argument and extract PR number
# Args: pr_input
# Returns: 0 on success with PR number echoed, 1 on failure
process_pr_argument() {
    local pr_input="$1"

    # Validate input is not empty
    if [[ -z "$pr_input" || "$pr_input" =~ ^[[:space:]]*$ ]]; then
        error "PR number or URL cannot be empty"
        return 1
    fi

    local pr_number
    if ! pr_number=$(parse_pr_number "$pr_input"); then
        error "Invalid PR number or URL: $pr_input"
        echo "Expected: PR number (e.g., 123) or GitHub PR URL"
        return 1
    fi

    echo "$pr_number"
    return 0
}

# Run main function
main "$@"
