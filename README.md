# git-wtm - Git Worktree Manager

A convenient wrapper for git worktree with organized directory structure and interactive features.

## Features

- 🗂️ **Organized Structure** - Automatically organizes worktrees by repository
- 🎯 **Interactive Selection** - Use fzf for easy worktree and PR selection
- 🔄 **PR Integration** - Create worktrees directly from GitHub PRs
- 📝 **Multiple Editors** - Open worktrees in your favorite editor or AI assistant
- 🧹 **Easy Cleanup** - Remove worktrees with safety checks and automatic cleanup
- 🎨 **Beautiful Output** - Color-coded status and progress indicators

## Quick Start

### Installation

```bash
# Install to /usr/local/bin
curl -fsSL https://raw.githubusercontent.com/rinsyan0518/git-wtm/main/install.sh | bash

# Install to custom directory
curl -fsSL https://raw.githubusercontent.com/rinsyan0518/git-wtm/main/install.sh | INSTALL_DIR=~/.local/bin bash
```

### Basic Usage

```bash
# Create a worktree for a branch
git-wtm add feature-branch

# Create a worktree from a tag
git-wtm add v1.0.0

# List all worktrees
git-wtm list

# Create worktree from GitHub PR
git-wtm pr 123
git-wtm pr https://github.com/owner/repo/pull/123

# Open worktree in editor (interactive)
git-wtm edit

# Remove worktree (interactive with safety checks)
git-wtm remove

# List all worktrees with detailed status
git-wtm list
```

## Commands

| Command                    | Description                               |
| -------------------------- | ----------------------------------------- |
| `add <branch\|tag> [path]` | Create a new worktree from branch or tag  |
| `pr [number\|url]`         | Create a worktree for PR review           |
| `list`                     | List all worktrees with detailed status   |
| `path`                     | Get path of a worktree (interactive)      |
| `edit`                     | Open a worktree in editor (interactive)   |
| `ai`                       | Open a worktree in AI agent (interactive) |
| `tool <command>`           | Run custom command in selected worktree (supports `{}` placeholder) |
| `remove`                   | Remove a worktree (interactive)           |
| `prune`                    | Clean up stale worktrees                  |
| `help`                     | Show help message                         |

## Directory Structure

git-wtm organizes your worktrees in a clean, predictable structure:

```
$HOME/.git-worktree/
└── repository-name/
    ├── main/           # Main branch worktree
    ├── feature-xyz/    # Feature branch worktree
    ├── pr-123/         # PR review worktree
    └── hotfix-abc/     # Hotfix branch worktree
```

## Configuration

Configure git-wtm using environment variables:

```bash
# Base directory for all worktrees (default: $HOME/.git-worktree)
export GIT_WTM_WORKTREE_BASE_DIR="$HOME/worktrees"

# Default editor for 'git-wtm edit' (default: $EDITOR or vim)
export GIT_WTM_EDITOR="nvim"

# AI agent for 'git-wtm ai' (default: claude)
export GIT_WTM_AI="claude"
```

## Examples

### Working with Feature Branches

```bash
# Create worktree for new feature
git-wtm add feature/user-auth

# Switch to the worktree directory
cd ~/.git-worktree/my-project/feature-user-auth

# Work on your feature...

# When done, remove the worktree
git-wtm remove  # Interactive selection
```

### PR Review Workflow

```bash
# Create worktree from PR number
git-wtm pr 456

# Or from PR URL
git-wtm pr https://github.com/owner/repo/pull/456

# Review the changes
cd ~/.git-worktree/my-project/pr-456

# Clean up when review is complete
git-wtm remove
```

### Working with Tags

```bash
# Create worktree from a specific release tag
git-wtm add v1.0.0

# Create worktree from a pre-release tag
git-wtm add v2.0.0-beta.1

# The worktree is created with a new branch name 'tags-v1.0.0'
cd ~/.git-worktree/my-project/tags-v1.0.0

# Work with the tagged version...
```

### Multiple Editor Support

```bash
# Open worktree in VS Code
GIT_WTM_EDITOR="code" git-wtm edit

# Open worktree in Neovim
GIT_WTM_EDITOR="nvim" git-wtm edit

# Open worktree in AI assistant
git-wtm ai
```

### Custom Tool Commands

The `tool` command allows you to run any command in a selected worktree with `{}` placeholder support:

```bash
# Open worktree in VS Code
git-wtm tool "code {}"

# Open terminal in worktree directory
git-wtm tool "gnome-terminal --working-directory={}"

# Run tests in worktree
git-wtm tool "npm test"

# Count JavaScript files
git-wtm tool "find {} -name '*.js' | wc -l"

# Build and deploy
git-wtm tool "npm run build && npm run deploy"
```

## Requirements

- **Git** (with worktree support)
- **fzf** - For interactive selection
- **gh** (optional) - For PR management features

## Advanced Usage

### Custom Worktree Paths

```bash
# Create worktree at specific path
git-wtm add feature-branch /path/to/custom/location
```

### Batch Operations

```bash
# Show status of all worktrees
git-wtm list

# Clean up all stale references
git-wtm prune

# Interactive PR selection (requires gh)
git-wtm pr  # Shows list of open PRs
```

### Shell Integration

Add to your shell profile for enhanced experience:

```bash
# Function to cd into selected worktree
gwcd() {
    local path=$(git-wtm path)
    [[ -n "$path" ]] && cd "$path"
}
```

## Tips & Tricks

- Use `git-wtm list` to get an overview of all your worktrees
- The `git-wtm edit` command respects your `$GIT_WTM_EDITOR` setting
- PR worktrees are automatically named `pr-<number>` for easy identification
- Safety checks prevent accidental deletion of worktrees with uncommitted changes
- Empty parent directories are automatically cleaned up after worktree removal

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
