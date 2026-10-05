#!/usr/bin/env python3
import importlib.util
import subprocess
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

MODULE_PATH = Path(__file__).resolve().parents[1] / "orbstack-recovery.py"
SPEC = importlib.util.spec_from_file_location("orbstack_recovery", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

LOCK_HOLDER = """
import fcntl, sys, time
handle = open(sys.argv[1], "r+")
fcntl.lockf(handle, fcntl.LOCK_EX)
sys.stdout.write("locked\\n")
sys.stdout.flush()
time.sleep(30)
"""


class FakeRecovery(MODULE.OrbStackRecovery):
    """Offline double: every probe and every side effect is scripted."""

    def __init__(self, root: Path):
        super().__init__(
            state_path=root / "state.json",
            log_path=root / "recovery.log",
            lock_path=root / "recovery.lock",
        )
        self.actions = []
        self.alerts = []
        self.network_ok = True
        self.boot_grace = False
        self.backup_held = False
        self.orb_status = "running"
        self.current_vm_state = "running"
        self.ingress_healthy = True
        self.docker_state = "ok"
        self.hang_marker = False
        self.wait_recovers = True

    # probes
    def host_network_ok(self):
        return self.network_ok

    def within_boot_grace(self, now):
        return self.boot_grace

    def backup_in_progress(self):
        return self.backup_held

    def orbctl_status(self):
        return self.orb_status

    def vm_state(self):
        return self.current_vm_state

    def docker_sock_state(self):
        return self.docker_state

    def vmgr_hang_marker(self, now=None):
        return self.hang_marker

    def ingress_ok(self):
        return self.ingress_healthy

    # actions
    def open_orbstack_app(self):
        self.actions.append("open_app")
        return True

    def launch_orbstack(self):
        self.actions.append("launch_orbstack")
        return True

    def kill_orbstack(self):
        self.actions.append("kill_orbstack")
        return True

    def wait_for_recovery(self, timeout):
        self.actions.append(f"wait({timeout})")
        return self.wait_recovers

    def start_vm(self):
        self.actions.append("start_vm")
        return True

    def restart_vm(self):
        self.actions.append("restart_vm")
        return True

    def alert(self, subject, body):
        self.alerts.append(subject)
        return True


class OrbStackRecoveryTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)

    def tearDown(self):
        self._tmp.cleanup()

    def recovery(self, **kwargs):
        recovery = FakeRecovery(self.root)
        for key, value in kwargs.items():
            setattr(recovery, key, value)
        return recovery

    # ------------------------------------------------------------- baseline set

    def test_healthy_runtime_is_noop_and_clears_failures(self):
        recovery = self.recovery()
        recovery.save_state(dict(MODULE.OrbStackRecovery.default_state(), ingress_failures=1))
        self.assertEqual(recovery.run_cycle(now=2_000), "healthy")
        self.assertEqual(recovery.actions, [])
        self.assertEqual(recovery.load_state()["ingress_failures"], 0)

    def test_second_ingress_failure_restarts_vm(self):
        recovery = self.recovery(ingress_healthy=False)
        self.assertEqual(recovery.run_cycle(now=2_000), "ingress_failure")
        self.assertEqual(recovery.actions, [])
        self.assertEqual(recovery.run_cycle(now=2_301), "vm_restarted")
        self.assertEqual(recovery.actions, ["restart_vm"])

    def test_stopped_vm_is_started(self):
        recovery = self.recovery(current_vm_state="stopped", ingress_healthy=False)
        self.assertEqual(recovery.run_cycle(now=2_000), "vm_started")
        self.assertEqual(recovery.actions, ["start_vm"])

    def test_starting_vm_is_left_alone(self):
        recovery = self.recovery(current_vm_state="starting", ingress_healthy=False)
        self.assertEqual(recovery.run_cycle(now=2_000), "vm_starting")
        self.assertEqual(recovery.actions, [])

    def test_orbstack_down_launches_app_without_host_reboot(self):
        recovery = self.recovery(orb_status="down", ingress_healthy=False)
        self.assertEqual(recovery.run_cycle(now=2_000), "orbstack_started")
        self.assertEqual(recovery.actions, ["launch_orbstack"])

    def test_unhealthy_host_network_never_touches_orbstack(self):
        recovery = self.recovery(network_ok=False, orb_status="down", ingress_healthy=False)
        self.assertEqual(recovery.run_cycle(now=2_000), "network_unhealthy")
        self.assertEqual(recovery.actions, [])

    def test_cooldown_blocks_repeat_actions(self):
        recovery = self.recovery(current_vm_state="stopped", ingress_healthy=False)
        recovery.save_state(dict(MODULE.OrbStackRecovery.default_state(), last_action=1_900))
        self.assertEqual(recovery.run_cycle(now=2_000), "cooldown")
        self.assertEqual(recovery.actions, [])

    def test_boot_grace_defers_action(self):
        recovery = self.recovery(boot_grace=True, ingress_healthy=False)
        self.assertEqual(recovery.run_cycle(now=2_000), "boot_grace")
        self.assertEqual(recovery.actions, [])

    # ------------------------------------------- the wedge this failed to fix

    def test_wedged_docker_socket_hard_kills_and_relaunches(self):
        """The 2026-10-05 failure: daemon alive, VM dead, `open -a` a no-op."""
        recovery = self.recovery(docker_state="wedged", ingress_healthy=False)
        self.assertEqual(recovery.run_cycle(now=2_000), "hard_restarted")
        self.assertEqual(recovery.actions, ["kill_orbstack", "open_app", "wait(180)"])

    def test_wedged_vmgr_hang_marker_hard_kills_without_socket_evidence(self):
        recovery = self.recovery(hang_marker=True, ingress_healthy=False)
        self.assertEqual(recovery.run_cycle(now=2_000), "hard_restarted")
        self.assertEqual(recovery.actions[0], "kill_orbstack")

    def test_wedged_orbctl_timeout_hard_kills(self):
        recovery = self.recovery(orb_status="timeout", ingress_healthy=False)
        self.assertEqual(recovery.run_cycle(now=2_000), "hard_restarted")
        self.assertEqual(recovery.actions[0], "kill_orbstack")

    def test_wedge_never_settles_for_launching_the_app_alone(self):
        recovery = self.recovery(docker_state="wedged", ingress_healthy=False)
        recovery.run_cycle(now=2_000)
        self.assertNotIn("launch_orbstack", recovery.actions)
        self.assertIn("kill_orbstack", recovery.actions)

    def test_escalation_alerts_once_per_incident_and_rearms_after_recovery(self):
        recovery = self.recovery(docker_state="wedged", ingress_healthy=False)
        self.assertEqual(recovery.run_cycle(now=2_000), "hard_restarted")
        self.assertEqual(len(recovery.alerts), 1)
        # still wedged inside the same incident: act again, but do not re-alert
        recovery.save_state(dict(recovery.load_state(), last_action=0))
        self.assertEqual(recovery.run_cycle(now=3_000), "hard_restarted")
        self.assertEqual(len(recovery.alerts), 1)
        # a healthy cycle re-arms the alert for the next incident
        recovery.ingress_healthy = True
        recovery.docker_state = "ok"
        self.assertEqual(recovery.run_cycle(now=4_000), "healthy")
        self.assertFalse(recovery.load_state()["alerted_escalation"])

    def test_persistent_soft_failure_escalates_to_hard_restart(self):
        recovery = self.recovery(ingress_healthy=False)
        recovery.save_state(
            dict(MODULE.OrbStackRecovery.default_state(), ingress_failures=3, last_action=0)
        )
        self.assertEqual(recovery.run_cycle(now=2_000), "hard_restarted")
        self.assertEqual(recovery.actions[0], "kill_orbstack")

    def test_failed_hard_restart_is_reported(self):
        recovery = self.recovery(docker_state="wedged", ingress_healthy=False, wait_recovers=False)
        self.assertEqual(recovery.run_cycle(now=2_000), "hard_restart_failed")

    def test_budget_spent_gives_up_alerts_once_and_stops_acting(self):
        recovery = self.recovery(docker_state="wedged", ingress_healthy=False)
        recovery.save_state(
            dict(MODULE.OrbStackRecovery.default_state(), hard_kills=[1_900, 1_950])
        )
        self.assertEqual(recovery.run_cycle(now=2_000), "gave_up")
        self.assertEqual(recovery.actions, [])
        self.assertEqual(len(recovery.alerts), 1)
        # the same failure must not alert again while it persists
        self.assertEqual(recovery.run_cycle(now=2_100), "gave_up")
        self.assertEqual(len(recovery.alerts), 1)

    def test_hard_kills_outside_the_window_do_not_count(self):
        recovery = self.recovery(docker_state="wedged", ingress_healthy=False)
        recovery.save_state(
            dict(MODULE.OrbStackRecovery.default_state(), hard_kills=[2_000 - 4_000])
        )
        self.assertEqual(recovery.run_cycle(now=2_000), "hard_restarted")

    def test_main_exits_nonzero_on_give_up(self):
        with patch.object(MODULE, "OrbStackRecovery") as recovery_class:
            recovery_class.return_value.run_locked.return_value = "gave_up"
            self.assertEqual(MODULE.main([]), 1)
            recovery_class.return_value.run_locked.return_value = "healthy"
            self.assertEqual(MODULE.main([]), 0)

    # --------------------------------------------------------- backup locking

    def test_backup_lock_held_by_another_process_skips_and_reserves_no_attempt(self):
        lock_path = self.root / "backup.lock"
        lock_path.touch()
        holder = subprocess.Popen(
            ["/usr/bin/python3", "-c", LOCK_HOLDER, str(lock_path)],
            stdout=subprocess.PIPE,
            text=True,
        )
        try:
            self.assertEqual(holder.stdout.readline().strip(), "locked")
            with patch.object(MODULE, "BACKUP_LOCK", lock_path):
                recovery = MODULE.OrbStackRecovery(
                    state_path=self.root / "state.json",
                    log_path=self.root / "recovery.log",
                    lock_path=self.root / "recovery.lock",
                )
                self.assertTrue(recovery.backup_in_progress())
                recovery.host_network_ok = lambda: True
                recovery.within_boot_grace = lambda now: False
                recovery.ingress_ok = lambda: False
                recovery.kill_orbstack = lambda: self.fail("must not act during backup")
                self.assertEqual(recovery.run_cycle(now=2_000), "backup_in_progress")
                self.assertEqual(recovery.load_state()["ingress_failures"], 0)
        finally:
            holder.terminate()
            holder.wait(timeout=10)

    def test_decoy_process_mentioning_the_backup_name_does_not_skip_recovery(self):
        """Regression: `pgrep -f mac-mini-backup` matched unrelated command lines.

        A shell, a diagnostic command or a delegated agent's prompt that merely
        contains the string used to suppress recovery. Only the lock is proof.
        """
        decoy = subprocess.Popen(["/bin/sh", "-c", "exec -a mac-mini-backup-decoy sleep 30"])
        try:
            listing = subprocess.run(
                ["/bin/ps", "-o", "command=", "-p", str(decoy.pid)],
                stdout=subprocess.PIPE,
                text=True,
                check=False,
            ).stdout
            self.assertIn("mac-mini-backup-decoy", listing)
            lock_path = self.root / "backup.lock"
            lock_path.touch()
            with patch.object(MODULE, "BACKUP_LOCK", lock_path):
                recovery = MODULE.OrbStackRecovery(
                    state_path=self.root / "state.json",
                    log_path=self.root / "recovery.log",
                    lock_path=self.root / "recovery.lock",
                )
                self.assertFalse(recovery.backup_in_progress())
        finally:
            decoy.terminate()
            decoy.wait(timeout=10)

    def test_backup_skips_alert_when_ingress_stays_down(self):
        recovery = self.recovery(backup_held=True, ingress_healthy=False)
        recovery.backup_skip_alert_after = 3
        for step in range(3):
            self.assertEqual(recovery.run_cycle(now=2_000 + step * 200), "backup_in_progress")
        self.assertEqual(len(recovery.alerts), 1)

    def test_backup_skips_do_not_accumulate_while_ingress_is_healthy(self):
        recovery = self.recovery(backup_held=True, ingress_healthy=True)
        self.assertEqual(recovery.run_cycle(now=2_000), "healthy")
        self.assertEqual(recovery.load_state()["backup_skips"], 0)

    # ------------------------------------------------------ detection details

    def test_vmgr_hang_marker_only_counts_when_recent(self):
        vmgr_log = self.root / "vmgr.log"
        now = int(time.time())
        stamp = time.strftime("%m-%d %H:%M:%S", time.localtime(now - 30))
        vmgr_log.write_text(
            f'vmgr | time="{stamp}" level=warning msg="sampling stacks due to VM hang"\n'
        )
        with patch.object(MODULE, "VMGR_LOG", vmgr_log):
            recovery = MODULE.OrbStackRecovery(state_path=self.root / "s.json")
            self.assertTrue(recovery.vmgr_hang_marker(now))
            self.assertFalse(recovery.vmgr_hang_marker(now + 3_600))

    def test_missing_vmgr_log_is_not_a_hang(self):
        with patch.object(MODULE, "VMGR_LOG", self.root / "absent.log"):
            recovery = MODULE.OrbStackRecovery(state_path=self.root / "s.json")
            self.assertFalse(recovery.vmgr_hang_marker())

    def test_docker_socket_absent_is_down_not_wedged(self):
        with patch.object(MODULE, "DOCKER_SOCK", self.root / "missing.sock"):
            recovery = MODULE.OrbStackRecovery(state_path=self.root / "s.json")
            self.assertEqual(recovery.docker_sock_state(), "down")


if __name__ == "__main__":
    unittest.main()
