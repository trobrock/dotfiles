# Disk space across the two Linux machines

The two Linux boxes share one `Archfile` and one set of dotfiles but have very
different storage:

| | Root filesystem | Extra disk | GPU |
|---|---|---|---|
| Intel mini-PC | 58G btrfs eMMC (`/dev/mmcblk0p2`, `@` + `@home`) | 1.9T NVMe at `/srv/storage` | Intel Alder Lake-N (iGPU) |
| AMD desktop | large enough | — | AMD Radeon |

Everything here exists because a change that is correct on one of them can be
wrong on the other. The rule: **a shared change must make sense on both, or be
opted into per machine** rather than hardcoded.

## What went wrong once

The Intel box hit **84K free on a 58G root** — btrfs fully allocated
(`Device unallocated: 1.00MiB`), which is the point where the filesystem can go
read-only. Two causes:

1. **`ollama-rocm` in the shared `Archfile`.** It pulled a 9.2G AMD ROCm stack
   into `/opt/rocm` plus 3.1G of `/usr/lib/ollama` onto a machine with an Intel
   iGPU, where ROCm can never run. `vulkan-radeon` was in the shared desktop
   section for the same reason. The AMD desktop genuinely wants both.
2. **Every tool cache on a 58G root.** 16G of pacman packages (2947 of them),
   4.5G of yay builds, 3.4G of Chrome builds, 3.8G of journal, plus go, cargo,
   npm, uv, puppeteer and playwright caches — while the 1.9T NVMe sat at 12%.

## GPU-conditional packages: the `[amd]` tag

`Archfile` sections tagged `[amd]` install only where an AMD GPU is present.
`bin/install`'s `has_amd_gpu()` reads the PCI vendor id from
`/sys/class/drm/card*/device/vendor` (`0x1002` = AMD/ATI) — sysfs rather than
`lspci`, so it works before `pciutils` exists. Override with
`DOTFILES_AMD_GPU=1` or `=0`.

Tags combine with the existing `[desktop]` tag:

```
# [desktop][amd] GPU      → AMD desktops only (skipped by the server profile)
vulkan-radeon

# [amd] Local inference   → any AMD machine, desktop or server
ollama-rocm
```

Selection matrix, verified against the real `Archfile`:

| profile | AMD? | packages | `vulkan-radeon` | `ollama-rocm` |
|---|---|---|---|---|
| desktop | no | 137 | no | no |
| desktop | yes | 139 | yes | yes |
| server | no | 82 | no | no |
| server | yes | 83 | no | yes |

Because `archfile_remove_missing()` uninstalls anything in the lock file that is
no longer selected, running `bin/install` on the Intel box *removes* the ROCm
stack on its own and keeps it off. No manual pruning needed after the first run.

## Cache relocation: the `cache_root` opt-in

A machine moves its heavy tool caches off root by writing a simple absolute path
(letters, numbers, `/`, `.`, `_`, and `-`) to
`~/.config/dotfiles/cache_root` — the same per-machine opt-in pattern as
`profile` and `machine_name`. **With no such file, every tool keeps its default
under `$HOME`,** so the AMD desktop is unaffected.

On the Intel box:

```
$ cat ~/.config/dotfiles/cache_root
/srv/storage/cache
```

Two persistent places consume it, because one is not enough:

- **`dot-zshenv`** — plain TTY/SSH shells. Guarded on the file being readable
  *and* the path being an existing directory, so an unmounted disk leaves the
  variables unset rather than pointing tools at a missing path.
- **`~/.config/environment.d/10-cache-dirs.conf`** — the systemd user session
  and anything it launches, including graphical apps. `environment.d` has no
  conditionals, so `bin/install` **generates** this file from `cache_root`
  instead of stowing one with a hardcoded path, and deletes it when the machine
  has no `cache_root`. Do not hand-edit it.

The installer exports the same variables before installing packages or browser
tools. If a configured cache directory is missing, it stops rather than filling
the root disk by accident.

Variables set (all verified against upstream docs or live output):

| Variable | Cache |
|---|---|
| `GOMODCACHE`, `GOCACHE` | go modules, go build |
| `UV_CACHE_DIR` | uv |
| `PUPPETEER_CACHE_DIR` | puppeteer's Chrome downloads |
| `PLAYWRIGHT_BROWSERS_PATH` | playwright browsers |
| `npm_config_cache` | npm (`npm config get cache` confirms it) |
| `AURDEST` | yay build dir (documented in `man yay`) |

`XDG_CACHE_HOME` is deliberately **not** redirected: the `ai-usage` /
`codex-usage-bars` helpers key their small caches off it, and moving all of
`~/.cache` to another disk is a bigger blast radius than the problem needs.

`~/.agent-browser` has no relocation env var, so its Chrome builds stay on root.
It accumulates one full ~385M build per Chrome release and had reached 9 of them;
prune it if it grows again.

### pacman's cache

`setup_pacman_cache_dir()` rewrites `CacheDir` in `/etc/pacman.conf`, records the
managed value in `/etc/pacman.d/dotfiles-cache-root`, and only runs on a machine
with a `cache_root`. Removing `cache_root` restores pacman's default only when
that managed value is still active, so a later manual change is preserved.
**Relocating it does not move the old contents** — clear
`/var/cache/pacman/pkg` by hand after the switch, or the 16G stays where it was.

## Journal cap

`system/etc/systemd/journald.conf.d/70-size-limits.conf` sets
`SystemMaxUse=2%`. Arch ships `journald.conf` fully commented out, so the
systemd default allows up to 10% of the filesystem, capped at 4G by default.
The journal had reached 3.8G on the 58G root. A smaller percentage rather than
a fixed size lets one shared value scale to each machine's disk.

`paccache.timer` (from `pacman-contrib`, now in `Archfile`) trims the package
cache to the last 3 versions weekly. It is enabled on both machines — it has
nothing to do with `cache_root` and is useful anywhere.

## `/srv/storage` and boot

`/etc/fstab` mounts `LABEL=storage` at `/srv/storage` at pass 1 **without
`nofail`**, so a failed mount halts boot instead of letting the generated
`environment.d` paths silently land back on root. That is intentional — don't
"fix" it by adding `nofail` without also making the generated file conditional.

## Recovery runbook

If root fills again, in this order — deletions first, since the disk may be too
full to write anything:

```sh
# 0. btrfs snapshots hold space even after deletion. timeshift is installed.
sudo btrfs subvolume list /
sudo timeshift --list          # delete old snapshots before measuring anything

# 1. Pure deletions
sudo journalctl --vacuum-size=200M
sudo pacman -Sc                      # cached versions of uninstalled packages
rm -rf "${AURDEST:-$HOME/.cache/yay}"
sudo paccache -rk1                   # trim to 1 version per package

# 2. Regenerable caches
go clean -modcache
npm cache clean --force
rm -rf "${GOCACHE:-$HOME/.cache/go-build}" "${UV_CACHE_DIR:-$HOME/.cache/uv}"
rm -rf "$HOME/.cargo/registry" "$HOME/.cargo/git"

# 3. Old Chrome builds, keeping only the newest
ls -1 "$HOME/.agent-browser/browsers"

# 4. Only once there is free space — btrfs needs room to work
sudo btrfs balance start -dusage=50 -musage=50 /
btrfs filesystem usage -T /
```

Find the real consumers with `du -xh --max-depth=1 <dir> | sort -rh | head`.
Note `du` reports *apparent* size while `df` reports compressed on-disk size —
root is `compress=zstd:3`, so recovery is smaller than the raw `du` sum, except
for already-compressed `.zst` package caches which recover about 1:1.
