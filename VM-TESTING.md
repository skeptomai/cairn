# Testing bootstrap.sh / setup.sh in a VM

Why: validate that `bootstrap.sh` + `setup.sh` run cleanly from a genuinely
fresh CachyOS install, without touching real hardware. This tests *script
correctness* (package availability, ordering, idempotency, subvolume/file
assumptions) — it does **not** validate anything GPU- or firmware-specific
(the NVIDIA `SWAY_UNSUPPORTED_GPU` workaround, real hibernate/resume), which
are already confirmed working on the real machine and can't be exercised
under a virtual GPU/firmware anyway.

Host: the dev machine (16 cores / 30GB RAM / `vmx` present) — plenty of headroom for a
4-core/4GB test VM.

## One-time host setup

```bash
sudo pacman -S --needed qemu-full libvirt virt-install edk2-ovmf dnsmasq iptables-nft virt-viewer
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt "$USER"        # takes effect on next login/newgrp, not the current shell
sudo virsh net-start default
sudo virsh net-autostart default
```

## The ufw gotcha (this cost real debugging time)

This machine runs `ufw`, default policy `deny (incoming)` / `deny (routed)`.
Without explicit rules, a libvirt NAT VM gets **no network at all** — not a
libvirt problem, libvirt's own NAT/nftables rules were fine the whole time.
Two distinct ufw chains block two distinct things:

- **FORWARD** (routed traffic): outbound VM→internet traffic is routed
  through `wlan0`, so it needs an explicit `route allow`. Return traffic for
  connections the VM initiated is already covered by ufw's own built-in
  `RELATED,ESTABLISHED` accept rule in `ufw-before-forward` — do **not** add
  a mirrored `wlan0 → virbr0` rule "to be safe"; that permits new
  *unsolicited* inbound-initiated traffic into the VM subnet, which is real
  unneeded exposure, not symmetry.
- **INPUT** (traffic addressed to the host itself): the VM's DHCP/DNS
  requests go to `virbr0`'s own address (`192.168.122.1`), which is host
  input, not forwarding. This needs an explicit allow too — scoped to the
  actual ports libvirt's dnsmasq uses (67/udp DHCP, 53/tcp+udp DNS), not a
  blanket `allow in on virbr0` for every port.

The minimal correct ruleset:

```bash
sudo ufw route allow in on virbr0 out on wlan0
sudo ufw allow in on virbr0 to any port 67 proto udp
sudo ufw allow in on virbr0 to any port 53 proto udp
sudo ufw allow in on virbr0 to any port 53 proto tcp
sudo ufw reload
```

(Swap `wlan0` for whatever `ip route show default` reports as the uplink
interface if this is ever run on different hardware/network.)

## Install media: a downloaded ISO works fine too

Either works — pick whichever's easier to reach at the time.

**Local ISO file** (simplest — no USB device-availability juggling across
reboots): attach it as a file-backed CD-ROM. It must live somewhere
`libvirt-qemu` can actually read — a home directory with restrictive (e.g.
`700`) permissions blocks it with a `Permission denied` on boot even though
the file itself is readable by the owner, so copy it into libvirt's own
images directory first rather than fighting home-dir ACLs:

```bash
sudo cp ~/Downloads/cachyos-desktop-linux-*.iso /var/lib/libvirt/images/
sudo chown root:libvirt /var/lib/libvirt/images/cachyos-desktop-linux-*.iso

sudo qemu-img create -f qcow2 /var/lib/libvirt/images/cachyos-test.qcow2 40G

sudo virt-install \
  --connect qemu:///system \
  --name cachyos-test \
  --memory 4096 \
  --vcpus 4 \
  --cpu host-passthrough \
  --disk path=/var/lib/libvirt/images/cachyos-test.qcow2,bus=virtio,format=qcow2 \
  --disk path=/var/lib/libvirt/images/cachyos-desktop-linux-*.iso,device=cdrom,bus=sata,readonly=on \
  --boot uefi \
  --os-variant archlinux \
  --network network=default,model=virtio \
  --graphics spice \
  --video virtio \
  --noautoconsole
```

Once the installer finishes and the VM reboots, eject the CD-ROM so it
doesn't boot back into the installer instead of the newly installed
system:

