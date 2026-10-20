#!/usr/bin/env python3
"""Exercise the install gate and replacement transaction without touching /Applications."""
import importlib.util
import json
import plistlib
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("installer", Path(__file__).resolve().parents[1] / "lib/install-release.py")
installer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(installer)


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.old = self.root / "installed/PinSnip.app"
        self.new = self.root / "build/PinSnip.app"
        self.make_app(self.old, "old")
        self.make_app(self.new, "new")
        self.events = []
        self.running = True
        self.corrupt_copy = False
        self.corrupt_installed = False
        self.patches = [patch.object(installer, "run", self.fake_run),
                        patch.object(installer, "is_running", lambda app: self.running)]
        for item in self.patches:
            item.start()
            self.addCleanup(item.stop)
        self.addCleanup(self.temp.cleanup)

    def make_app(self, app, version):
        (app / "Contents/MacOS").mkdir(parents=True)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": installer.BUNDLE_ID, "CFBundleExecutable": "PinSnip"}))
        (app / "Contents/MacOS/PinSnip").write_bytes(b"\xcf\xfa\xed\xfe" + version.encode())
        (app / "version").write_text(version)
        (app / "signature.json").write_text(json.dumps({"formal": True, "valid": True,
            "rule": "stable-rule", "accepts": ["stable-rule"], "timestamp": True,
            "runtime": True, "debug": False}))

    def change(self, app, **values):
        data = json.loads((app / "signature.json").read_text())
        data.update(values)
        (app / "signature.json").write_text(json.dumps(data))

    def fake_run(self, *args):
        self.events.append(args)
        tool = Path(args[0]).name
        app = Path(args[-1])
        if tool == "codesign":
            while app.suffix != ".app":
                app = app.parent
            data = json.loads((app / "signature.json").read_text())
            if "--verify" in args:
                if not data["valid"] or (self.corrupt_installed and app == self.old and (app / "version").read_text() == "new"):
                    raise installer.InstallError("签名损坏")
                if "-R" in args:
                    self.assertNotIn("--deep", args)
                    rule = args[args.index("-R") + 1]
                    self.assertTrue(rule.startswith("="))
                    allowed = data["formal"] if rule[1:] == installer.DEVELOPER_REQUIREMENT else rule[1:] in data["accepts"]
                    if not allowed:
                        raise installer.InstallError("身份不兼容")
                return ""
            if "-r-" in args:
                return f'Executable={app}\ndesignated => {data["rule"]}\n' if data["rule"] else ""
            if "--entitlements" in args:
                return "com.apple.security.get-task-allow" if data["debug"] else ""
            return ("Timestamp=Oct 17, 2026\n" if data["timestamp"] else "") + ("flags=0x10000(runtime)" if data["runtime"] else "flags=0x0")
        if tool == "ditto":
            shutil.copytree(args[1], args[2], symlinks=True)
            if self.corrupt_copy:
                self.change(Path(args[2]), valid=False)
        elif tool == "osascript":
            self.running = False
        elif tool == "open":
            self.running = True
        else:
            self.fail(f"Unexpected command: {args}")
        return ""

    def assert_no_replacement(self):
        self.assertEqual((self.old / "version").read_text(), "old")
        self.assertTrue(self.running)
        self.assertFalse(any(Path(call[0]).name in ("osascript", "open") for call in self.events))

    def test_rejects_non_developer_id_before_copy_or_quit(self):
        self.change(self.new, formal=False)
        with self.assertRaises(installer.InstallError):
            installer.install(self.new, self.old)
        self.assert_no_replacement()
        self.assertFalse(any(Path(call[0]).name == "ditto" for call in self.events))

    def test_rejects_incompatible_old_requirement(self):
        self.change(self.new, accepts=["different-rule"])
        with self.assertRaises(installer.InstallError):
            installer.install(self.new, self.old)
        self.assert_no_replacement()

    def test_rejects_new_rule_that_would_exclude_old_version(self):
        self.change(self.new, rule="new-hash-only-rule")
        with self.assertRaises(installer.InstallError):
            installer.install(self.new, self.old)
        self.assert_no_replacement()

    def test_rejects_unreadable_old_requirement(self):
        self.change(self.old, rule="")
        with self.assertRaises(installer.InstallError):
            installer.install(self.new, self.old)
        self.assert_no_replacement()

    def test_rejects_corrupt_signature(self):
        self.change(self.new, valid=False)
        with self.assertRaises(installer.InstallError):
            installer.install(self.new, self.old)
        self.assert_no_replacement()

    def test_rejects_debug_entitlements(self):
        self.change(self.new, debug=True)
        with self.assertRaises(installer.InstallError):
            installer.install(self.new, self.old)
        self.assert_no_replacement()

    def test_rejects_debug_binary(self):
        (self.new / "Contents/MacOS/PinSnip.debug.dylib").touch()
        with self.assertRaises(installer.InstallError):
            installer.install(self.new, self.old)
        self.assert_no_replacement()

    def test_rejects_wrong_bundle_id(self):
        (self.new / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "wrong"}))
        with self.assertRaises(installer.InstallError):
            installer.install(self.new, self.old)
        self.assert_no_replacement()

    def test_rejects_missing_timestamp_and_runtime(self):
        for field in ("timestamp", "runtime"):
            with self.subTest(field=field):
                self.change(self.new, timestamp=True, runtime=True)
                self.change(self.new, **{field: False})
                with self.assertRaises(installer.InstallError):
                    installer.install(self.new, self.old)
                self.assert_no_replacement()

    def test_revalidates_staged_copy_before_quitting(self):
        self.corrupt_copy = True
        with self.assertRaises(installer.InstallError):
            installer.install(self.new, self.old)
        self.assert_no_replacement()
        self.assertEqual(list(self.old.parent.glob(".PinSnip-upgrade-*")), [])

    def test_restores_backup_if_installed_validation_fails(self):
        self.corrupt_installed = True
        with self.assertRaises(installer.InstallError):
            installer.install(self.new, self.old)
        self.assertEqual((self.old / "version").read_text(), "old")
        self.assertTrue(self.running)

    def test_missing_or_symlink_app_never_quits_old_app(self):
        link = self.new.parent / "Link.app"
        link.symlink_to(self.new, target_is_directory=True)
        for source in (link, self.new.parent / "Missing.app"):
            with self.subTest(source=source):
                with self.assertRaises(installer.InstallError):
                    installer.install(source, self.old)
                self.assert_no_replacement()

    def test_rejects_nested_helper_debug_entitlements(self):
        helper = self.new / "Contents/Frameworks/Helper.app"
        self.make_app(helper, "helper")
        self.change(helper, debug=True)
        with self.assertRaises(installer.InstallError):
            installer.install(self.new, self.old)
        self.assert_no_replacement()

    def test_check_only_does_not_mutate_or_quit(self):
        installer.install(self.new, self.old, check_only=True)
        self.assert_no_replacement()
        self.assertFalse(any(Path(call[0]).name == "ditto" for call in self.events))
        self.assertEqual(list(self.old.parent.iterdir()), [self.old])

    def test_success_installs_staged_app_keeps_backup_and_launches(self):
        installer.install(self.new, self.old)
        self.assertEqual((self.old / "version").read_text(), "new")
        backups = list(self.old.parent.glob(".PinSnip-upgrade-*/Previous.app/version"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), "old")
        self.assertTrue(self.running)
        self.assertEqual(self.events[-1], ("/usr/bin/open", str(self.old)))


if __name__ == "__main__":
    unittest.main()
