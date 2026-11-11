"""Appium E2E tests for the native Android app, run on real BrowserStack devices."""
from appium.webdriver.common.appiumby import AppiumBy


def by_tag(driver, tag):
    # Compose testTags are exposed as plain resource-ids (testTagsAsResourceId = true),
    # without the usual "package:id/" prefix, so match them with XPath.
    return driver.find_element(AppiumBy.XPATH, f'//*[@resource-id="{tag}"]')


def count_text(driver):
    return by_tag(driver, "count_label").text


def test_starts_at_zero(driver):
    assert count_text(driver) == "Count: 0"


def test_increment_and_reset(driver):
    by_tag(driver, "increment_button").click()
    by_tag(driver, "increment_button").click()
    assert count_text(driver) == "Count: 2"

    by_tag(driver, "reset_button").click()
    assert count_text(driver) == "Count: 0"
