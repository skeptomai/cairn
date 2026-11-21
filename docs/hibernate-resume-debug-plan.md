# Hibernate resume failure: debug plan (omen, dGPU disabled in BIOS)

Started 2026-11-21. Check each item off with its result and date as it is run.

## Observed (2026-11-21 hibernate attempt, boot -1)

- `systemctl hibernate` entered hibernation fine (`PM: hibernation: hibernation entry`
  at 06:49:14; nvidia-hibernate service and system-sleep/nvidia hook ran, as no-ops).
- On power-on: black display, no response to repeated lid close/open, hard reboot needed.
- **No journal exists for the resume attempt**, so the hang was before userspace:
  firmware, bootloader, initramfs, or the image restore itself.
- The next boot (hard reboot) found no image: `Unable to resume from device ... continuing
  boot process`, and the EFI `HibernateLocation` var was already gone. The failed resume
  attempt consumed the image.
- Setup: Intel Arrow Lake-P iGPU only (dGPU off in BIOS). Both `i915` and `xe` are loaded;
  the iGPU is bound to `i915`. Kernel 7.2.4-3-cachyos. `resume=` and `resume_offset=` are on
  the cmdline; initramfs has the `resume` hook (systemd-based, after `kms`).
- The s2idle suspend failure on 2026-11-20/21 had the same symptoms (black display, dead
  input). Likely a shared cause, probably Intel graphics or platform, not NVIDIA.

## Unknowns (do not assume)

- Which kernel version the 2026-09-05 successful hibernate used. A kernel change is not
  established as the cause.
- Whether the dGPU being disabled matters at all (test 3 answers this directly).

## Tests

For every test: note whether the display and input came back, and capture
`journalctl -b -1` afterward.

### 1. `test_resume`: kernel image write, read and restore, no power-off
- [x] Run: `echo test_resume | sudo tee /sys/power/disk; echo disk | sudo tee /sys/power/state`
- Pass: system returns to the desktop with display and input working.
- Fail (hang or black display): the fault is in the kernel and driver restore path. Firmware
  and power-off are ruled out. Go to test 4.
- Result (2026-11-21): **PASS, with a visible glitch.** Display started to return, froze
  about 10s, went black, then came back fully functional. The kernel log is clean:
  snapshot allocated (9.1 GB), CPUs offlined and re-onlined, i915 re-initialised GuC/HuC on
  both GTs, USB re-enumerated, tasks restarted, `hibernation exit`, wifi re-associated.
  No drm, i915 or sway errors. Only noise: waybar "Unable to replace properties" for
  about 0.6s, an xhci "invalid context state" warning, and a bluez adv_monitor warning.
  Limits of this result: `test_resume` never powers off, so the firmware and the boot
  kernel's own i915 init are not exercised. The failing case involves both (the boot
  kernel brings up the GPU before restoring the old kernel over it). A pass here narrows the
  fault to that cold-resume path. It does not clear i915. The freeze/black glitch is
  unexplained by the logs.

### 2. `reboot` mode: write the image, then reboot straight into resume
- [x] Run: `echo reboot | sudo tee /sys/power/disk; echo disk | sudo tee /sys/power/state`
- Skips systemd hooks and the firmware power-off path. Compare against plain
  `systemctl hibernate`.
- Pass here but fail with `systemctl hibernate`: the problem is in the firmware power-cycle
  path (BIOS update or setting). Fail here too: the restore path again.
- Result (2026-11-21): **FAIL.** `hibernation entry` logged at 07:11:54 (boot -1, last
  journal line), then the machine rebooted into resume: power came back, display stayed
  black through repeated lid close/open, hard reset needed. Same symptoms as the
  `systemctl hibernate` failure. The next boot (07:17:49) again found `HibernateLocation`
  unset, so the image was consumed. Also observed: the **RGB keyboard went from black to
  assorted colours**, i.e. the keyboard controller lost its configured state. That fits a
  firmware or EC level reset during the resume boot, not a normal kernel resume (which
  restores it, as in test 1).
  Conclusions: the firmware power-off path is ruled out (reboot mode skips it), and so is
  the systemd sleep hook path. The fault is in the cold-resume restore path (boot kernel
  and initramfs bring up the GPU, then restore the old kernel over it). Go to test 4.

### 3. A/B on the dGPU
- [ ] Enable the dGPU in BIOS and repeat `systemctl hibernate`.
- Pass: the dGPU being disabled breaks the chain, so document it as a constraint.
- Fail: NVIDIA is irrelevant, so drop it from the suspect list.
- Result:

### 4. Pin the iGPU driver
- [ ] 4a. Add `xe.force_probe=!7d51 i915.force_probe=7d51` to the cmdline (or blacklist `xe`).
- [~] 4b. Remove the `kms` hook from `/etc/mkinitcpio.conf` HOOKS, rebuild the initramfs,
      and retest. This keeps the GPU from initializing in the initramfs before the restore.
      **APPLIED 2026-11-21. RESULT: PASS.** Plain `systemctl hibernate`, power-off, power
      button: desktop restored perfectly (entry 07:26:33, image restored same boot 07:27:39).
      Single successful run so far; the earlier failures were 2 of 2.
  - **Why `kms` was there (history check):** no record of a deliberate choice. The repo's
    only commit (`6763cf0`) and its docs never mention adding it. `kms` is in the stock
    CachyOS/mkinitcpio HOOKS line (`base systemd autodetect microcode kms modconf block
    keyboard sd-vconsole ...`), and `bootstrap.sh` only inserts `resume`, never touching
    `kms`. The only documented early-KMS decision is the opposite one: NVIDIA modules must
    be kept *out* of early KMS (`docs/hibernate-swap-luks.md`). So treat `kms` as an
    unexamined distro default, not a fix for anything we know of.
  - **Known costs of removing it:** with no early KMS, plymouth falls back to the
    simpledrm/efifb framebuffer, so the boot splash may look different or appear later
    (the GPU driver loads from the rootfs instead). Nothing else is known to depend on it.
  - **What changed:** `/etc/mkinitcpio.conf` HOOKS lost `kms`; `mkinitcpio -P` rebuilt the
    initramfs (verified: no i915/xe/drm modules inside). Backup of the original:
    `/etc/mkinitcpio.conf.bak-pre-kms-experiment`.
  - **Revert:** `sudo cp -a /etc/mkinitcpio.conf.bak-pre-kms-experiment /etc/mkinitcpio.conf && sudo mkinitcpio -P`.
  - **Promoted to `bootstrap.sh` and `CLAUDE.md` 2026-11-21** after the pass above.
  - Remaining tests (3, 4a, 4c, 5, 6) are not needed unless this regresses. Untested:
    whether the same fix holds with the NVIDIA dGPU re-enabled, and whether it also fixes
    the s2idle suspend failure (the AX211 wifi firmware death is a separate issue).
- [ ] 4c. Try `i915.enable_psr=0`, then `i915.enable_dc=0`, one at a time.
- Result:

### 5. Capture a console log of the hang
- [ ] Add `no_console_suspend initcall_debug` to the cmdline (`ignore_loglevel` is already
      there). Consider `pstore` or a persistent journal for the last messages.
- Result:

### 6. Firmware and BIOS
- [ ] Check for a BIOS update for the HP Omen.
- [ ] Try the BIOS sleep and power options, if any are exposed.
- Result:

## Recording the outcome

When one test explains the failure, update `CLAUDE.md` ("Things to not re-litigate",
hibernate and suspend entries) and `docs/hibernate-swap-luks.md`, and move the fix into
`bootstrap.sh`.
