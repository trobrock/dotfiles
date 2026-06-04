# Laptop sleep / hibernate

Goal: closing the lid should resume quickly for short moves, but a closed laptop off power should eventually hibernate so it does not drain in a backpack.

## Policy

- Lid close: `suspend-then-hibernate`
- Hypridle open-session battery idle: `suspend-then-hibernate`
- Hibernate delay: `45min`
- On AC: stay suspended; the hibernate countdown starts after AC is disconnected
- No clamshell mode: docked/external-monitor lid close still suspends

Tracked templates:

- `system/etc/systemd/logind.conf.d/70-lid-suspend-then-hibernate.conf`
- `system/etc/systemd/sleep.conf.d/70-suspend-then-hibernate.conf`

## Repeatable system setup

`bin/install --profile desktop` runs this automatically on Linux machines with a battery.

You can also run just this setup from the repo root:

```sh
bin/setup-laptop-sleep --swap-size 96g
```

The setup script is intended to be idempotent. It:

1. Installs the tracked systemd logind/sleep drop-ins under `/etc/systemd/`.
2. Disables the stale unowned amd-debug `s2idle-hook` if it is present.
3. Creates `/swap/swapfile` on btrfs for hibernation, keeping zram as higher-priority swap.
4. Adds the `resume` mkinitcpio hook.
5. Adds `resume=` and `resume_offset=` to systemd-boot entries.
6. Regenerates initramfs when the mkinitcpio hook changes.

Reboot after running it.

## Validation

After reboot:

```sh
systemctl hibernate
```

Then test the full path with a temporarily short `HibernateDelaySec` if needed:

```sh
sudoedit /etc/systemd/sleep.conf.d/70-suspend-then-hibernate.conf
# set HibernateDelaySec=3min just for testing
systemctl suspend-then-hibernate
```

Useful logs:

```sh
journalctl -b -u systemd-suspend-then-hibernate.service --no-pager
journalctl -b | rg -i 'suspend|hibernate|s2idle|PM:|systemd-sleep'
```
