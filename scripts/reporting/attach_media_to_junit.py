#!/usr/bin/env python3
"""Attach a media file (video/screenshot/log) to a JUnit XML report for the
Bitrise Tests tab, following the "naming attachments after test cases"
convention: <classname>__<name>[__run<k>]__<label>.<ext>

https://docs.bitrise.io/en/bitrise-ci/testing/test-reports/test-attachments/naming-attachments-after-test-cases

Two modes:

  add-recording-testcase
    For a SUITE-level recording (one video covering the whole run, e.g. a
    host-side `adb shell screenrecord` wrapped around an entire instrumented
    test run). Adds a synthetic passing <testcase> to the first <testsuite>
    in the XML (skipped if a testcase with that exact classname+name already
    exists, so re-running this script is idempotent) and copies the media
    file into --dest-dir using the naming convention so it attaches to that
    testcase.

    Respects $RECORD_VIDEO: with "failures", the recording is only kept (and
    the synthetic testcase only added) if the suite had at least one failure
    or error; with "off" this script is a no-op; "all" always keeps it.

  rename
    Copies/renames a media file into --dest-dir using the naming convention
    for an EXISTING testcase (classname+name already present in the XML),
    without modifying the XML. Used where the test framework already reports
    a real per-test-case JUnit entry we can attach to directly.

This never raises on recoverable problems -- attachment failures must not
fail the build. It prints a warning and exits 0 instead.
"""
import argparse
import os
import re
import shutil
import sys
import xml.etree.ElementTree as ET
from typing import Optional

INVALID_CHARS = re.compile(r'["*/:<>?\\|]')


def clean(value: str) -> str:
    """Bitrise's required clean function: replace invalid filename chars."""
    return INVALID_CHARS.sub("_", value)


def attachment_filename(classname: str, name: str, label: str, ext: str, run: Optional[int] = None) -> str:
    run_part = f"__run{run}" if run and run > 1 else ""
    return f"{clean(classname)}__{clean(name)}{run_part}__{label}{ext}"


def record_video_mode() -> str:
    return os.environ.get("RECORD_VIDEO", "failures").strip().lower() or "failures"


def suite_has_failures(testsuites_root: ET.Element) -> bool:
    for testsuite in testsuites_root.iter("testsuite"):
        for attr in ("failures", "errors"):
            try:
                if int(testsuite.get(attr, "0") or "0") > 0:
                    return True
            except ValueError:
                pass
        for testcase in testsuite.findall("testcase"):
            if testcase.find("failure") is not None or testcase.find("error") is not None:
                return True
    return False


def cmd_add_recording_testcase(args: argparse.Namespace) -> int:
    # --always (used for cheap artifacts like screenshots, where the goal is
    # "attach as many as possible") skips the $RECORD_VIDEO gating entirely --
    # that gating exists to avoid uploading a video from every passing run,
    # not to limit screenshots.
    mode = "all" if args.always else record_video_mode()
    if mode == "off":
        print("[attach] RECORD_VIDEO=off, skipping recording attachment.")
        return 0

    if not os.path.isfile(args.junit_xml):
        print(f"[attach] WARN: JUnit XML not found at {args.junit_xml}, skipping.")
        return 0
    if not os.path.isfile(args.media):
        print(f"[attach] WARN: media file not found at {args.media}, skipping.")
        return 0

    try:
        tree = ET.parse(args.junit_xml)
        root = tree.getroot()
        testsuites = [root] if root.tag == "testsuite" else list(root.iter("testsuite"))
        if not testsuites:
            print("[attach] WARN: no <testsuite> found in JUnit XML, skipping.")
            return 0

        if mode == "failures" and not suite_has_failures(root):
            print("[attach] RECORD_VIDEO=failures and the suite passed, not attaching the recording.")
            return 0

        target_suite = testsuites[0]
        existing = next(
            (
                tc
                for tc in target_suite.findall("testcase")
                if tc.get("classname") == args.classname and tc.get("name") == args.name
            ),
            None,
        )
        if existing is None:
            testcase = ET.SubElement(
                target_suite,
                "testcase",
                {"classname": args.classname, "name": args.name, "time": "0"},
            )
            system_out = ET.SubElement(testcase, "system-out")
            system_out.text = (
                "Synthetic test case added to attach the whole suite's screen "
                "recording -- see docs/test-recording-plan.md."
            )
            try:
                total = int(target_suite.get("tests", "0") or "0")
                target_suite.set("tests", str(total + 1))
            except ValueError:
                pass

        os.makedirs(args.dest_dir, exist_ok=True)
        ext = os.path.splitext(args.media)[1] or ".mp4"
        dest_name = attachment_filename(args.classname, args.name, args.label, ext)
        shutil.copyfile(args.media, os.path.join(args.dest_dir, dest_name))

        tree.write(args.junit_xml, encoding="UTF-8", xml_declaration=True)
        print(f"[attach] Attached {args.media} -> {dest_name} for {args.classname}#{args.name}")
        return 0
    except Exception as exc:  # noqa: BLE001 -- attachment issues must never fail the build
        print(f"[attach] WARN: failed to attach recording ({exc}), continuing without it.")
        return 0


