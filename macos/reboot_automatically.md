# Periodic Mac mini restart

The Mac mini uses a dedicated system LaunchDaemon to execute an automated daily reboot as the final stage of the nightly maintenance pipeline:

- **LaunchDaemon:** `/Library/LaunchDaemons/com.alejandro.restart.plist`
- **Schedule:** Daily at `08:15 ICT` (`01:15 UTC`).
- **Action:** `/sbin/shutdown -r now`
- **Managed by:** `defaults.sh` (`install_system_daemon com.alejandro.restart`)

`pmset` repeating schedules are cancelled (`sudo pmset repeat cancel`) to avoid duplicate reboot ownership.

Verify the loaded daemon with:

```bash
sudo launchctl print system/com.alejandro.restart
pmset -g sched
```

`pmset -g sched` should show no active repeating restart or wake entries. `launchctl` should show `com.alejandro.restart` active with `StartCalendarInterval = { Hour = 8; Minute = 15; }`.
