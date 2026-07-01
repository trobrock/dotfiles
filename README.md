# Dotfiles

You probably shouldn't use this if you aren't me. But go for it if you want...

## Initial Setup

```bash
git clone https://github.com/trobrock/dotfiles.git ~/dev/personal/dotfiles
cd ~/dev/personal/dotfiles
bin/install
```

For a headless Arch server, use the server profile:

```bash
bin/install --profile server
```

The selected profile is saved to `~/.config/dotfiles/profile` so shell startup can avoid desktop-only behavior on headless boxes. The default profile is `desktop`, which preserves the current Arch + Hyprland/macOS workstation behavior.

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

Profiles:

- `bin/install` or `bin/install --profile desktop` installs the full workstation setup.
- `bin/install --profile server` installs shared non-GUI Arch packages and skips desktop setup such as Hyprland, fingerprint auth, TTY auto-login, VoxType/Walker/Elephant hooks, 1Password GUI config, and Hyprshot cleanup.
- Desktop/macOS profiles use a local fixed-socket `ssh-agent`; the server profile signs with a server-local private key file. Git signing should not rely on SSH agent forwarding.
- `bin/diff --profile server` dry-runs the server stow overlay.

`Archfile` sections tagged `[desktop]` are skipped by the server profile. Untagged and `[shared]` sections install everywhere. Generated package locks are `Archfile.lock` for desktop and `Archfile.server.lock` for server.

bin/diff: This shows what symlinks are missing.

bin/ss: Decrypts machine secrets from `~/.config/dotfiles-secrets/secrets.yaml` via `sops` and writes them to `~/.zsh_secrets`. Run on its own to refresh secrets without doing a full install. Shell startup tolerates this file being absent, which is useful before the age key has been seeded on a new server.

bin/migrate-from-1password: One-shot migration that pulls the legacy "ZSH Secrets" 1Password item into the sops-encrypted file. Run once on a GUI-capable machine that's signed into 1Password.

## tmux Developerly widgets

The tmux status bar delegates task labels, agent activity, and local LLM usage to
Developerly:

- `@developerly_status_task` — per-session tmux option populated by the Developerly TUI for `status-left`.
- `developerly usage show-compact` — compact token usage widget for `status-right`.
- `developerly status` — agent activity summary for `status-right`.
