"""Pytest fixtures: one Appium session per test, on BrowserStack or a local Appium server."""
import base64
import os
import re

import pytest
from appium import webdriver
from appium.options.android import UiAutomator2Options

TEST_RESULTS_DIR = os.path.join(os.path.dirname(__file__), "test-results")

RECORD_VIDEO = os.environ.get("RECORD_VIDEO", "failures").strip().lower() or "failures"
INVALID_CHARS = re.compile(r'["*/:<>?\\|]')


def clean(value):
    """Bitrise's required clean function for the attachment naming convention."""
    return INVALID_CHARS.sub("_", value)


@pytest.fixture
def driver(request):
    options = UiAutomator2Options()
    options.app = os.environ["BS_APP_URL"]  # bs://... returned by the upload API
    options.platform_version = os.environ.get("BS_OS_VERSION", "14.0")
    options.device_name = os.environ.get("BS_DEVICE", "Google Pixel 8")
    options.set_capability(
        "bstack:options",
        {
            "projectName": "Mobile Testing Monorepo",
            "buildName": os.environ.get("BITRISE_BUILD_NUMBER", "local"),
            "sessionName": request.node.name,
            "userName": os.environ["BROWSERSTACK_USERNAME"],
            "accessKey": os.environ["BROWSERSTACK_ACCESS_KEY"],
        },
    )
    drv = webdriver.Remote("https://hub-cloud.browserstack.com/wd/hub", options=options)
    drv.implicitly_wait(10)

    recording_started = False
    if RECORD_VIDEO != "off":
        try:
            drv.start_recording_screen()
            recording_started = True
        except Exception as exc:  # noqa: BLE001 -- recording must never break the test
            print(f"[recording] WARN: could not start screen recording ({exc})")

    yield drv

    # Mark the session passed/failed in the BrowserStack dashboard.
    failed = request.node.rep_call.failed if hasattr(request.node, "rep_call") else False
    status = "failed" if failed else "passed"
    drv.execute_script(
        'browserstack_executor: {"action": "setSessionStatus", "arguments": {"status": "%s"}}' % status
    )

    # Local screenshot for every test, pass or fail (BrowserStack also records
    # a full session video per run, viewable in its dashboard regardless). Named
    # per Bitrise's attachment convention so it's auto-attached to the test case.
    classname = clean(request.module.__name__)
    name = clean(request.node.name)
    os.makedirs(TEST_RESULTS_DIR, exist_ok=True)
    drv.get_screenshot_as_file(os.path.join(TEST_RESULTS_DIR, f"{classname}__{name}__screenshot.png"))

    if recording_started and (RECORD_VIDEO == "all" or status == "failed"):
        try:
            video_b64 = drv.stop_recording_screen()
            video_path = os.path.join(TEST_RESULTS_DIR, f"{classname}__{name}__video.mp4")
            with open(video_path, "wb") as f:
                f.write(base64.b64decode(video_b64))
        except Exception as exc:  # noqa: BLE001
            print(f"[recording] WARN: could not save screen recording ({exc})")
    elif recording_started:
        try:
            drv.stop_recording_screen()  # discard -- RECORD_VIDEO=failures and this test passed
        except Exception:  # noqa: BLE001
            pass

    drv.quit()


@pytest.hookimpl(tryfirst=True, hookwrapper=True)
def pytest_runtest_makereport(item, call):
    outcome = yield
    rep = outcome.get_result()
    setattr(item, "rep_" + rep.when, rep)
