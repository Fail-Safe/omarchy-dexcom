#!/usr/bin/env python3
"""Exercise the production singleton in Quickshell without credentials or network."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("qs"), "Quickshell is not installed")
class ServiceLifecycleTests(unittest.TestCase):
    def test_shared_polling_and_last_widget_teardown(self):
        qml = '''import QtQuick
import Quickshell
import Quickshell.Io
import PLUGIN as Dexcom
ShellRoot {
    id: root
    readonly property var service: Dexcom.Service
    property var first: null
    property var second: null
    property int stage: 0
    property int ticks: 0
    property string lastStamp: ""
    FileView { id: counts; path: COUNTS; blockAllReads: true }
    Component {
        id: consumer
        QtObject {
            readonly property var service: Dexcom.Service
            Component.onCompleted: service.attachWidget()
            Component.onDestruction: if (service) service.detachWidget()
        }
    }
    function verify(condition, message) {
        if (!condition) throw new Error("stage " + stage + ": " + message)
    }
    function advance() { stage++; ticks = 0 }
    function started() {
        counts.reload()
        return JSON.parse(counts.text()).started
    }
    function payloadReady(number) {
        return !service.checking && service.stampedAt === "fixture-" + number
    }
    Component.onCompleted: {
        service.settings = {glucoseUnit: "mmol/L", refreshIntervalSec: 600}
        service.refresh()
        service.setPaused(true)
        service.setPaused(false)
    }
    Timer {
        interval: 50; repeat: true; running: true
        onTriggered: {
            root.ticks++
            try {
                verify(ticks < 100, "transition timed out")
                switch (stage) {
                case 0:
                    if (ticks < 6) return
                    verify(started() === 0, "fetch without consumers")
                    first = consumer.createObject(root)
                    second = consumer.createObject(root)
                    verify(first.service === second.service, "backend not shared")
                    verify(service.attachedWidgets === 2, "two consumers not attached")
                    advance(); break
                case 1:
                    if (!payloadReady(1)) return
                    verify(started() === 1, "duplicate initial fetch")
                    verify(first.service.badgeText === "5.0 →", "badge/unit/trend mismatch")
                    verify(second.service.history.length === 2, "second consumer lacks history")
                    verify(first.service.history[0].mgdl === 95
                        && first.service.history[1].mgdl === 90, "history payload mismatch")
                    first.service.setPaused(true)
                    verify(second.service.paused, "pause not shared")
                    second.service.setChartHours(12)
                    verify(first.service.chartHours === 12, "chart range not shared")
                    first.destroy(); first = null
                    advance(); break
                case 2:
                    if (service.attachedWidgets !== 1) return
                    second.service.setPaused(false)
                    second.service.refresh()
                    advance(); break
                case 3:
                    if (!payloadReady(2)) return
                    verify(started() === 2, "remaining consumer cannot refresh exactly once")
                    second.destroy(); second = null
                    advance(); break
                case 4:
                    if (service.attachedWidgets !== 0) return
                    service.refresh()
                    advance(); break
                case 5:
                    if (ticks < 6) return
                    verify(started() === 2, "fetch after last consumer detached")
                    service.setPaused(true)
                    first = consumer.createObject(root)
                    advance(); break
                case 6:
                    if (ticks < 6) return
                    verify(started() === 2 && service.paused, "paused attachment fetched")
                    service.setPaused(false)
                    advance(); break
                case 7:
                    if (!payloadReady(3)) return
                    verify(started() === 3, "resume did not fetch exactly once")
                    lastStamp = service.stampedAt
                    first.service.refresh()
                    advance(); break
                case 8:
                    if (started() !== 4) return
                    verify(service.checking, "delayed fetch not in flight")
                    first.destroy(); first = null
                    advance(); break
                case 9:
                    if (service.attachedWidgets !== 0 || service.checking || ticks < 25) return
                    verify(started() === 4, "cancellation scheduled an unowned fetch")
                    verify(service.stampedAt === lastStamp, "canceled result was applied")
                    verify(!service.paused, "detach changed user pause state")
                    first = consumer.createObject(root)
                    advance(); break
                case 10:
                    if (!payloadReady(5)) return
                    verify(started() === 5, "reattachment failed to restart polling")
                    verify(first.service.badgeText === "5.0 →", "reattachment lost payload")
                    first.destroy(); first = null
                    advance(); break
                case 11:
                    if (service.attachedWidgets !== 0 || ticks < 6) return
                    verify(started() === 5, "unexpected final fetch")
                    console.log("DEXCOM_LIFECYCLE_PASSED")
                    stop(); Qt.quit()
                }
            } catch (error) {
                console.error("DEXCOM_LIFECYCLE_FAILED: " + error)
                stop(); Qt.quit()
            }
        }
    }
}
'''
        with tempfile.TemporaryDirectory(prefix="dexcom-qml-") as tmp:
            directory = Path(tmp)
            counts = directory / "counts.json"
            counts.write_text(json.dumps({"started": 0, "finished": 0}))
            bin_dir = directory / "bin"
            bin_dir.mkdir()
            helper = bin_dir / "python3"
            helper.write_text("#!" + sys.executable + "\n" + '''import json, os, time
from pathlib import Path
path = Path(os.environ["DEXCOM_TEST_COUNTS"])
counts = json.loads(path.read_text())
counts["started"] += 1
invocation = counts["started"]
def save():
    pending = path.with_suffix(".tmp")
    pending.write_text(json.dumps(counts))
    pending.replace(path)
save()
time.sleep(1 if invocation == 4 else 0.2)
now = int(time.time())
counts["finished"] += 1
save()
print(json.dumps({"ok": True, "mgdl": 90, "trend": "Flat", "ageSec": 0,
    "stampedAt": "fixture-" + str(invocation), "history": [
        {"epochSec": now - 300, "mgdl": 95}, {"epochSec": now, "mgdl": 90}]}))
''')
            helper.chmod(0o700)
            config = directory / "shell.qml"
            config.write_text(qml.replace("PLUGIN", json.dumps(ROOT.as_uri()))
                              .replace("COUNTS", json.dumps(str(counts))))
            env = {**os.environ, "QT_QPA_PLATFORM": "offscreen",
                   "QT_QUICK_BACKEND": "software", "QT_QPA_PLATFORMTHEME": "",
                   "XDG_RUNTIME_DIR": tmp, "XDG_CACHE_HOME": tmp,
                   "XDG_STATE_HOME": tmp, "DEXCOM_TEST_COUNTS": str(counts),
                   "PATH": str(bin_dir) + os.pathsep + os.environ.get("PATH", "")}
            try:
                result = subprocess.run([shutil.which("qs"), "-p", str(config)],
                                        capture_output=True, text=True, timeout=30, env=env)
            except subprocess.TimeoutExpired as exc:
                self.fail(f"Quickshell timed out: {exc.stdout!r} {exc.stderr!r}")
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("DEXCOM_LIFECYCLE_PASSED", output)
            self.assertNotIn("DEXCOM_LIFECYCLE_FAILED", output)
            self.assertEqual(json.loads(counts.read_text()), {"started": 5, "finished": 4})


if __name__ == "__main__":
    unittest.main()
