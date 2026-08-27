---
description: Commit, push, open a PR, wait for checks, and merge
---

Ship the current branch through to merge. The user has pre-authorized every git/gh action in this workflow — do not ask for confirmation before committing, pushing, creating, or merging the PR. Do not stop after an intermediate milestone like creating a branch, committing, pushing, opening a PR, or seeing checks pending; continue automatically through checks and merge unless a guardrail below explicitly says to stop and ask.

Use project-specific judgment for tests, PR wording, merge strategy, and failure diagnosis. This prompt is guidance, not a rigid state machine. Keep the non-negotiable guardrails, and avoid known mechanical retry loops.

## Preflight

- `git status` + `git diff` + `git log -5 --oneline` in parallel to see pending changes and recent commit-message style.
- If the current branch is `main` or `master`:
  - If the working tree is clean, stop — there is nothing to ship.
  - Otherwise, derive a short kebab-case feature branch name from the pending diff (e.g. `fix/null-guard-booking-total`, `feat/guest-export-csv`). Match any branch-prefix convention visible in recent branches (`git branch -a --sort=-committerdate | head -20`).
  - Create and switch to it with `git switch -c <name>`. Do **not** stash, reset, or discard any changes — the uncommitted work moves with the new branch.
  - Do not pause after creating the branch. Continue directly to committing, pushing, opening the PR, waiting for checks, and merging.

## 1. Commit pending changes

- If the working tree is clean, skip this step.
- Stage files by name (never `git add -A` or `git add .`; never `-f`). Skip anything that looks like secrets (`.env`, credentials, keys).
- Write a commit message matching the repo's recent style. Focus on the *why*. No Claude co-author trailer unless the repo's recent history uses one.
- Never `--amend`, never `--no-verify`. If a pre-commit hook fails: fix the underlying issue, re-stage, create a NEW commit (not an amend).

## 2. Push

- If no upstream is set, push with `-u origin <branch>`.
- Never `--force`, never `--force-with-lease`, never `--no-verify`.

## 3. Open or find the PR

- Do not run `gh pr view` until you have a PR number/URL. Before a PR exists it often fails and causes wasted retries.
- Discover existing PRs by current branch first: `gh pr list --head "$(git branch --show-current)" --state all --json number,url,state,isDraft,title`.
  - If there is an open PR for this branch, use it.
  - If the only PR is closed/merged, diagnose whether this branch was already shipped before creating anything new.
  - If more than one plausible PR appears, stop and ask.
- If no PR exists, create one against the repo's default branch. Title < 70 chars. Body has a `## Summary` bullet list and a `## Test plan` checklist. Derive both from the actual diff across all commits on the branch (not just the latest).

## 4. Wait for checks

- Prefer the `monitor_github_pr_checks` tool over manual `gh pr checks` polling. Start one monitor for the PR and wait for Pi to be woken when checks finish or fail.
- If the monitor reports no checks yet, queued, pending, or another transient non-final state, keep waiting with the monitor/check rollup rather than polling repeatedly in chat.
- If no CI is configured for the repo, continue to merge after confirming the PR/check rollup says there are no required checks.

## 5. Handle results

**If all checks pass (or no required checks exist):**
- Merge with an allowed method that fits the project. Infer the project preference from repo settings, branch protection, and recent merged PRs when possible; do not assume a merge style without checking. If multiple allowed styles remain plausible and the repo has no obvious convention, choose the conservative project-appropriate default once (commonly squash for small feature branches) and do not enter a retry loop of merge methods.
- Add `--auto` only when GitHub says the PR is mergeable but still waiting on required checks or queueing; otherwise merge directly.
- Branch cleanup must be conditional and idempotent:
  - In a normal checkout, use GitHub's branch deletion support only when safe for the repo/worktree.
  - In a non-primary worktree (`git rev-parse --git-common-dir` is not `.git`, or `git worktree list` shows this path is not the main checkout), avoid `--delete-branch` if it would make `gh` switch the worktree and fail. Merge without local branch deletion, then delete only the remote head if it still exists.
  - Before explicit remote deletion, check that the remote branch still exists (for example, `git ls-remote --exit-code origin refs/heads/<branch>`). If GitHub already deleted it, do not retry deletion.
- Verify the final state with a PR identifier you already have (for example, `gh pr view <num> --json state,mergeCommit`). Do not switch this worktree off its branch just for cleanup; leave local worktree removal to the user.

**If any check failed:**
- Use the monitor wakeup output to identify the failing check. Then inspect only the relevant details (`gh pr checks`, `gh run view <run-id> --log-failed`, provider logs, or project-specific commands as appropriate).
- Diagnose the root cause and fix it in code. Keep the LLM responsible for project-specific strategy and failure diagnosis. Do not bypass with `--no-verify`, skip tests, or disable lints to make a check pass.
- Commit the fix with a message describing what broke and what you changed. Push. Return to step 4 and start a fresh check monitor.
- If two fix attempts in a row don't resolve it, or the failure looks unrelated to the diff (flaky infra, external outage), stop and summarize for the user.

## Continuation rule

- Creating a branch, making a commit, pushing, opening/finding a PR, or seeing checks pending is not a stopping point. Keep going until the PR is merged or a guardrail requires asking the user.
- If a command returns a transient/non-final state, inspect the PR/check rollup and continue with the appropriate wait/fix/merge path rather than stopping.

## Guardrails (repeat — do not break these)

- Never push to `main` or `master`.
- Never `--force` / `--force-with-lease` / `--no-verify` / `--amend`.
- Never `git add -A`, `git add .`, or `git add -f`.
- Never `git restore`, `git reset --hard`, or `git checkout --` to discard user changes.
- If anything unexpected appears (unfamiliar files, diverged branch, existing merge conflict), stop and ask.