```bash
sudo virsh change-media cachyos-test sda --eject --config --live
```

**Real installer USB**, if already in hand: pass the raw block device
straight through instead of the ISO file — hybrid ISOs written with `dd`
boot fine this way under UEFI. Same `virt-install` command, just
`--disk path=/dev/sda,device=cdrom,bus=sata,readonly=on` (confirm the real
device first with `lsblk -f` — look for `iso9660`, label `COS_2026xx`).
Downside versus the file-backed approach: the device has to still be
physically present and enumerated as the same path across every VM
rebuild, which a plain ISO file doesn't require.

### Rebuilding the VM from scratch (wiping a previous test)

```bash
sudo virsh destroy cachyos-test          # if running
sudo virsh undefine cachyos-test --nvram # --nvram required: fails without it if UEFI/secure boot is in use
sudo rm -f /var/lib/libvirt/images/cachyos-test.qcow2
```

Then repeat the `qemu-img create` + `virt-install` steps above. Consider
taking a snapshot (`sudo virsh snapshot-create-as cachyos-test post-install
"fresh OS install, before install.sh"`) right after the base OS install
finishes and before running `install.sh` — reverting to that snapshot is
instant, versus the ~20-30 minutes a full OS reinstall costs every time
`install.sh` itself needs a genuinely from-scratch test.

## Viewing/interacting with the VM

Must run as the normal user, **not** `sudo` — `sudo` doesn't carry Wayland/X
display authority, and the `libvirt` group membership added above needs a
fresh shell to take effect:

```bash
newgrp libvirt   # or just open a brand new terminal
virt-viewer --connect qemu:///system cachyos-test
```

## Useful commands while it's running

```bash
sudo virsh list --all                  # VM state
sudo virsh domifaddr cachyos-test      # confirm it got a DHCP lease
sudo virsh domdisplay cachyos-test     # spice:// URL if virt-viewer isn't handy
```

## Bugs this process already found

- `bootstrap.sh`'s `@swap` btrfs subvolume creation never actually created
  the subvolume on a truly fresh system (it created a throwaway subvolume at
  the wrong path and just printed manual instructions) — fixed in the commit
  that fixed the `@swap` block; see git log. It never fired on the real
  machine because `@swap` already existed there by hand.

## What this VM run should confirm before trusting a real reinstall

- `bootstrap.sh` completes with no manual intervention on a genuinely fresh
  CachyOS install (packages resolve, AUR builds succeed, `@swap` gets
  created correctly, mkinitcpio/limine edits apply without error).
- `setup.sh` symlinks everything without missing directories or ordering
  issues.
- Sway actually launches (under a generic/virtual GPU — expected to work
  without the `SWAY_UNSUPPORTED_GPU` workaround mattering here) and waybar
  and walker come up.
- Anything the scripts assume about `packages.txt` being complete gets
  caught here rather than mid-reinstall on real hardware.

**All confirmed** via `install.sh`'s first genuine start-to-finish run on a
truly fresh install, 2026-09-09 — see the dated section below.

## Lessons from the first real end-to-end run (2026-09-06/07)

Five real bugs were caught, all falling into a small number of recurring
*classes* — worth checking for these classes specifically on any future
script change, not just re-running the VM test blindly:

