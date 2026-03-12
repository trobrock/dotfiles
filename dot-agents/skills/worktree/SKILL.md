---
name: worktree
description: Manage git worktrees with Worktrunk and tmux window integration. Create worktrees with dedicated tmux windows, clean up merged branches, open dev servers in the browser, and spawn parallel AI agents in separate worktrees.
---

# Worktree Management

Manage git worktrees using [Worktrunk](https://worktrunk.dev/) (`wt`) with tmux window integration. Worktrunk handles worktree creation, environment setup (via project hooks), and lifecycle management. This skill adds tmux window orchestration and parallel agent spawning on top.

## Prerequisites

- `wt` (Worktrunk) is installed with shell integration
- `tmux` is running (check with `$TMUX` env var)
- Project hooks in `.config/wt.toml` handle environment setup automatically (dependency installation, port assignment, database provisioning)

## Key Concepts

- **Worktree paths** follow the pattern `<repo>.<branch>` as siblings of the main repo directory
- **Ports** are deterministic per branch via `hash_port` (range 10000-19999) -- no collisions, stable across machines
- **`wt list --format=json`** is the authoritative source for worktree paths, URLs, and status
- The agent (you) should **stay in your current working directory** -- operate on remote tmux windows via `tmux send-keys`, never `cd` into a different worktree

## Operations

### 1. Create Worktree + Tmux Window

Create a new worktree and open a dedicated tmux window for it. Worktrunk hooks handle all environment setup (copy-ignored files, mise.local.toml generation, bundle/yarn install, bin/setup).

**Preferred: Use `wtc --tmux`** to create a worktree with an opencode session in a detached tmux window without affecting your current shell:

```bash
wtc --tmux "<branch>"
```

This handles branch existence checks, `--create` flag, tmux window creation, and opencode launch automatically. See [Spawn Parallel AI Agent](#4-spawn-parallel-ai-agent-in-a-worktree) for full usage.

**Manual alternative** (when you need a worktree without opencode, or need to run different commands):

```bash
# Check if the branch already exists (local or remote)
branch_exists=$(git branch --list "<branch>" || git ls-remote --heads origin "<branch>")

# Create the worktree (--create only if branch is new)
if [ -z "$branch_exists" ]; then
  wt switch --create "<branch>"
else
  wt switch "<branch>"
fi
```

Wait for the switch to complete, then get the worktree path and create a tmux window:

```bash
# Get worktree path from wt list
worktree_path=$(wt list --format=json | jq -r '.[] | select(.branch == "<branch>") | .path')

# Create a tmux window named after the branch, rooted in the worktree
tmux new-window -n "<branch>" -c "$worktree_path"
```

After creating the window, **switch back to your original window** so you remain in your current context:

```bash
# Switch back to the window you were on (use the window name or index you noted before)
tmux select-window -t ":<original_window>"
```

**Important:** `wt switch` changes the shell's working directory via shell integration. After creating the worktree, you need to return to your original directory. Run `wt switch main` (or whatever branch you were on) to get back to where you started. Alternatively, note your current branch with `git branch --show-current` before starting.

### 2. Clean Up Worktrees

#### Remove a single worktree

Close the tmux window and remove the worktree + branch:

```bash
# Kill the tmux window (suppressing errors if it doesn't exist)
tmux kill-window -t ":<branch>" 2>/dev/null || true

# Remove the worktree and delete the branch
wt remove "<branch>" -D
```

The `-D` flag force-deletes the local branch even if it has unmerged changes.

#### Merge a PR and clean up (the `wtm` pattern)

For a branch with an open PR that's ready to merge:

```bash
# From the worktree's directory (or via tmux send-keys)
gh pr merge --admin
wt remove -D
git pull
```

#### Bulk prune merged worktrees

Remove all worktrees whose branches are already merged into the default branch:

```bash
wt step prune --dry-run  # preview first
wt step prune            # remove them
```

### 3. Open Worktree in Browser

Look up the worktree's dev server URL and open it:

```bash
# Get the URL from wt list
url=$(wt list --format=json | jq -r '.[] | select(.branch == "<branch>") | .url')

# Open in the default browser (macOS)
open "$url"
```

The URL pattern for Portal projects is `http://huntress.localhost:<hash_port>`. The port is deterministic per branch name.

### 4. Spawn Parallel AI Agent in a Worktree

Use the `wtc --tmux` command to create a worktree with a dedicated tmux window and launch an independent opencode session in it. This lets you delegate a task to a parallel agent while continuing your own work.

**IMPORTANT:** Always use `wtc --tmux` for spawning agents. Never run `wt switch` in the current shell to create agent worktrees — it renames the current tmux window and changes the working directory via shell integration, contaminating your session.

#### Writing the prompt

Write prompts using a heredoc with a **single-quoted delimiter** (`<<'PROMPT'`) to avoid shell expansion. This makes quotes, backticks, `$variables`, and all special characters safe inside the prompt body:

```bash
wtc --tmux <branch> <<'PROMPT'
Your detailed task description here.
Any "quotes", $variables, `backticks`, and special chars are safe.
PROMPT
```

#### Prompt sources

`wtc` accepts prompts from three sources (in priority order):

1. **Positional argument** (short prompts): `wtc --tmux <branch> "Fix the auth bug"`
2. **File** (`-f`): `wtc --tmux <branch> -f /path/to/prompt.txt`
3. **Stdin / heredoc** (detailed prompts): pipe or heredoc as shown above

#### Options

- `--tmux` — spawn in a detached tmux window (required for parallel agents)
- `--name <win>` — custom tmux window name (defaults to last segment of branch name)
- `--plan` — launch opencode in plan mode
- `-f <file>` — read prompt from a file

#### Examples

```bash
# Spawn an agent with an inline prompt
wtc --tmux feature-branch "Fix the auth bug in the login controller"

# Spawn with a custom window name
wtc --tmux --name auth feature-branch "Fix the auth bug"

# Spawn in plan mode (read-only)
wtc --tmux --plan feature-branch "Investigate the auth flow"

# Spawn with a detailed heredoc prompt
wtc --tmux feature-branch <<'PROMPT'
Implement the SORT command for the ES|QL parser.
Only support SORT on aggregation (STATS) queries.

Key files:
- lib/esql/parser.rb
- lib/esql/ast.rb
PROMPT

# Spawn with a prompt file
wtc --tmux feature-branch -f /tmp/detailed-prompt.txt
```

After spawning, `wtc` prints the tmux window name and how to connect:

```
Spawned in tmux window 'auth' on branch 'feature-branch'
Connect: tmux select-window -t ":auth"
```

The agent runs independently. You do not need to wait for it to finish.

#### Spawning multiple parallel agents

Call `wtc --tmux` once per agent. Each call is independent and does not affect your current shell:

```bash
wtc --tmux --name sort sc-new-story-esql-sort-command <<'PROMPT'
Implement SORT command for the ES|QL parser...
PROMPT

wtc --tmux --name bypass sc-new-story-ai-search-esql-bypass <<'PROMPT'
Detect raw ES|QL in AI search and bypass the LLM...
PROMPT

wtc --tmux --name timerange sc-new-story-nlq-time-range <<'PROMPT'
Add TIME_RANGE extraction to NaturalLanguageQuery...
PROMPT
```

## Querying Worktree Status

Use `wt list --format=json` to get structured data about all worktrees. Each entry includes:

| Field | Description |
|-------|-------------|
| `branch` | Branch name |
| `path` | Absolute filesystem path |
| `url` | Dev server URL (from project `[list]` config) |
| `url_active` | Whether the dev server is responding |
| `is_current` | Whether this is the current worktree |
| `is_main` | Whether this is the main/primary worktree |
| `working_tree.staged` | Has staged changes |
| `working_tree.modified` | Has unstaged modifications |
| `working_tree.untracked` | Has untracked files |
| `main_state` | Relationship to main: `is_main`, `ahead`, `behind`, `diverged` |
| `remote.ahead` / `remote.behind` | Commits ahead/behind remote tracking branch |

## When to Use This Skill

- User asks to create a worktree, branch environment, or parallel workspace
- User asks to spin up or launch a parallel agent/task
- User asks to clean up, remove, or prune worktrees
- User asks to open a worktree's dev server in the browser
- User asks to list or check the status of active worktrees
- User asks about worktree ports or URLs
