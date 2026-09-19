#!/usr/bin/env python3
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

MODULE_PATH = Path(__file__).resolve().parents[1] / "orbstack-recovery.py"
SPEC = importlib.util.spec_from_file_location("orbstack_recovery", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FakeRecovery(MODULE.OrbStackRecovery):
    def __init__(self, root: Path):
        super().__init__(
            state_path=root / "state.json",
            log_path=root / "recovery.log",
            lock_path=root / "recovery.lock",
        )
        self.actions = []
        self.network_ok = True
        self.orb_states = [True]
        self.current_vm_state = "running"
        self.ingress_healthy = True

    def host_network_ok(self):
        return self.network_ok

    def orb_running(self):
        if len(self.orb_states) > 1:
            return self.orb_states.pop(0)
        return self.orb_states[0]

    def vm_state(self):
        return self.current_vm_state

    def ingress_ok(self):
        return self.ingress_healthy

    def launch_orbstack(self):
        self.actions.append("launch_orbstack")
        return True

    def start_vm(self):
        self.actions.append("start_vm")
        return True

    def restart_vm(self):
        self.actions.append("restart_vm")
        return True


class OrbStackRecoveryTests(unittest.TestCase):
    def test_healthy_runtime_is_noop_and_clears_failures(self):
        with tempfile.TemporaryDirectory() as tmp:
            recovery = FakeRecovery(Path(tmp))
            recovery.save_state({"ingress_failures": 1, "last_action": 0})
            result = recovery.run_cycle(now=2_000)
            self.assertEqual(result, "healthy")
            self.assertEqual(recovery.actions, [])
            self.assertEqual(recovery.load_state()["ingress_failures"], 0)

    def test_second_ingress_failure_restarts_vm(self):
        with tempfile.TemporaryDirectory() as tmp:
            recovery = FakeRecovery(Path(tmp))
            recovery.ingress_healthy = False
            self.assertEqual(recovery.run_cycle(now=2_000), "ingress_failure")
            self.assertEqual(recovery.actions, [])
            self.assertEqual(recovery.run_cycle(now=2_301), "vm_restarted")
            self.assertEqual(recovery.actions, ["restart_vm"])

    def test_stopped_vm_is_started(self):
        with tempfile.TemporaryDirectory() as tmp:
            recovery = FakeRecovery(Path(tmp))
            recovery.current_vm_state = "stopped"
            self.assertEqual(recovery.run_cycle(now=2_000), "vm_started")
            self.assertEqual(recovery.actions, ["start_vm"])

    def test_starting_vm_is_left_alone(self):
        with tempfile.TemporaryDirectory() as tmp:
            recovery = FakeRecovery(Path(tmp))
            recovery.current_vm_state = "starting"
            self.assertEqual(recovery.run_cycle(now=2_000), "vm_starting")
            self.assertEqual(recovery.actions, [])

    def test_orbstack_down_launches_app_without_host_reboot(self):
        with tempfile.TemporaryDirectory() as tmp:
            recovery = FakeRecovery(Path(tmp))
            recovery.orb_states = [False]
            self.assertEqual(recovery.run_cycle(now=2_000), "orbstack_started")
            self.assertEqual(recovery.actions, ["launch_orbstack"])

    def test_unhealthy_host_network_never_touches_orbstack(self):
        with tempfile.TemporaryDirectory() as tmp:
            recovery = FakeRecovery(Path(tmp))
            recovery.network_ok = False
            recovery.orb_states = [False]
            self.assertEqual(recovery.run_cycle(now=2_000), "network_unhealthy")
            self.assertEqual(recovery.actions, [])

    def test_cooldown_blocks_repeat_actions(self):
        with tempfile.TemporaryDirectory() as tmp:
            recovery = FakeRecovery(Path(tmp))
            recovery.current_vm_state = "stopped"
            recovery.save_state({"ingress_failures": 0, "last_action": 1_900})
            self.assertEqual(recovery.run_cycle(now=2_000), "cooldown")
            self.assertEqual(recovery.actions, [])


if __name__ == "__main__":
    unittest.main()
