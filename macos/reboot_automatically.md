# Periodic Mac mini restart

The Mac mini does not use a `pmset` periodic restart or a system LaunchDaemon.
The active setup uses a native Codex Scheduled Task:

- Schedule: daily at 03:00.
- Script: `~/.codex/scripts/restart-every-3-days.sh`.
- The script date-gates the restart to every third day.
- Restart action: macOS `System Events`, not `sudo` or `shutdown`.

Keep the scheduler and date gate together. Do not add a second `pmset` or
LaunchAgent restart path. Verify with:

```bash
pmset -g sched
open -a ChatGPT
```

`pmset -g sched` should not show a repeating restart or wake entry. ChatGPT's
Scheduled list should show the active daily `03:00` Codex task.

To change or remove the schedule, edit or disable the existing native Codex
task. Do not recreate it without first checking for the existing task, because
duplicate restart owners can cause unexpected reboots.
