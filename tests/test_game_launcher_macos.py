"""macOS GUI regression: normal opens must rerun a persistent game launcher.

Run in the console user's Aqua session (SSH may invoke open). No Wine, account
state, Desktop artifacts, or force-new-instance flags are used by this test.
"""
import os
from pathlib import Path
import plistlib
import re
import signal
import subprocess
import sys
import tempfile
import time
import unittest
import uuid


@unittest.skipUnless(sys.platform == "darwin", "requires macOS LaunchServices")
class GameLauncherReopenTest(unittest.TestCase):
    def test_normal_reopen_while_first_worker_remains_alive(self):
        repo = Path(__file__).resolve().parents[1]
        cache = Path.home() / ".cache/chardonnay-launcher"
        cache.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="reopen-test-", dir=cache) as temporary:
            root = Path(temporary)
            identifier = "local.chardonnay.reopen-test." + uuid.uuid4().hex
            app = root / "Reopen Probe.app"
            executable = app / "Contents/MacOS/GameLauncher"
            resources = app / "Contents/Resources"
            executable.parent.mkdir(parents=True)
            resources.mkdir()
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
                "CFBundleExecutable": "GameLauncher",
                "CFBundleIdentifier": identifier,
                "CFBundlePackageType": "APPL",
                "LSUIElement": True,
            }))
            subprocess.run(["/usr/bin/clang", "-fobjc-arc", "-Wall", "-Wextra", "-Werror",
                            "-framework", "Cocoa", str(repo / "app/merlot/GameLauncher.m"),
                            "-o", str(executable)], check=True)
            # Keep the first worker alive, just like a cold Steam launch.
            (resources / "launch.command").write_text(
                '#!/bin/bash\nprintf "%s\\n" "$$" >> "$(dirname "$0")/requests"\n'
                'exec /bin/sleep 60\n')
            marker = resources / "requests"
            host_log = cache / identifier / "host.log"
            host_pid = None
            worker_pids = []

            def wait_for_count(count):
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline:
                    lines = marker.read_text().splitlines() if marker.exists() else []
                    if len(lines) >= count:
                        return [int(line) for line in lines]
                    time.sleep(0.1)
                self.fail(f"normal open produced fewer than {count} worker requests")

            try:
                subprocess.run(["/usr/bin/open", str(app)], check=True)
                worker_pids = wait_for_count(1)
                match = re.search(r"host-start pid=(\d+)", host_log.read_text())
                self.assertIsNotNone(match)
                assert match is not None
                host_pid = int(match[1])
                time.sleep(2.2)
                # Crucial regression: no -n. Deliver the reopen event to the same host.
                subprocess.run(["/usr/bin/open", str(app)], check=True)
                worker_pids = wait_for_count(2)
                self.assertEqual(len(worker_pids), 2)
                self.assertNotEqual(worker_pids[0], worker_pids[1])
                self.assertEqual(host_log.read_text().count("host-start pid="), 1)
                for pid in [host_pid, *worker_pids]:
                    os.kill(pid, 0)
                print(f"PASS: two normal opens, one native host, two live workers (host {host_pid})")
            finally:
                if marker.exists():
                    worker_pids = [int(line) for line in marker.read_text().splitlines()]
                if host_pid is None and host_log.exists():
                    match = re.search(r"host-start pid=(\d+)", host_log.read_text())
                    host_pid = int(match[1]) if match else None
                for pid in [*worker_pids, host_pid]:
                    if pid:
                        try:
                            os.kill(pid, signal.SIGTERM)
                        except ProcessLookupError:
                            pass
                # Keep probe logs inside the temporary test scope for cleanup.
                if host_log.exists():
                    host_log.unlink()
                    host_log.parent.rmdir()


if __name__ == "__main__":
    unittest.main()
