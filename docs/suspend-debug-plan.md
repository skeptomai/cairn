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
- Whether cold storage of the laptop contributed to the original overnight freeze (user's
  theory, 2026-11-21: the laptop had been kept in quite cold conditions). Checked the journal
  (nothing: no temperature or battery logging beyond boot-time `TZ01 30 C`) and upower's
  battery history (`/var/lib/upower/history-*-Primary-*.dat`, root-only). On Nov 20 the pack
  discharged smoothly: 12.57 V at 94% (12:00) to 11.44 V at 58% (14:22, close to the 14:30
  iwlwifi firmware crash) to 11.31 V at 50% (15:31), with no voltage cliff or sag. So no
  evidence of cold-induced brownout, but cell temperature is not recorded anywhere, so it is
  not ruled out. It cannot explain the S3 hang (hit ~30 min after boot on a warm machine).
  The overnight test (4) on a warm laptop is the discriminating experiment.

## Tests

For every test: before it, save work. After it, note whether display and keyboard came back,
and how long it took. If stuck: lock screen or plain black; keyboard backlight, Caps Lock LED,
Ctrl+Alt+F2 behaviour; whether a forced power-off was needed. Then read
`journalctl -b -1` (previous boot) or the current boot's kernel log.

### 1. S3 (`deep`) instead of s2idle (runtime switch, no config change)
- [x] Run: `echo deep | sudo tee /sys/power/mem_sleep`, then `systemctl suspend`.
      Revert (or just reboot): `echo s2idle | sudo tee /sys/power/mem_sleep`.
- Pass: returns cleanly, no EC wake loop, and `lps0` is not used. Then make it permanent
  with `mem_sleep_default=deep` on the cmdline and run a long-sleep test.
- Fail (black screen, dead input, forced reboot): the firmware S3 resume path is broken on
  this BIOS, same family as the old hibernate hang. Stay on s2idle and go to test 2.
- Result (2026-11-21, **FAIL**): journal's last kernel line is `PM: suspend entry (deep)`
  at 07:50:27, then nothing (only wpa_supplicant shutting down wlan0 18 ms later). No
  device-suspend or `PM: suspend exit` messages, so the machine hung while entering S3 or
  on resume, before any driver logged. Power LED never fully went off after 2 min. A power-button
  press brought it up with a solid LED and a differently-lit keyboard backlight, a blank screen,
  and no response to input or lid close/open. A forced power-off was needed. This is the same
  firmware-path failure as the old hibernate hang, so S3 is not viable on this BIOS (F.03). Stay
  on s2idle (`mem_sleep` reverts to `[s2idle]` on reboot, nothing persistent was changed). Do not
  set `mem_sleep_default=deep`. Next: test 2.

### 2. Stop the EC from waking s2idle
- [x] Try the boot parameters `acpi.ec_no_wakeup=1`, then `acpi.ec_freeze_events=1`, one at a
      time (both exist under `/sys/module/acpi/parameters/`). Do NOT mask `GPE 0x6E`
      (`acpi_mask_gpe`): it is the EC's own event line and masking it would likely break
      lid, battery and hotkey events.
- Pass: far fewer `Timekeeping suspended` wake loops, and nonzero `slp_s0_residency_usec`
  and Package C6+ residency after a sleep.
- Result (2026-11-21, **PASS**): set at runtime with
  `echo 1 | sudo tee /sys/module/acpi/parameters/ec_no_wakeup` (the param is writable, no reboot
  needed). Lid closed 08:00:06 to 08:11:11 (665 s): `Timekeeping suspended` wake loops 0 (was
  164 in 5 min), `last_hw_sleep` 660 s (about 99% of the sleep, was 0), Package C10 residency
  661 s (was C2 only), `suspend_stats` 1 success / 0 fail, display and input restored. Only
  `ec_no_wakeup` was tried, so `ec_freeze_events` is unneeded. Made permanent in `bootstrap.sh`
  (limine cmdline). Remaining: test 4 (overnight) to see if the original freeze recurs; test 3
  (iwlwifi) only if wifi dies again.

### 3. Wifi firmware hardening
- [ ] Add a systemd-sleep hook that unloads `iwlwifi` before sleep and reloads it after.
      Only worth doing if the wifi still dies across cycles after tests 1 and 2.
- Result:

### 4. Long-sleep test
- [ ] Sleep for several hours (overnight) with the lid closed, on whichever configuration
      passed. The original failure only showed up after 14.5 hours.
- Result (2026-11-22, **PASS**), with `acpi.ec_no_wakeup=1`, five s2idle cycles on one boot, all
  resumed cleanly (`suspend_stats` 5 success / 0 fail, no hang, display and input back):
  08:34 to 12:06 (3 h 32), 13:09 to 14:32 (1 h 22), 15:24 to 20:12 (4 h 48), **21:41 to 07:04
  (9 h 23, the overnight)**. Total sleep about 69,350 s. Cumulative Package C10 residency 69,290 s
  and `slp_s0_residency_usec` 64,294 s (about 93%), so the machine reaches real deep idle.
  Battery: the 4 h 48 afternoon sleep ran on battery and went 87% to 86% (about 0.2%/h).
  The overnight was likely on the charger (100% at 21:04), so its drain is unmeasured. No
  iwlwifi `Microcode SW error`, `device is gone` or `Failed to start RT ucode` anywhere in the boot;
  only the usual post-resume `authentication ... timed out` lines while wlan0 re-associates, and
  the known `CMS0` ACPI error. `last_hw_sleep` only reflects the last cycle and read inconsistent
  values (4095 s then 3656 s for much longer sleeps), so use the cumulative counters instead.
  The original 14.5 h freeze did not recur in 9 h 23, so it is unexplained but unreproduced; the
  cold-storage theory remains unproven. Test 3 (iwlwifi hook) is not needed.

## Recording the outcome

When one test explains the failure, update `CLAUDE.md` ("Things to not re-litigate", the
suspend entry) and move the fix into `bootstrap.sh`.