def cmd_attach_to_first_failure(args: argparse.Namespace) -> int:
    """Attach a media file (e.g. a golden-test diff image) to whichever
    testcase in the XML failed or errored first, without needing to know its
    classname/name in advance. No-op if nothing failed -- these attachments
    (image diffs that only exist because of a failure) have nothing useful
    to attach to a passing run anyway."""
    if not os.path.isfile(args.junit_xml):
        print(f"[attach] WARN: JUnit XML not found at {args.junit_xml}, skipping.")
        return 0
    if not os.path.isfile(args.media):
        print(f"[attach] WARN: media file not found at {args.media}, skipping.")
        return 0
    try:
        root = ET.parse(args.junit_xml).getroot()
        failing = next(
            (
                tc
                for tc in root.iter("testcase")
                if tc.find("failure") is not None or tc.find("error") is not None
            ),
            None,
        )
        if failing is None:
            print("[attach] No failing testcase found, nothing to attach the diff image to.")
            return 0

        os.makedirs(args.dest_dir, exist_ok=True)
        ext = os.path.splitext(args.media)[1] or ".png"
        dest_name = attachment_filename(failing.get("classname", "unknown"), failing.get("name", "unknown"), args.label, ext)
        shutil.copyfile(args.media, os.path.join(args.dest_dir, dest_name))
        print(f"[attach] Attached {args.media} -> {dest_name} (first failing testcase)")
        return 0
    except Exception as exc:  # noqa: BLE001
        print(f"[attach] WARN: failed to attach to first failure ({exc}), continuing without it.")
        return 0


def cmd_rename(args: argparse.Namespace) -> int:
    mode = record_video_mode()
    if mode == "off":
        print("[attach] RECORD_VIDEO=off, skipping attachment.")
        return 0
    if not os.path.isfile(args.media):
        print(f"[attach] WARN: media file not found at {args.media}, skipping.")
        return 0
    try:
        os.makedirs(args.dest_dir, exist_ok=True)
        ext = os.path.splitext(args.media)[1] or os.path.splitext(args.label)[1] or ""
        label = args.label
        if ext and label.endswith(ext):
            label = label[: -len(ext)]
        dest_name = attachment_filename(args.classname, args.name, label, ext, run=args.run)
        shutil.copyfile(args.media, os.path.join(args.dest_dir, dest_name))
        print(f"[attach] Copied {args.media} -> {dest_name}")
        return 0
    except Exception as exc:  # noqa: BLE001
        print(f"[attach] WARN: failed to rename/copy attachment ({exc}), continuing without it.")
        return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    p1 = sub.add_parser("add-recording-testcase")
    p1.add_argument("--junit-xml", required=True)
    p1.add_argument("--classname", required=True)
    p1.add_argument("--name", default="zz_session_recording")
    p1.add_argument("--media", required=True)
    p1.add_argument("--label", default="video")
    p1.add_argument("--dest-dir", required=True)
    p1.add_argument(
        "--always", action="store_true",
        help="Attach regardless of $RECORD_VIDEO (for cheap artifacts like screenshots).",
    )
    p1.set_defaults(func=cmd_add_recording_testcase)

    p3 = sub.add_parser("attach-to-first-failure")
    p3.add_argument("--junit-xml", required=True)
    p3.add_argument("--media", required=True)
    p3.add_argument("--label", default="diff")
    p3.add_argument("--dest-dir", required=True)
    p3.set_defaults(func=cmd_attach_to_first_failure)

    p2 = sub.add_parser("rename")
    p2.add_argument("--classname", required=True)
    p2.add_argument("--name", required=True)
    p2.add_argument("--media", required=True)
    p2.add_argument("--label", default="video")
    p2.add_argument("--dest-dir", required=True)
    p2.add_argument("--run", type=int, default=1)
    p2.set_defaults(func=cmd_rename)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
