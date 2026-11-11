"""Pytest fixtures: one Appium session per test, on BrowserStack or a local Appium server."""
import os

import pytest
from appium import webdriver
from appium.options.android import UiAutomator2Options


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
    yield drv

    # Mark the session passed/failed in the BrowserStack dashboard.
    failed = request.node.rep_call.failed if hasattr(request.node, "rep_call") else False
    status = "failed" if failed else "passed"
    drv.execute_script(
        'browserstack_executor: {"action": "setSessionStatus", "arguments": {"status": "%s"}}' % status
    )
    drv.quit()


@pytest.hookimpl(tryfirst=True, hookwrapper=True)
def pytest_runtest_makereport(item, call):
    outcome = yield
    rep = outcome.get_result()
    setattr(item, "rep_" + rep.when, rep)
