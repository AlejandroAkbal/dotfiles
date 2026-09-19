#!/usr/bin/env python3
import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, call, patch

MODULE_PATH = Path(__file__).resolve().parents[1] / "jump-desktop-recovery.py"
SPEC = importlib.util.spec_from_file_location("jump_desktop_recovery", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class TestJumpDesktopRecovery(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.patch_log_dir = patch.object(
            MODULE, "LOG_DIR", Path(self.tmpdir.name) / "log"
        )
        self.patch_log_file = patch.object(
            MODULE, "LOG_FILE", Path(self.tmpdir.name) / "log/test.log"
        )
        self.patch_print = patch("builtins.print")
        self.patch_log_dir.start()
        self.patch_log_file.start()
        self.patch_print.start()

    def tearDown(self):
        self.patch_print.stop()
        self.patch_log_file.stop()
        self.patch_log_dir.stop()
        self.tmpdir.cleanup()

    @patch.object(MODULE, "is_agent_loaded")
    def test_already_loaded_is_healthy_noop(self, mock_is_loaded):
        mock_is_loaded.return_value = True
        with patch.object(MODULE, "bootstrap_agent") as mock_bootstrap:
            res = MODULE.run_cycle()
            self.assertEqual(res, "healthy")
            mock_bootstrap.assert_not_called()

    @patch.object(MODULE, "is_agent_loaded")
    @patch.object(MODULE, "bootstrap_agent")
    def test_missing_agent_triggers_bootstrap_and_recovers(
        self, mock_bootstrap, mock_is_loaded
    ):
        mock_is_loaded.side_effect = [False, True]
        mock_bootstrap.return_value = True

        res = MODULE.run_cycle()
        self.assertEqual(res, "recovered")
        mock_bootstrap.assert_called_once()

    @patch.object(MODULE, "is_agent_loaded")
    @patch.object(MODULE, "bootstrap_agent")
    def test_missing_agent_bootstrap_failure(self, mock_bootstrap, mock_is_loaded):
        mock_is_loaded.return_value = False
        mock_bootstrap.return_value = False

        res = MODULE.run_cycle()
        self.assertEqual(res, "bootstrap_failed")
        mock_bootstrap.assert_called_once()

    @patch("subprocess.run")
    def test_is_agent_loaded_invokes_launchctl_print(self, mock_subproc):
        mock_subproc.return_value = MagicMock(returncode=0)
        self.assertTrue(MODULE.is_agent_loaded("gui/501"))
        mock_subproc.assert_called_once_with(
            ["/bin/launchctl", "print", "gui/501/com.p5sys.jump.connect.agent"],
            capture_output=True,
            text=True,
            timeout=5,
        )

    @patch("subprocess.run")
    @patch("pathlib.Path.exists")
    def test_bootstrap_agent_invokes_launchctl_bootstrap_and_kickstart(
        self, mock_exists, mock_subproc
    ):
        mock_exists.return_value = True
        mock_subproc.return_value = MagicMock(returncode=0)
        self.assertTrue(MODULE.bootstrap_agent("gui/501"))
        self.assertEqual(mock_subproc.call_count, 2)
        mock_subproc.assert_has_calls([
            call(
                [
                    "/bin/launchctl",
                    "bootstrap",
                    "gui/501",
                    "/Library/LaunchAgents/com.p5sys.jump.connect.agent.plist",
                ],
                capture_output=True,
                text=True,
                timeout=10,
            ),
            call(
                [
                    "/bin/launchctl",
                    "kickstart",
                    "gui/501/com.p5sys.jump.connect.agent",
                ],
                capture_output=True,
                text=True,
                timeout=5,
            ),
        ])

    @patch.object(MODULE, "is_agent_loaded")
    @patch("subprocess.run")
    @patch("pathlib.Path.exists")
    def test_bootstrap_recovers_on_launchd_error_if_service_loaded(
        self, mock_exists, mock_subproc, mock_is_loaded
    ):
        mock_exists.return_value = True
        mock_subproc.return_value = MagicMock(
            returncode=5, stderr="Bootstrap failed: 5: Input/output error"
        )
        mock_is_loaded.return_value = True

        self.assertTrue(MODULE.bootstrap_agent("gui/501"))
        mock_is_loaded.assert_called_once_with("gui/501")


if __name__ == "__main__":
    unittest.main()
