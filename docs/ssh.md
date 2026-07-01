# SSH and Git signing

SSH keys and git commit signing used to live in the 1Password SSH agent + `op-ssh-sign`. That worked but biometric prompted on every operation, didn't work headless, and tied auth + signing to a GUI app.

Current split:

- Desktop Linux/macOS use a dotfiles-managed local `ssh-agent` at `~/.ssh/agent.sock`.
- Headless servers sign with a private key file that lives on that server, currently `~/.ssh/id_ed25519`.
- Repo-managed SSH config does not enable `ForwardAgent`; forwarding is opt-in only from `~/.ssh/config.local` for exceptional cases.

## Desktop/macOS flow

- The private key lives sops-encrypted at `~/.config/dotfiles-secrets/ssh/id_ed25519`.
- On login, `~/.config/scripts/ssh-agent-unlock` decrypts it with sops/age and pipes it into `ssh-add -`. The decrypted key never touches disk.
- Linux desktop: user systemd units run `ssh-agent.service` on `~/.ssh/agent.sock` and `ssh-agent-unlock.service` loads the key.
- macOS: LaunchAgents `com.trobrock.ssh-agent` and `com.trobrock.ssh-agent-unlock` do the same.
- Git signing uses native `gpg.format = ssh` with `~/.config/scripts/git-ssh-sign`, which forces signing through `~/.ssh/agent.sock` when that socket exists.

Security boundary: the per-machine age private key at `~/.config/sops/age/keys.txt`. Anyone who can read that file can decrypt the SSH key. Same trust model the rest of the secrets workflow already relies on.

## Desktop/macOS one-time migration

1. Export the private key from 1Password. Either via the GUI (Edit item → reveal private key → copy) or, if the item has a private-key field exposed:
   ```sh
   op read "op://Private/GitHub SSH/private key?ssh-format=openssh" > /tmp/id_ed25519
   ```
   The key inside the sops envelope must be passphrase-less — sops is the encryption layer. If 1Password exported a passphrased key, strip the passphrase with `ssh-keygen -p -f /tmp/id_ed25519 -P 'oldpass' -N ''`.

2. Confirm it parses:
   ```sh
   ssh-keygen -y -f /tmp/id_ed25519
   ```
   The output should match the `signingkey` line in `~/.gitconfig`.

3. Encrypt into the secrets repo:
   ```sh
   cd ~/.config/dotfiles-secrets
   mkdir -p ssh
   sops --encrypt --input-type binary --output-type binary /tmp/id_ed25519 > ssh/id_ed25519
   shred -u /tmp/id_ed25519
   git add ssh/id_ed25519 && git commit -m "Add SSH key"
   git push
   ```
   `.sops.yaml` already matches `ssh/.+` via the `path_regex` rule — no edits needed there.

4. Drop the public key alongside so the agent unlock script can fingerprint-check it for idempotency:
   ```sh
   mkdir -p ~/.ssh
   cat > ~/.ssh/id_ed25519.pub <<'EOF'
   ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE0dw+dqQQl/uuMeKaslGGjbVUTVXXV2MNM8DIBLP2bY trobrock@gmail.com
   EOF
   chmod 644 ~/.ssh/id_ed25519.pub
   ```

5. Disable the 1Password SSH agent so it stops fighting for `$SSH_AUTH_SOCK`:
   - 1Password → Settings → Developer → uncheck **Use the SSH agent**.
   - Remove any `~/.config/1Password/ssh/agent.toml` if you set one up.
   - If 1Password wrote `~/.ssh/config`, move it aside before re-running stow:
     ```sh
     [ -f ~/.ssh/config ] && [ ! -L ~/.ssh/config ] && mv ~/.ssh/config ~/.ssh/config.pre-dotfiles
     ```

6. Re-run `bin/install` or enable the services by hand:
   ```sh
   # Linux desktop:
   systemctl --user daemon-reload
   systemctl --user enable --now ssh-agent.service ssh-agent-unlock.service

   # macOS:
   launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.trobrock.ssh-agent.plist
   launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.trobrock.ssh-agent-unlock.plist
   ```

7. Verify:
   ```sh
   ssh-add -l
   ssh -T git@github.com
   git commit --allow-empty -m "test sign"
   git log --show-signature -1
   ```

## Headless server setup

Servers do not use the dotfiles-managed ssh-agent. The server profile overrides Git to sign directly with a private key file:

```ini
[user]
  signingkey = ~/.ssh/id_ed25519

[gpg "ssh"]
  program = /usr/bin/ssh-keygen
```

On a server:

```sh
bin/install --profile server
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519 -C trobrock@gmail.com
ssh-keygen -y -f ~/.ssh/id_ed25519 > ~/.ssh/id_ed25519.pub
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub
```

Register `~/.ssh/id_ed25519.pub` with GitHub as an SSH signing key, and as an authentication key if this server also needs to push/pull over SSH.

Verify:

```sh
git config --get user.signingkey       # ~/.ssh/id_ed25519
git config --get gpg.ssh.program       # /usr/bin/ssh-keygen
git commit --allow-empty -m "test sign"
```

For local `git log --show-signature` verification, add the server public key to `~/.config/git/allowed_signers` or use a private `~/.config/local/gitconfig` override for `gpg.ssh.allowedSignersFile`.

If a workstation needs private connection details for a server alias, keep only those details in `~/.ssh/config.local`:

```sshconfig
Host trobrock-home
  HostName <private hostname or IP>
```

Do not add `ForwardAgent yes` for normal git signing. If an exceptional workflow still needs forwarding, opt in per-host from `~/.ssh/config.local` and remember that root on the remote box can talk to your forwarded agent for the duration of the session.

## Troubleshooting desktop/macOS agent signing

If `git commit` fails with `Couldn't get agent socket?`, check:

```sh
printf '%s\n' "$SSH_AUTH_SOCK"
ls -l ~/.ssh/agent.sock
SSH_AUTH_SOCK=~/.ssh/agent.sock ssh-add -l
```

Long-lived tmux panes may have inherited an old `/run/user/.../ssh-agent.socket`. New shells should point at `~/.ssh/agent.sock`; for an existing shell, run:

```sh
export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"
```

If tmux itself has a stale value from before this setup, clear or replace it once:

```sh
tmux set-environment -gu SSH_AUTH_SOCK
tmux set-environment -gu SSH_AGENT_PID
```

## Rotating keys

- Desktop/macOS shared key: generate a fresh key, update GitHub, update `dot-gitconfig` and `dot-config/git/allowed_signers`, re-encrypt into the secrets repo, then restart the unlock service/LaunchAgent.
- Server local key: generate/replace `~/.ssh/id_ed25519` on that server and update GitHub with the new public key. Do not commit the private key.
