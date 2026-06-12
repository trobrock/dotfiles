# SSH and Git signing

SSH keys and git commit signing used to live in the 1Password SSH agent + `op-ssh-sign`. That worked but biometric prompted on every operation, didn't work headless, and tied auth + signing to a GUI app.

The current flow uses a single Ed25519 key, stored sops-encrypted in the private secrets repo, loaded into a plain `ssh-agent` on login. Same key everywhere. Zero prompts after login.

## How it works

- The private key lives sops-encrypted at `~/.config/dotfiles-secrets/ssh/id_ed25519`.
- On login, a small script (`~/.config/scripts/ssh-agent-unlock`) decrypts it with sops/age and pipes it straight into `ssh-add -`. The decrypted key never touches disk.
- Linux desktop and server profiles: a user systemd unit (`ssh-agent.service`) runs `ssh-agent` on the fixed socket `~/.ssh/agent.sock`; a oneshot `ssh-agent-unlock.service` loads the key after it.
- macOS: a LaunchAgent (`com.trobrock.ssh-agent`) runs `ssh-agent` on the same fixed socket; `com.trobrock.ssh-agent-unlock` loads the key after it.
- Git signing uses native `gpg.format = ssh` — no external signer program. The local agent serves the key to `ssh-keygen -Y sign` (which is what git invokes internally for SSH-format signatures).
- Platform/profile overlays stow an `IdentityAgent ~/.ssh/agent.sock` config so `ssh` can find the fixed local agent even if a shell/tool didn't inherit `$SSH_AUTH_SOCK`. Avoid OpenSSH-only tokens such as `%i` here; Ruby Net::SSH/Kamal reads this config but does not expand those tokens.
- Headless servers load their own local agent from the same sops-encrypted key. Repo-managed SSH config does not enable `ForwardAgent`; forwarding is opt-in only from `~/.ssh/config.local` for exceptional cases.

Security boundary: the per-machine age private key at `~/.config/sops/age/keys.txt`. Anyone who can read that file can decrypt the SSH key. Same trust model the rest of the secrets workflow already relies on.

## One-time migration (per identity, not per machine)

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
   - Also remove any `~/.config/1Password/ssh/agent.toml` if you set one up.
   - If 1Password (or any prior setup) wrote `~/.ssh/config`, move it aside before re-running stow so `dot-ssh/config` can land cleanly:
     ```sh
     [ -f ~/.ssh/config ] && [ ! -L ~/.ssh/config ] && mv ~/.ssh/config ~/.ssh/config.pre-dotfiles
     ```

6. Re-run `bin/install` (or just enable the services by hand):
   ```sh
   # Linux:
   systemctl --user daemon-reload
   systemctl --user enable --now ssh-agent.service ssh-agent-unlock.service

   # macOS:
   launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.trobrock.ssh-agent.plist
   launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.trobrock.ssh-agent-unlock.plist
   ```

7. Verify:
   ```sh
   ssh-add -l                # should list the key
   ssh -T git@github.com     # should auth as you, no prompt
   git commit --allow-empty -m "test sign"
   git log --show-signature -1   # "Good signature" via allowed_signers
   ```

## Headless server setup

Servers sign locally. The server profile stows the same fixed-socket systemd user units as Linux desktops plus `~/.ssh/config.d/00-agent.conf`, so git signing does not depend on a workstation SSH session or a forwarded agent socket.

On a server:

```sh
# Seed the age key first if this is a fresh host, then:
bin/install --profile server
systemctl --user daemon-reload
systemctl --user enable --now ssh-agent.service ssh-agent-unlock.service
ssh-add -l
```

`ssh-add -l` should list the signing key from `~/.config/dotfiles-secrets/ssh/id_ed25519`. If it does not, check that the private secrets repo exists and the server's age key can decrypt it. `~/.ssh/id_ed25519.pub` is optional, but lets the unlock script skip re-adding an already-loaded key.

If a workstation needs private connection details for a server alias, keep only those details in `~/.ssh/config.local`:

```
Host trobrock-home
  HostName <private hostname or IP>
```

Do not add `ForwardAgent yes` for normal git signing. If an exceptional workflow still needs forwarding, opt in per-host from `~/.ssh/config.local` and remember that root on the remote box can talk to your forwarded agent for the duration of the session.

## Rotating the key

1. Generate fresh: `ssh-keygen -t ed25519 -N '' -f /tmp/id_ed25519 -C trobrock@gmail.com`
2. Update GitHub (Settings → SSH and GPG keys, replace both Authentication and Signing entries).
3. Update `signingkey` in `dot-gitconfig` and the line in `dot-config/git/allowed_signers`.
4. Re-encrypt into the secrets repo (step 3 above) and push.
5. On each machine: pull the secrets repo, `systemctl --user restart ssh-agent-unlock.service` (Linux) or `launchctl kickstart -k "gui/$(id -u)/com.trobrock.ssh-agent-unlock"` (macOS).
