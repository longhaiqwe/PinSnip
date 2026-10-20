#!/usr/bin/env python3
"""Install an upgrade only when it preserves the installed Developer ID identity."""
import argparse
import plistlib
import re
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2]
BUNDLE_ID = "com.longhai.pinsnip"
TEAM_ID = "5RFJK73RSL"
DEVELOPER_REQUIREMENT = (
    f'identifier "{BUNDLE_ID}" and anchor apple generic '
    'and certificate 1[field.1.2.840.113635.100.6.2.6] exists '
    'and certificate leaf[field.1.2.840.113635.100.6.1.13] exists '
    f'and certificate leaf[subject.OU] = "{TEAM_ID}"'
)


class InstallError(RuntimeError):
    pass


def run(*args):
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode:
        raise InstallError(f"命令失败：{args[0]}\n{result.stderr.strip()}")
    return result.stdout + result.stderr


def validate_app(app):
    if app.is_symlink() or not app.is_dir() or app.suffix != ".app":
        raise InstallError(f"应用不存在或不是独立的 .app 目录：{app}")
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info.get("CFBundleIdentifier") != BUNDLE_ID or info.get("CFBundleExecutable") != "PinSnip":
        raise InstallError(f"应用标识不正确：{app}")
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", str(app))
    # The root requirement must not be applied to nested components with different IDs.
    run("/usr/bin/codesign", "--verify", "--strict", "-R", "=" + DEVELOPER_REQUIREMENT, str(app))
    details = run("/usr/bin/codesign", "-dvvv", str(app))
    if not re.search(r"^Timestamp=.+", details, re.MULTILINE) or not re.search(r"flags=.*\bruntime\b", details):
        raise InstallError(f"必须是带时间戳及 Hardened Runtime 的正式构建：{app}")
    if (app / "Contents/MacOS/PinSnip.debug.dylib").exists():
        raise InstallError("禁止安装 Debug 构建。")
    # Check entitlements on the root and every nested executable, including helpers.
    macho_magic = {b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe",
                   b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"}
    for item in app.rglob("*"):
        if item.is_symlink() or not item.is_file():
            continue
        with item.open("rb") as stream:
            if stream.read(4) not in macho_magic:
                continue
        entitlements = run("/usr/bin/codesign", "-d", "--entitlements", ":-", str(item))
        if "com.apple.security.get-task-allow" in entitlements:
            raise InstallError(f"禁止安装包含调试权限的构建：{item}")


def designated_requirement(app):
    output = run("/usr/bin/codesign", "-d", "-r-", str(app))
    rules = [line.removeprefix("designated => ").strip()
             for line in output.splitlines() if line.startswith("designated => ")]
    if len(rules) != 1 or not rules[0]:
        raise InstallError(f"无法读取旧版身份规则，禁止替换：{app}")
    return rules[0]


def validate_upgrade(source, installed, expected_requirement=None):
    validate_app(installed)
    old_requirement = designated_requirement(installed)
    if expected_requirement is not None and old_requirement != expected_requirement:
        raise InstallError("准备安装期间旧版身份发生变化，禁止替换。")
    validate_app(source)
    run("/usr/bin/codesign", "--verify", "--strict", "-R", "=" + old_requirement, str(source))
    # Mutual compatibility also prevents replacing a stable DR with a narrower rule
    # that would work this time but require fresh permission on the following update.
    new_requirement = designated_requirement(source)
    run("/usr/bin/codesign", "--verify", "--strict", "-R", "=" + new_requirement, str(installed))
    return old_requirement


def is_running(app):
    executable = app / "Contents/MacOS/PinSnip"
    result = subprocess.run(["/usr/bin/pgrep", "-f", "^" + re.escape(str(executable)) + "$"],
                            capture_output=True, text=True)
    if result.returncode not in (0, 1):
        raise InstallError("无法确认应用运行状态，停止替换。")
    return result.returncode == 0


def quit_app(app):
    if not is_running(app):
        return
    run("/usr/bin/osascript", "-e", "on run argv", "-e",
        "tell application (item 1 of argv) to quit", "-e", "end run", str(app))
    for _ in range(40):
        if not is_running(app):
            return
        time.sleep(0.25)
    raise InstallError("旧版未退出，已取消替换。")


def install(source, installed, check_only=False):
    source = source.absolute()
    installed = installed.absolute()
    if source.resolve() == installed.resolve() or source.resolve() in installed.resolve().parents or installed.resolve() in source.resolve().parents:
        raise InstallError("安装来源与目标不能相同或相互嵌套。")
    old_requirement = validate_upgrade(source, installed)
    if check_only:
        print("签名检查通过：正式签名有效，新旧身份兼容。未退出或替换应用。")
        return

    # Stage on the destination filesystem so renames and rollback remain local.
    workspace = Path(tempfile.mkdtemp(prefix=".PinSnip-upgrade-", dir=installed.parent))
    staged = workspace / "New.app"
    backup = workspace / "Previous.app"
    replaced = False
    was_running = False
    try:
        run("/usr/bin/ditto", str(source), str(staged))
        validate_upgrade(staged, installed, old_requirement)
        was_running = is_running(installed)
        quit_app(installed)
        # All signature checks above happen before the installed app is moved.
        installed.rename(backup)
        try:
            staged.rename(installed)
            validate_upgrade(installed, backup, old_requirement)
        except BaseException:
            if installed.exists():
                installed.rename(staged)
            backup.rename(installed)
            raise
        replaced = True
        print(f"已安装正式签名新版；旧版备份：{backup}")
        run("/usr/bin/open", str(installed))
        for _ in range(40):
            if is_running(installed):
                print(f"新版已启动：{installed}")
                return
            time.sleep(0.25)
        raise InstallError(f"安装成功但未确认启动，请检查应用。旧版备份：{backup}")
    except BaseException:
        if not replaced and not backup.exists() and was_running and installed.exists():
            try:
                run("/usr/bin/open", str(installed))
            except InstallError as error:
                print(f"旧版已保留，但未能重新启动：{error}")
        raise
    finally:
        # Keep the old app after success or any unsuccessful rollback.
        if not replaced and not backup.exists():
            shutil.rmtree(workspace)


def main():
    parser = argparse.ArgumentParser(description="仅安装与旧版身份兼容的 PinSnip 正式签名构建。")
    parser.add_argument("--app", type=Path, default=PROJECT / "build/Release/PinSnip.app")
    parser.add_argument("--destination", type=Path, default=Path("/Applications/PinSnip.app"))
    parser.add_argument("--check", action="store_true", help="只校验，不退出、复制、替换或启动应用")
    args = parser.parse_args()
    try:
        install(args.app, args.destination, args.check)
    except (InstallError, OSError, ValueError) as error:
        parser.exit(1, f"安装已停止：{error}\n")


if __name__ == "__main__":
    main()