1. **Hardcoded machine-specific values that differ on every install.**
   `ROOT_UUID` was a literal string baked in from the dev machine's own install — broke
   the `@swap` fstab entry and the `resume=` kernel cmdline on the VM (a
   fresh root filesystem always gets a new UUID). Would have broken a real
   reinstall of the dev machine too. Fixed by computing via `findmnt -no UUID /` at
   runtime. Same class: the swapfile size was hardcoded to `32G` (sized for
   the dev machine's ~30GB RAM) and `fallocate` failed with ENOSPC on the VM's smaller
   disk — fixed by sizing off `/proc/meminfo` at runtime instead.
   **Check**: grep any script for literal UUIDs, hostnames, IPs, or sizes
   that look copied from `blkid`/`free`/`df` output on the real machine.

2. **Assumed a tool/package already exists that a fresh install doesn't
   have.** Both `yay` (no AUR helper at all on stock CachyOS) and `gum`
   (chicken-and-egg: `install.sh` needed it before `bootstrap.sh` had a
   chance to install it from `packages.txt`) were assumed pre-existing.
   Fixed by self-bootstrapping both instead of erroring with instructions.
   **Check**: does every command a script shells out to actually come from
   something `packages.txt`/`bootstrap.sh` installs *before* that point in
   the script runs — not just eventually?

3. **Hardware-conditional steps run unconditionally.** The NVIDIA hibernate
   service-enabling failed outright (`Unit ... does not exist`) on the VM's
   virtual GPU, since `nvidia-utils` was never installed. Fixed by gating
   the whole block on `lspci -k | grep -qi nvidia`.
   **Check**: any step assuming specific hardware (GPU vendor, TPM, specific
   PCI devices) should test for that hardware, not just assume this machine
   always has it.

4. **A live, hand-applied fix on the real machine that never got captured
   back into the repo.** `elephant.service` (walker's search backend) was
   created and enabled directly on the dev machine's filesystem at some point after the
   original walker bug was diagnosed — only the "install these AUR packages"
   half of that fix made it into `bootstrap.sh`/`packages.txt`; the systemd
   unit itself was never tracked. A fresh install had no idea it needed to
   exist, so walker opened but sat on "Waiting for elephant..." forever.
   **Check** (audited 2026-09-07, see below): periodically diff the *actual*
   live machine state against what the repo would produce, not just trust
   that "it works on the dev machine" means the repo fully describes why.

### 2026-09-07 audit for more of #4, plus general packages.txt drift

Ran `comm -23 <(pacman -Qqe | sort) <(packages.txt, uncommented, sorted)` to
find explicitly-installed packages missing from `packages.txt`. Most of the
diff is expected noise (CachyOS branding/kernel/bootloader packages that
ship with any CachyOS install regardless, plus this session's own
VM-testing tooling installed on the *host* — `qemu-full`, `virt-viewer`,
`libguestfs`, `tcpdump` — which is testing infrastructure, not part of the
desktop stack being tested, and deliberately not added here).

Real gaps found and fixed:
- **`ufw` is actively enabled and firewalling the dev machine, but wasn't installed or
  enabled by `bootstrap.sh` at all** — a fresh reinstall would have *no
  firewall*. Fixed: package + `systemctl enable --now ufw` added. The actual
  *rules* (the `virbr0`/libvirt ones documented above, e.g.) are deliberately
  **not** scripted — they're environment-specific and this doc already has
  the pattern to redo them by hand.
- **Desktop-infrastructure packages nothing else pulls in transitively**:
  `wireplumber`/`pipewire-alsa`/`pipewire-jack`/`pipewire-pulse` (audio would
  be silently broken without these — `pipewire` itself is a transitive dep
  already, these aren't), `polkit-gnome`/`xdg-desktop-portal-wlr` (GUI
  privilege dialogs, screen-share/file-picker portals), `rofi`,
  `cliphist`/`wl-clip-persist`/`waypaper`/`udiskie`, `power-profiles-daemon`/
  `switcheroo-control`/`upower` (laptop power management), `openssh`. All
  added to `packages.txt`.
- Checked whether `sddm` (also installed) contradicts this repo's claim that
  `greetd` is the display manager — it doesn't; `greetd.service` is the one
  actually enabled and running, `sddm.service` is disabled dead weight from
  somewhere upstream. Not a real gap, just noise.

**Known, deliberately undocumented gap**: personal application packages
(`firefox`, `discord`, `signal-desktop`, `emacs-wayland`, dev tooling like
`rustup`/`mise`/`tmux`/`glances`/`meld`) are *not* captured in
`packages.txt` — that file's scope is the desktop stack (compositor, bar,
theming, infrastructure), not personal software choices, and guessing which
personal-app packages "count" risks encoding stale/wrong assumptions. If a
real reinstall needs these reproduced exactly, regenerate against
`pacman -Qqen`/`pacman -Qqem` again and review by hand rather than trusting
this doc's list is exhaustive.

## install.sh's first genuine end-to-end run (2026-09-09)

Every prior VM cycle had tested `bootstrap.sh`/`setup.sh` directly, but
never `install.sh` itself (added 2026-09-09) on a machine where it runs in
its *actual* intended order — clone repo, then `install.sh`, nothing
pre-provisioned. That exposed one real bug immediately, plus one gap that
isn't a bug but is worth documenting:

- **Real bug**: `bootstrap.sh`'s keyboard-detection step wrote the
  generated `10-keyboard.conf` to `$HOME/.config/sway/local.conf.d/`,
  assuming that path was already the symlink `setup.sh` creates into this
  checkout. On `install.sh`'s actual order (`bootstrap.sh` runs *before*
  `setup.sh`), `~/.config/sway` is still a plain real directory at that
  point — `setup.sh` then backs the whole thing up (into
  `~/.config-backup-<timestamp>/`) and replaces it with the symlink,
  stranding the keyboard override in the backup and leaving the real
  session on `sway/config`'s tracked `us`-only fallback. Never caught
  before because every earlier VM cycle re-ran `bootstrap.sh` on top of an
  already-`setup.sh`'d machine, where the symlink already existed. Fixed
  in `ac4d36a` by writing to `sway/local.conf.d/` relative to the repo
  checkout instead of guessing through `$HOME/.config`.
