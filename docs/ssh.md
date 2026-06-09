# SSH and Git signing

SSH keys and git commit signing used to live in the 1Password SSH agent + `op-ssh-sign`. That worked but biometric prompted on every operation, didn't work headless, and tied auth + signing to a GUI app.

The current flow uses a single Ed25519 key, stored sops-encrypted in the private secrets repo, loaded into a plain `ssh-agent` on login. Same key everywhere. Zero prompts after login.

## How it works

- The private key lives sops-encrypted at `~/.config/dotfiles-secrets/ssh/id_ed25519`.
- On login, a small script (`~/.config/scripts/ssh-agent-unlock`) decrypts it with sops/age and pipes it straight into `ssh-add -`. The decrypted key never touches disk.
- Linux: a user systemd unit (`ssh-agent.service`) runs `ssh-agent` on a known socket; a oneshot `ssh-agent-unlock.service` loads the key after it.
- macOS: a LaunchAgent (`com.trobrock.ssh-agent`) runs `ssh-agent` on a known socket; `com.trobrock.ssh-agent-unlock` loads the key after it.
- Git signing uses native `gpg.format = ssh` — no external signer program. The agent serves the key to `ssh-keygen -Y sign` (which is what git invokes internally for SSH-format signatures).
- Non-server profiles stow a platform-specific `IdentityAgent` config so `ssh` can find the fixed local agent even if a shell/tool didn't inherit `$SSH_AUTH_SOCK`.
- Headless servers have no key on the box. `ForwardAgent yes` in a trusted host block forwards the workstation agent over the SSH connection; both auth and signing then use your local agent transparently.

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

## Per-host setup for headless servers

On any server you commit from, no key install is needed — just enable agent forwarding from your workstation. The only repo-managed forwarding target today is `trobrock-home`:

```
Host trobrock-home
  ForwardAgent yes
```

Non-server profiles stow this from `linux/dot-ssh/config.d/10-agent-forwarding.conf` or `darwin/dot-ssh/config.d/10-agent-forwarding.conf`. They also stow `00-agent.conf`, which sets `IdentityAgent` to the fixed local socket. Together, that means `ssh trobrock-home` forwards the workstation agent even from tools or shells that did not inherit `$SSH_AUTH_SOCK`.

If a workstation needs private connection details for that alias, add only those details to `~/.ssh/config.local`:

```
Host trobrock-home
  HostName <private hostname or IP>
```

Then `ssh trobrock-home`, and inside that session:

```sh
ssh-add -l    # should show the forwarded key
git commit -S -m "test"   # signing works against your forwarded agent
```

Only enable `ForwardAgent` for hosts you trust. Root on the remote box can use your forwarded agent for the duration of the session.

## Rotating the key

1. Generate fresh: `ssh-keygen -t ed25519 -N '' -f /tmp/id_ed25519 -C trobrock@gmail.com`
2. Update GitHub (Settings → SSH and GPG keys, replace both Authentication and Signing entries).
3. Update `signingkey` in `dot-gitconfig` and the line in `dot-config/git/allowed_signers`.
4. Re-encrypt into the secrets repo (step 3 above) and push.
5. On each machine: pull the secrets repo, `systemctl --user restart ssh-agent-unlock.service` (Linux) or `launchctl kickstart -k "gui/$(id -u)/com.trobrock.ssh-agent-unlock"` (macOS).
