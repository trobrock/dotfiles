# Secrets

Machine-specific secrets used to live in 1Password and were pulled via the `op` CLI in `bin/ss`. That worked but required the 1Password desktop app, which is a non-starter on headless boxes.

The new flow uses [sops](https://github.com/getsops/sops) with [age](https://github.com/FiloSottile/age):

- Plaintext lives in a separate **private** repo, `trobrock/dotfiles-secrets`.
- Values are encrypted at rest with an age key; the public dotfiles repo is unchanged.
- Decryption needs only a small (~100-byte) age private key on each machine — fully headless, no GUI dependency.

## Layout

```
~/.config/sops/age/keys.txt          # age private key (per machine; can be shared)
~/.config/dotfiles-secrets/          # clone of the private secrets repo
├── .sops.yaml                       # tells sops which age recipient to encrypt to
└── secrets.yaml                     # sops-encrypted YAML; keys plaintext, values ciphertext
~/.config/dotfiles/machine_name      # which top-level section of secrets.yaml to load on this box
~/.zsh_secrets                       # generated `export KEY=value` file sourced by your shell
```

`secrets.yaml` has one top-level section per machine, plus `common:` for shared values:

```yaml
common:
  GITHUB_TOKEN: ghp_...
  OPENAI_API_KEY: sk-...
trobrock-arch:
  WORK_VPN_PASSWORD: ...
trobrock-mac:
  SOME_OTHER_THING: ...
```

## First-time setup (do this once, on a GUI-capable machine signed into 1Password)

1. **Generate an age key.**

   ```bash
   mkdir -p ~/.config/sops/age
   age-keygen -o ~/.config/sops/age/keys.txt
   chmod 600 ~/.config/sops/age/keys.txt
   age-keygen -y ~/.config/sops/age/keys.txt   # prints the public key — save it
   ```

2. **Create the private repo `trobrock/dotfiles-secrets` on GitHub** (empty is fine).

3. **Clone it locally:**

   ```bash
   git clone git@github.com:trobrock/dotfiles-secrets.git ~/.config/dotfiles-secrets
   ```

4. **Add `.sops.yaml` to the secrets repo.** Replace `age1...` with the public key from step 1:

   ```yaml
   creation_rules:
     - path_regex: secrets\.yaml$
       age: age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
   ```

5. **Migrate from 1Password:**

   ```bash
   ~/dev/personal/dotfiles/bin/migrate-from-1password
   ```

   This reads the `ZSH Secrets` 1Password item, builds `~/.config/dotfiles-secrets/secrets.yaml`, and encrypts it with sops. Inspect with `sops --decrypt ~/.config/dotfiles-secrets/secrets.yaml`, then commit and push:

   ```bash
   cd ~/.config/dotfiles-secrets
   git add .sops.yaml secrets.yaml
   git commit -m "Migrate secrets from 1Password"
   git push
   ```

6. **Test:** `bin/ss` should decrypt and write `~/.zsh_secrets`.

## Bootstrapping a new headless machine

1. SSH in. If this is a brand-new box with no GitHub access yet, either temporarily use agent forwarding for the initial private secrets clone or copy `~/.config/dotfiles-secrets` from a trusted machine; normal Git signing should not use forwarding after install.
2. Clone dotfiles: `git clone https://github.com/trobrock/dotfiles ~/dev/personal/dotfiles`
3. **Seed the age key:**

   ```bash
   mkdir -p ~/.config/sops/age
   scp known-good:~/.config/sops/age/keys.txt ~/.config/sops/age/keys.txt
   chmod 600 ~/.config/sops/age/keys.txt
   ```

4. `cd ~/dev/personal/dotfiles && bin/install --profile server`

   The install script will:
   - Install `sops` + `age` via the package manager
   - Clone `dotfiles-secrets` to `~/.config/dotfiles-secrets`
   - Prompt you to pick the machine name (the section of `secrets.yaml` to use) on first run
   - Write `~/.zsh_secrets`

If the age key is missing when `bin/install` runs, it prints the scp instructions and continues without secrets. Re-run `bin/ss` after seeding the key.

## Day-to-day operations

### Edit secrets

```bash
bin/se               # or: bin/se -m "Add FOO for arch box"
```

`bin/se` opens `$EDITOR` via sops, and on save commits + pushes the secrets repo, then regenerates `~/.zsh_secrets`. If the file is unchanged (aborted edit), it exits without touching git or `~/.zsh_secrets`.

To do it manually:

```bash
sops ~/.config/dotfiles-secrets/secrets.yaml
cd ~/.config/dotfiles-secrets && git commit -am "..." && git push
bin/ss
```

### Refresh `~/.zsh_secrets` after editing

```bash
bin/ss
```

### Add a new machine

1. Add a new top-level section to `secrets.yaml`:
   ```bash
   bin/se -m "Add new-machine-name section"
   # add `new-machine-name:` with its fields
   ```
2. On the new machine, run `bin/install` (after seeding the age key). It'll prompt for the section name.

### Add a new machine with its own age key (optional, for cleaner revocation)

If you want per-machine keys instead of a shared one:

1. Generate a key on the new machine: `age-keygen -o ~/.config/sops/age/keys.txt`
2. Get its public key: `age-keygen -y ~/.config/sops/age/keys.txt`
3. On your trusted machine, add the public key to `.sops.yaml`:
   ```yaml
   creation_rules:
     - path_regex: secrets\.yaml$
       age: >-
         age1aaa...,
         age1bbb...
   ```
4. Re-encrypt to include the new recipient: `sops updatekeys ~/.config/dotfiles-secrets/secrets.yaml`
5. Commit and push.

### Rotate a key (e.g. after losing a machine)

1. Remove the lost machine's public key from `.sops.yaml`.
2. `sops updatekeys ~/.config/dotfiles-secrets/secrets.yaml`
3. Rotate any individual secret values that may have been exposed (this is independent of the age key rotation — the old age key could still decrypt old git history of `secrets.yaml`).
4. Commit and push.
