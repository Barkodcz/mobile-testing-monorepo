"""Appium E2E tests for the native iOS app, run on a local Simulator.

Uses the `ios_driver` fixture (XCUITest driver) added in conftest.py for
scenario 5 -- the existing Android test_counter.py and its `driver` fixture
are untouched.
"""
from appium.webdriver.common.appiumby import AppiumBy


def by_id(driver, element_id):
    return driver.find_element(AppiumBy.ACCESSIBILITY_ID, element_id)


def count_text(driver):
    return by_id(driver, "count_label").text


def test_starts_at_zero(ios_driver):
    assert count_text(ios_driver) == "Count: 0"


def test_increment_and_reset(ios_driver):
    by_id(ios_driver, "increment_button").click()
    by_id(ios_driver, "increment_button").click()
    assert count_text(ios_driver) == "Count: 2"

    by_id(ios_driver, "reset_button").click()
    assert count_text(ios_driver) == "Count: 0"


def test_decrement_floors_at_zero(ios_driver):
    by_id(ios_driver, "decrement_button").click()
    assert count_text(ios_driver) == "Count: 0"
