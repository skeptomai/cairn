# Suspend debug plan (omen, dGPU disabled in BIOS)

Started 2026-11-21. Hibernate was fixed the same day (see `hibernate-resume-debug-plan.md`:
the mkinitcpio `kms` hook was the cause). Suspend is a separate problem. Check each item off
with its result and date as it is run.

## Observed

- **Original failure (2026-11-20/21, boot -3):** three s2idle cycles worked on Nov 20
  (12:15, 14:48, 15:40). The overnight one (entered 15:40:56, woken 06:18:57) ended with the
  user reporting a frozen display and keyboard. The kernel journal shows the kernel *did*
  finish resuming (`PM: suspend exit`, i915 GuC/HuC re-initialised, no drm errors). So the
  freeze was not a kernel hang like the hibernate one. Userspace was alive (waybar, systemd
  timers) and a terminal was used at 06:20:29. What exactly froze is unexplained.
- **iwlwifi (Intel AX211/BE, `bz-b0-gf-a0-100.ucode`) firmware dies over time.** `Microcode SW
  error` at 14:30 on Nov 20, then `device is gone during suspend` at the 15:40 suspend entry
  (so the wifi was already dead *before* sleeping), then `Failed to start RT ucode: -110`
  on every restart attempt. Only a reboot recovered it. Not established whether the wifi
  death causes the freeze or is a separate bug.
- **Baseline retests (2026-11-21, after the `kms` removal):** `systemctl suspend` (power
  button wake, ~20s) and a lid close/open (~5 min) both worked cleanly. Display and rustlock
  came back instantly, no iwlwifi/i915/ACPI errors, `suspend_stats` 2 success / 0 fail.
  The overnight failure has not been reproduced.
- **s2idle is not saving power.** Measured after the lid test: Package C-state residency was
  C2 only (C3 to C10 = 0), `slp_s0_residency_usec` = 0, all `S0i2.x` substate residencies = 0.
  The HP EC fires ACPI `GPE 0x6E` (the EC's own event line) ~87 times/s even while awake. In
  sleep this woke the machine 164 times in ~5 min (about once a second); the kernel re-idles
  each time. This is why the power button LED pulsed. Net effect: sleep is roughly idle with the
  screen off, so overnight battery drain is high.
- `/sys/power/mem_sleep` = `[s2idle] deep`: real S3 is offered by the firmware
  (`ACPI: PM: (supports S0 S3 S4 S5)`) and has never been tried.
- Other noise, not yet chased: `ACPI Error: No handler for Region [CMS0] SystemCMOS` aborting
  `\_SB.PC00.LPCB.EC0._Q33` on resume; `typec port1-partner: parent port1 should not be
  sleeping`. BIOS is HP F.03 07/11/2025.

## Unknowns (do not assume)

- Whether the original freeze was lid-triggered, lock-screen-triggered, or compositor/GPU
  related. Only reproduced once, after a very long sleep.
- Whether the wifi firmware death causes the freeze or just coincides with it.
- Whether S3 resume works at all on this BIOS (the hibernate failure was a firmware-path
  hang, so S3 could hang the same way).

## Tests

For every test: before it, save work. After it, note whether display and keyboard came back,
and how long it took. If stuck: lock screen or plain black; keyboard backlight, Caps Lock LED,
Ctrl+Alt+F2 behaviour; whether a forced power-off was needed. Then read
`journalctl -b -1` (previous boot) or the current boot's kernel log.

### 1. S3 (`deep`) instead of s2idle (runtime switch, no config change)
- [ ] Run: `echo deep | sudo tee /sys/power/mem_sleep`, then `systemctl suspend`.
      Revert (or just reboot): `echo s2idle | sudo tee /sys/power/mem_sleep`.
- Pass: returns cleanly, no EC wake loop, and `lps0` is not used. Then make it permanent
  with `mem_sleep_default=deep` on the cmdline and run a long-sleep test.
- Fail (black screen, dead input, forced reboot): the firmware S3 resume path is broken on
  this BIOS, same family as the old hibernate hang. Stay on s2idle and go to test 2.
- Result:

### 2. Stop the EC from waking s2idle
- [ ] Try the boot parameters `acpi.ec_no_wakeup=1`, then `acpi.ec_freeze_events=1`, one at a
      time (both exist under `/sys/module/acpi/parameters/`). Do NOT mask `GPE 0x6E`
      (`acpi_mask_gpe`): it is the EC's own event line and masking it would likely break
      lid, battery and hotkey events.
- Pass: far fewer `Timekeeping suspended` wake loops, and nonzero `slp_s0_residency_usec`
  and Package C6+ residency after a sleep.
- Result:

### 3. Wifi firmware hardening
- [ ] Add a systemd-sleep hook that unloads `iwlwifi` before sleep and reloads it after.
      Only worth doing if the wifi still dies across cycles after tests 1 and 2.
- Result:

### 4. Long-sleep test
- [ ] Sleep for several hours (overnight) with the lid closed, on whichever configuration
      passed. The original failure only showed up after 14.5 hours.
- Result:

## Recording the outcome

When one test explains the failure, update `CLAUDE.md` ("Things to not re-litigate", the
suspend entry) and move the fix into `bootstrap.sh`.