- **Installer gap, not a script bug**: the base CachyOS installer's
  keyboard step only offers layout/variant (e.g. Dvorak), not modifier
  options like `ctrl:swapcaps`. A fresh install that wants that option has
  to set it manually (`sudo localectl set-x11-keymap us pc105 dvorak
  ctrl:swapcaps`) and re-run `bootstrap.sh` before it'll show up anywhere —
  `bootstrap.sh` correctly mirrors whatever `localectl` reports, it just
  can't invent an option you never set. Documented in the README's
  "Customizing the keyboard layout" section.

With both addressed, `install.sh` completed a full, unattended-except-for-
the-gum-prompts run: fresh install → clone → `install.sh` (bootstrap →
setup → theme pick → reboot) → clean login at the greeter with the correct
layout → working Sway/waybar/walker/elephant session. First time this
exact path has been verified rather than assumed.

## Remote access to the VM (no more shutdown/guestfish for routine syncs)

Once a fresh VM has a home directory (post-install), get `your-user@your-real-machine`'s own key
in and skip the console entirely:

```bash
# one-time, from the host:
sudo virsh shutdown cachyos-test   # or let it be managed-saved
sudo guestfish -a /var/lib/libvirt/images/cachyos-test.qcow2 <<'EOF'
run
mount btrfsvol:/dev/sda2/@ /
mount btrfsvol:/dev/sda2/@home /home
mkdir-p /home/youruser/.ssh
upload <(cat ~/.ssh/id_rsa.pub) /home/youruser/.ssh/authorized_keys
chmod 0700 /home/youruser/.ssh
chmod 0600 /home/youruser/.ssh/authorized_keys
command "chown -R 1000:1000 /home/youruser/.ssh"
upload <(echo 'youruser ALL=(ALL) NOPASSWD: ALL') /etc/sudoers.d/99-nopasswd-youruser
chmod 0440 /etc/sudoers.d/99-nopasswd-youruser
command "visudo -cf /etc/sudoers.d/99-nopasswd-youruser"
ln-sf /usr/lib/systemd/system/sshd.service /etc/systemd/system/multi-user.target.wants/sshd.service
command "sed -i s/^ENABLED=yes/ENABLED=no/ /etc/ufw/ufw.conf"
EOF
sudo virsh start cachyos-test
```

**Only skip the two lines above (`ln-sf sshd.service` and the `ufw.conf`
sed) if `bootstrap.sh` has already run on this VM at least once** (it now
enables sshd and adds an ssh-allow ufw rule itself, see its own comments)
-- this recipe was originally written assuming that, and broke silently
on a genuinely virgin install (installer only, no bootstrap.sh yet) on
2026-09-07, in *two separate layers*:

