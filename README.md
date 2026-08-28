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
- `bin/install --profile server` installs shared non-GUI Arch packages and skips desktop setup such as Hyprland, fingerprint auth, TTY auto-login, VoxType/Elephant hooks, 1Password GUI config, and Hyprshot cleanup.
- Desktop/macOS profiles use a local fixed-socket `ssh-agent`; the server profile signs with a server-local private key file. Git signing should not rely on SSH agent forwarding.
- `bin/diff --profile server` dry-runs the server stow overlay.

`Archfile` sections tagged `[desktop]` are skipped by the server profile. Untagged and `[shared]` sections install everywhere. Generated package locks are `Archfile.lock` for desktop and `Archfile.server.lock` for server.

bin/diff: This shows what symlinks are missing.

bin/ss: Decrypts machine secrets from `~/.config/dotfiles-secrets/secrets.yaml` via `sops` and writes them to `~/.zsh_secrets`. Run on its own to refresh secrets without doing a full install. Shell startup tolerates this file being absent, which is useful before the age key has been seeded on a new server.

## Notch

`bin/install` installs the latest stable [Notch](https://github.com/trobrock/notch) release to `~/.local/bin/notch`. Its global defaults are stowed from `dot-config/notch` to `~/.config/notch` on every machine.

MCP servers are **per-platform**, because Notch has no way to merge multiple MCP files — it reads a single `mcp.json` (overridable via the `mcp_config` key or `--mcp-config`). The file is stowed from the platform overlay instead of the shared root:

| Overlay | `mcp.json` | Servers |
| --- | --- | --- |
| `linux/dot-config/notch/` | yes | `grafana`, `sentry`, `cloudflare-api` |
| `darwin/dot-config/notch/` | yes, empty | none — no Comfortly servers on the work Mac |
| `server/` | absent | none |

The empty file on macOS is deliberate. Notch treats an unresolved `${NAME}` reference in an MCP `env` block as a hard parse error, and `GRAFANA_SERVICE_ACCOUNT_TOKEN` only exists in the `personal_arch` section of `dotfiles-secrets` — sharing the Linux file would make every `notch` invocation on the Mac print a `parse MCP config` warning.

On the Linux desktop, the Grafana server resolves `GRAFANA_SERVICE_ACCOUNT_TOKEN` from the environment when Notch loads the config. Keep that value in the encrypted `dotfiles-secrets` workflow rather than in this repository. Sentry and Cloudflare use OAuth; authenticate them once per machine with:

```bash
notch login openai-codex
notch mcp login sentry          # linux desktop only
notch mcp login cloudflare-api  # linux desktop only
```

Notch stores OAuth credentials and sessions under `~/.local/share/notch`; those private runtime files are not managed by these dotfiles.

bin/migrate-from-1password: One-shot migration that pulls the legacy "ZSH Secrets" 1Password item into the sops-encrypted file. Run once on a GUI-capable machine that's signed into 1Password.

## tmux Developerly widgets

The tmux status bar delegates task labels, agent activity, and local LLM usage to
Developerly:

- `@developerly_status_task` — per-session tmux option populated by the Developerly TUI for `status-left`.
- `developerly usage show-compact` — compact token usage widget for `status-right`.
- `developerly status` — agent activity summary for `status-right`.

## tmux API spend pill

`dot-local/bin/codex-usage-bars` renders the `api $N 7d` pill from two sources,
because no single tool sees everything:

- **ccusage** (`npm:ccusage`, pinned in `dot-config/mise/config.toml`) covers Pi.
  It auto-detects agent CLIs by their log formats.
- **Notch sessions** are read directly from `~/.local/share/notch/sessions`.
  ccusage cannot see Notch, which writes an unrelated schema. Notch >= 0.4.14
  reports `cost_usd` per turn, so the widget sums that rather than pricing
  tokens itself. Only key-billed providers (`anthropic`, `openai`) count;
  subscription providers are already covered by the codex/claude pills.

The pill degrades honestly: a total prefixed `~` means one source failed and the
figure is a floor, and a cached total older than
`CODEX_USAGE_BARS_API_SPEND_MAX_AGE` (default 6h) renders `—` instead of a stale
number.

Useful env vars:

| Variable | Effect |
| --- | --- |
| `CODEX_USAGE_BARS_API_SPEND` | `on` / `off` / `auto` (default) |
| `CODEX_USAGE_BARS_API_SPEND_SPLIT` | `1` renders separate `ccusage` and `notch` pills |
| `CODEX_USAGE_BARS_NOTCH_SPEND` | `off` drops the Notch source |
| `CODEX_USAGE_BARS_NOTCH_SESSIONS` | Override the Notch session directory |
| `CODEX_USAGE_BARS_API_SPEND_MAX_AGE` | Seconds a failed refresh may keep serving the last total |

Note that tmux runs `status-right` through `/bin/sh`, which never sources the
zsh config that puts mise shims on `PATH`. The widget therefore probes
`$MISE_DATA_DIR/shims` (or `~/.local/share/mise/shims`) directly when `ccusage`
is not on `PATH`. It never falls back to `npx`, which would fetch and execute a
package on a status-bar refresh.
