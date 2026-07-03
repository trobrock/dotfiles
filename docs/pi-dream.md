# Pi Dream

Pi Dream is an unattended, read-only scout for useful codebase maintenance work. It uses Pi overnight or on demand to identify candidate tasks with evidence, validation steps, and risk scoring. It does **not** edit files.

## Commands

```bash
pi-dream doctor
pi-dream scout --repo ~/dotfiles
pi-dream scout --repo ~/dotfiles --recipe tests
pi-dream scout --repo ~/dotfiles --mock
pi-dream inbox
pi-dream show <id>
pi-dream accept <id>
pi-dream ticket <id> <candidate-id> --dry-run
pi-dream ticket <id> <candidate-id>
pi-dream implement <id> <candidate-id> --dry-run
pi-dream implement <id> <candidate-id>
pi-dream reject <id> --reason "not useful"
pi-dream archive <id>
```

Reports are written outside this repo by default:

```text
${XDG_STATE_HOME:-~/.local/state}/pi-dream/inbox/
```

Override with `PI_DREAM_HOME=/path/to/state` or `--state-dir`.

## Pi integration

The Pi extension in `dot-pi/agent/extensions/dream.ts` adds:

```text
/dream inbox
/dream review
/dream show <id>
/dream accept <id>
/dream ticket <id> <candidate-id> [--dry-run]
/dream implement <id> <candidate-id> [--dry-run]
/dream reject <id> <reason>
/dream archive <id>
/dream run [repo] [recipe]
```

It also registers the `dream_inbox` tool so Pi can list/show/update existing dream reports during a normal session. Ticket/implementation actions are available from slash commands and require an explicit command because they call Developerly.

The prompt template `dot-pi/agent/prompts/dream-scout.md` adds `/dream-scout` for manual read-only scouting inside Pi.

## Recipes

Current recipes:

- `general` — broad high-confidence maintenance candidates
- `tests` — skipped/focused/flaky/failing-test opportunities
- `docs` — README/examples/setup drift
- `todos` — TODO/FIXME/HACK triage
- `config` — config/script/automation drift

## Safety model

The unattended runner invokes Pi with:

- `--tools read,grep,find,ls`
- no edit/write/bash tools
- no skills or prompt templates
- context files disabled by default
- a temporary safety extension that blocks secret-looking paths and absolute paths outside the repo

Scout mode writes reports only. Generated reports should stay under `~/.local/state/pi-dream`, not in this public dotfiles repo.

## Developerly handoff

After reviewing a candidate, create a Developerly ticket without starting work:

```bash
pi-dream ticket <report-id> C1
```

This runs:

```bash
developerly work-items create --project <matched-project> --kind <kind> --title <candidate-title> --description <dream-context> --sync --json
```

To start implementation through the Developerly quick-start workflow:

```bash
pi-dream implement <report-id> C1
```

This runs `developerly quickstart` from the target repo, creates/syncs the work item, and launches the configured worktree/tmux/agent flow. By default it uses `--agent pi`, `--plan`, and the report branch as the base branch.

Useful options:

```bash
pi-dream ticket <id> C1 --no-sync              # local-only work item
pi-dream implement <id> C1 --agent claude      # launch Claude instead of Pi
pi-dream implement <id> C1 --base main         # choose base branch
pi-dream implement <id> C1 --no-plan           # skip planning mode
pi-dream implement <id> C1 --dry-run           # show command, no side effects
```

Pi Dream resolves the Developerly project by matching the report repo path against `developerly projects list --json`. Override with `--project <id-or-name>` or `PI_DREAM_DEVELOPERLY_PROJECT`.

## Optional systemd timer

This repo includes opt-in user units:

```bash
systemctl --user daemon-reload
systemctl --user enable --now pi-dream.timer
```

The default service scouts `%h/dotfiles`. Override it with a drop-in if needed:

```bash
systemctl --user edit pi-dream.service
```

Example override:

```ini
[Service]
Environment=PI_DREAM_REPO=%h/dev/project
Environment=PI_DREAM_RECIPE=general
Environment=PI_DREAM_MAX_CANDIDATES=5
```

## Testing without model/API usage

```bash
PI_DREAM_HOME=$(mktemp -d) pi-dream scout --repo ~/dotfiles --mock
PI_DREAM_HOME=/tmp/pi-dream-test pi-dream inbox
```