1. `sshd` was never enabled at all (installing the `openssh` package
   doesn't enable the service).
2. CachyOS's own installer ships `ufw` **explicitly installed and
   already enabled** (default-deny-incoming) from first boot, before any
   of this repo's scripts have run at all -- so even with sshd enabled,
   the connection still timed out (not refused) until ufw was disabled
   or given an explicit allow rule.

The connection just times out silently either way, with nothing to
indicate which of the two (or both) is the actual cause -- check
`systemctl is-enabled sshd` and `sudo ufw status` on the console if this
recipe ever fails again. `bootstrap.sh` re-enables ufw properly (with
the ssh-allow rule) as one of its own steps, so disabling it here is
only a temporary pre-bootstrap state, not a lasting security decision.

**Gotcha found doing this**: `bootstrap.sh` enabling `ufw` (default-deny
incoming) with no `allow ssh` rule locks this out immediately — fixed in
`bootstrap.sh` itself (`sudo ufw allow ssh` before enabling the service), so
this only bites if testing against an older checkout.

From then on, routine updates are just:

```bash
rsync -a ~/cairn/ youruser@192.168.122.39:~/cairn/
ssh youruser@192.168.122.39 'cd ~/cairn && ./bootstrap.sh'
```

The VM's default shell is `fish`, not `bash` — a multi-line inline `ssh host
'...'` script gets parsed by fish first and often breaks (e.g. `VAR=$(...)`
syntax). Write an actual script with a `#!/usr/bin/env bash` shebang, `scp`
it over, then `ssh host /path/to/script.sh` instead of inlining.

Only reach for the shutdown/guestfish dance again for genuinely offline-only
changes (partition/fstab-level edits, or recovering from a state broken
badly enough that the graphical session/sshd won't come up).

## "Display output is not active" in virt-viewer

The VM's `swayidle` blanks its virtual output via DPMS after 600s idle (same
`sway/config` as the real machine) and only wakes on real input activity —
but nothing touches the VM's keyboard/mouse while no one's connected via
virt-viewer, so it sits blanked between sessions. spice/virt-viewer then
shows "Display output is not active" until DPMS is explicitly turned back
on. Not a crash. Fix from the host:

```bash
./vm-wake-display.sh youruser@192.168.122.39
```

(`swaymsg` needs `SWAYSOCK` spelled out explicitly over a plain
non-interactive SSH session — it doesn't auto-discover it there the way a
real logged-in shell does — and the socket filename embeds sway's PID, so
it isn't a fixed path; the script re-discovers it each time. Also routes
around the VM's fish-vs-bash quoting gotcha below.)

**Permanent fix, once per VM** (so you stop needing the wake script at
all): add a `local.conf.d` drop-in — this directory is the exact mechanism
`sway/config`'s own tail comment sets aside for per-machine overrides not
tracked in git — that kills the shared `swayidle` and re-execs it without
the `timeout 600 'output * dpms off'` clause:

```
# ~/.config/sway/local.conf.d/20-vm-no-dpms-idle.conf
exec_always pkill -x swayidle; swayidle -w \
    lock "swaylock -f -c 1b1e26" \
    timeout 300 "swaylock -f -c 1b1e26" \
    before-sleep "swaylock -f -c 1b1e26"
```

Then `swaymsg reload` (or just log out/in). The VM still locks on idle and
before sleep — it just never blanks the output, since nothing's around to
un-blank it. Copying the file over fish's heredoc limitation (see below):
`scp` it from the host rather than trying to heredoc it over `ssh`.

## VM display is small by default (1280x800) and doesn't persist a change

The virtual GPU's default mode is only 1280x800 — not enough for some
apps (e.g. btop refuses to run, complaining the terminal is too small).
Bump it for the current session:

```bash
swaymsg output "Virtual-1" resolution 1920x1080
```

(The VM's other available modes came back via `swaymsg -t get_outputs`,
which lists everything the virtual GPU reports — 1920x1080, 3840x2160, etc.)

To make it stick across reboots, drop a file in
`~/.config/sway/local.conf.d/` (not tracked in this repo — the output name
`Virtual-1` is meaningless on real hardware, and `sway/config` already
`include`s this directory for exactly this kind of machine-specific
override):

```bash
mkdir -p ~/.config/sway/local.conf.d
echo 'output "Virtual-1" resolution 1920x1080' > ~/.config/sway/local.conf.d/vm-resolution.conf
swaymsg reload
```
