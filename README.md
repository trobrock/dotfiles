# Dotfiles

You probably shouldn't use this if you aren't me. But go for it if you want...

## Initial Setup

```bash
git clone https://github.com/trobrock/dotfiles.git ~/dev/personal/dotfiles
cd ~/dev/personal/dotfiles
bin/install
```

On a fresh machine, `bin/install` needs an [age](https://github.com/FiloSottile/age) private key in place before it can decrypt machine secrets:

```bash
mkdir -p ~/.config/sops/age
scp known-good:~/.config/sops/age/keys.txt ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
```

The key lets `sops` decrypt `secrets.yaml` from the private `dotfiles-secrets` repo, which is cloned automatically. If the key isn't present when `bin/install` runs, it prints the scp instructions and skips the secrets step; re-run `bin/ss` (or `bin/install`) after seeding the key.

## Commands

bin/install: This will install all the dotfiles with stow.
**Note: this will overwrite anything that already exists, so you better have everything backed up!**

bin/diff: This shows what symlinks are missing.

bin/ss: Decrypts machine secrets from `~/.config/dotfiles-secrets/secrets.yaml` via `sops` and writes them to `~/.zsh_secrets`. Run on its own to refresh secrets without doing a full install.

bin/migrate-from-1password: One-shot migration that pulls the legacy "ZSH Secrets" 1Password item into the sops-encrypted file. Run once on a GUI-capable machine that's signed into 1Password.

## llm-usage (tmux widget)

`dot-local/bin/llm-usage` aggregates token usage from local Claude Code
(`~/.claude/projects/*/*.jsonl`) and Pi (`~/.local/state/pi/agent/sessions/**/*.jsonl`)
session logs and renders a tmux status string showing today's tokens, a trend
arrow vs. the prior-7-day daily average, and the trailing 7-day total:

    󱙺 8.2M ▲ 446% · 18M/7d

Useful subcommands:

- `llm-usage show` — fast cached render (used by tmux `status-right`).
- `llm-usage refresh` — synchronous rescan; use on first install.
- `llm-usage stats` — human-readable breakdown for the last 14 days.
- `llm-usage reset` — wipe the `~/.cache/llm-usage/` cache.

The collector is incremental (per-file byte offsets in `state.json`), so steady-state
runs are sub-second.
