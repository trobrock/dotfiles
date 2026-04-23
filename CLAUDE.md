# Public repo — no secrets

This repo is public. Never commit sensitive or private information: API keys, tokens, SSH/GPG private keys, credentials, internal hostnames or IPs, company-specific URLs, or anything else that shouldn't be world-readable. Secrets should be sourced from a secret manager (1Password CLI is installed), env vars, or files kept outside the repo. If you see something questionable about to be staged, stop and flag it before the commit.

# Repo layout

This is a GNU Stow-managed dotfiles repo.

- **`dot-` prefix convention** — files/dirs named `dot-foo` get symlinked to `~/.foo` when stowed (e.g., `dot-zshrc` → `~/.zshrc`, `dot-claude/settings.json` → `~/.claude/settings.json`). Use this prefix when adding new config that should land in `$HOME`.
- **Repo-local vs. stowed** — `dot-claude/` is **global** (stows to `~/.claude/`). Anything repo-scoped (like this file) must live at the repo root AND be listed in `.stow-local-ignore` so stow won't symlink it.
- **Package manifests** — `Archfile` (Linux) and `Brewfile` (macOS) are the source of truth for installed packages. Add new entries alphabetically within the matching comment-delimited section. `Archfile.lock` and `Brewfile.lock.json` are generated — do not hand-edit.
- **Platform split** — `linux/` and `darwin/` hold OS-specific setup scripts. Cross-platform config lives in `dot-*` at the root.
- **Primary platform** — Arch + Hyprland. `linux/` and `Archfile` are the actively-used paths; macOS/Brewfile exist but aren't daily-driven.

# Linux package management

Prefer `yay` over `pacman` for installs/removes/queries. `yay` handles both official repos and the AUR, and is already installed.

- Install: `yay -S <pkg>`
- Remove: `yay -Rns <pkg>`
- Search: `yay -Ss <query>`

Use `pacman` only when `yay` cannot (e.g., inside scripts where AUR is irrelevant, or when the user explicitly asks).

# Working in this repo

- **"Hooks" is ambiguous** — could mean Claude Code hooks (`dot-claude/settings.json`), pacman hooks, systemd units, tmux hooks, or shell hooks. Ask which before acting.
- **Regressions → check git log first** — when the user says "this used to work", run `git log -- <file>` on the relevant config and bisect recent commits before theorizing.
- **Don't preserve adjacent legacy defensively** — when modifying a keybind/hook/script, ask whether the surrounding old behavior should be removed too, rather than leaving it untouched "to be safe".

# Config changes

- **Verify config keys against upstream docs** — for tools like VoxType, hypridle, waybar, hyprland, etc., fetch the actual docs or source before proposing a key/value. First-pass guesses have been wrong enough times to be worth the verification step.
- **Broad-first for user-visible config** — for vocab lists, widget styling, status bars, and similar user-visible surfaces, propose the broader version and let the user narrow. Narrowing up from a minimal fix is tedious.
