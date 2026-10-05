"""Exercise deploy failure gates without Docker, systemd, or database writes."""
from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class DeployTests(unittest.TestCase):
    def test_reconciliation_failure_keeps_timer_stopped_and_rolls_back_image_only(self):
        self._run_deploy(fail_phase="reconcile")

    def test_sql_apply_failure_keeps_timer_stopped_and_skips_reconciliation(self):
        self._run_deploy(fail_phase="apply")

    def test_success_reconciles_before_logging_and_restarts_timer(self):
        self._run_deploy(fail_phase="none")

    def test_writer_role_preflight_failures_do_not_change_release_or_grant_rights(self):
        for failure in ("missing-writer", "same-role", "invalid-writer"):
            with self.subTest(failure=failure):
                self._run_deploy(fail_phase=failure)

    def test_configured_writer_role_gets_scoped_grants(self):
        self._run_deploy(fail_phase="none", writer_role="custom_etl_writer")

    def _run_deploy(self, fail_phase: str, writer_role: str = "etl_writer"):
        git_bash = Path("C:/Program Files/Git/bin/bash.exe")
        bash = str(git_bash) if os.name == "nt" and git_bash.exists() else shutil.which("bash")
        if not bash:
            self.skipTest("Bash is required for deploy shell checks")
        script = Path(__file__).resolve().parents[1] / "deploy/scripts/deploy.sh"
        with tempfile.TemporaryDirectory(dir=script.parents[2]) as temporary:
            base = Path(temporary)
            for directory in ("bin", "data-engineering", "releases", "secrets"):
                (base / directory).mkdir()
            (base / "data-engineering/compose.yaml").write_text("services: {}\n")
            original = "ETL_IMAGE=previous\nWAREHOUSE_ANALYTICS_ROLE=rm_analytics_reader\n"
            if fail_phase == "same-role":
                writer_role = "rm_analytics_reader"
            elif fail_phase == "invalid-writer":
                writer_role = "bad-role"
            if writer_role != "etl_writer":
                original += "WAREHOUSE_WRITER_ROLE=" + writer_role + "\n"
            release = base / "releases/data-engineering.env"
            release.write_text(original)
            (base / "secrets/data-engineering.env").write_text("placeholder\n")
            mocks = {
                "systemctl": """#!/bin/sh
printf 'systemctl %s\n' "$*" >> "$MOCK_LOG"
case "$*" in
  'is-active --quiet data-engineering.timer') exit 0 ;;
  'is-active --quiet data-engineering.service') exit 3 ;;
esac
exit 0
""",
                "docker": """#!/bin/sh
printf 'docker %s\n' "$*" >> "$MOCK_LOG"
case "$*" in
  *'/app/warehouse/002_transform.sql') [ "$FAIL_PHASE" != apply ]; exit $? ;;
  *'run --rm warehouse-db-etl reconcile') [ "$FAIL_PHASE" != reconcile ]; exit $? ;;
  *'pg_dump -Fc'*) printf 'fake backup archive'; exit 0 ;;
  *'pg_restore'*) cat >/dev/null; exit 0 ;;
  *'current_database()'*) printf 'warehouse_db\n'; exit 0 ;;
  *'-v writer_role='*) cat >> "$MOCK_LOG"; exit 0 ;;
  *'SELECT EXISTS'*)
    if [ "$FAIL_PHASE" = missing-writer ]; then
      case "$*" in *"rolname = 'etl_writer'"*) printf 'f\n'; exit 0 ;; esac
    fi
    printf 't\n'; exit 0 ;;
  *'SELECT status'*) printf 'SUCCEEDED\n'; exit 0 ;;
esac
exit 0
""",
            }
            for name, content in mocks.items():
                mock = base / "bin" / name
                mock.write_text(content, newline="\n")
                mock.chmod(0o755)
            env = os.environ.copy()
            shell_base = "/" + base.drive[0].lower() + base.as_posix()[2:] if os.name == "nt" else base.as_posix()
            env.update(CFMANAGER_DIR=base.name, MOCK_LOG=shell_base + "/calls.log",
                       MOCK_BIN=shell_base + "/bin",
                       FAIL_PHASE=fail_phase)
            wrappers = ('export PATH="/usr/bin:/bin"; docker() { "$MOCK_BIN/docker" "$@"; }; '
                        'systemctl() { "$MOCK_BIN/systemctl" "$@"; }; '
                        'id() { printf "0\\n"; }; source "$1" "${@:2}"')
            result = subprocess.run([bash, "-c", wrappers,
                                     "mock-deploy", script.as_posix(), "sha256:" + "a" * 64, "full"],
                                    env=env, cwd=base.parent, capture_output=True, text=True,
                                    encoding="utf-8", errors="replace")
            calls = (base / "calls.log").read_text()
            if fail_phase in ("missing-writer", "same-role", "invalid-writer"):
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(release.read_text(), original)
                self.assertNotIn("pg_dump", calls)
                self.assertNotIn("GRANT", calls)
                self.assertNotIn("systemctl start data-engineering.timer", calls)
                return
            self.assertIn("pg_restore --list", calls, result.stdout + result.stderr)
            self.assertIn("pg_restore --file=/dev/null", calls)
            if fail_phase == "apply":
                self.assertNotIn("warehouse-db-etl reconcile", calls)
            else:
                self.assertIn("warehouse-db-etl reconcile", calls)
                self.assertIn("-v writer_role='" + writer_role + "'", calls)
                self.assertIn("GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA etl, stg, dw, mart", calls)
                self.assertIn('TO :"writer_role"', calls)
                self.assertNotIn('GRANT ALL PRIVILEGES', calls)
            if fail_phase != "none":
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertNotIn("systemctl start data-engineering.timer", calls)
                self.assertEqual(release.read_text(), original)
                self.assertFalse((base / "releases/deployments.log").exists())
                self.assertIn("does not restore warehouse data", result.stderr)
            else:
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("systemctl start data-engineering.timer", calls)
                self.assertIn("reconciliation=passed", (base / "releases/deployments.log").read_text())


if __name__ == "__main__":
    unittest.main()
