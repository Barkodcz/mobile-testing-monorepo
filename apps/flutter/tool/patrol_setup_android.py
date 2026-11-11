#!/usr/bin/env python3
"""Apply Patrol's Android setup to a Flutter-generated android/ folder (Kotlin DSL).

Safe to run many times: every change is skipped if it is already there.
Usage (from apps/flutter):  python3 tool/patrol_setup_android.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
GRADLE = ROOT / "android/app/build.gradle.kts"
PACKAGE = "io.bitrise.sample.counter_flutter"
TEST_FILE = ROOT / "android/app/src/androidTest/java" / PACKAGE.replace(".", "/") / "MainActivityTest.java"

MAIN_ACTIVITY_TEST = f"""package {PACKAGE};

import androidx.test.platform.app.InstrumentationRegistry;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.junit.runners.Parameterized;
import org.junit.runners.Parameterized.Parameters;
import pl.leancode.patrol.PatrolJUnitRunner;

@RunWith(Parameterized.class)
public class MainActivityTest {{
    @Parameters(name = "{{0}}")
    public static Object[] testCases() {{
        PatrolJUnitRunner instrumentation = (PatrolJUnitRunner) InstrumentationRegistry.getInstrumentation();
        instrumentation.setUp(MainActivity.class);
        instrumentation.waitForPatrolAppService();
        return instrumentation.listDartTests();
    }}

    public MainActivityTest(String dartTestName) {{
        this.dartTestName = dartTestName;
    }}

    private final String dartTestName;

    @Test
    public void runDartTest() {{
        PatrolJUnitRunner instrumentation = (PatrolJUnitRunner) InstrumentationRegistry.getInstrumentation();
        instrumentation.runDartTest(dartTestName);
    }}
}}
"""


def main() -> int:
    if not GRADLE.exists():
        print(f"{GRADLE} not found. Run `flutter create . --platforms=android,ios` first "
              "(Flutter 3.29+ generates Kotlin DSL files).", file=sys.stderr)
        return 1

    text = GRADLE.read_text()
    if "PatrolJUnitRunner" not in text:
        text, n = re.subn(
            r"(defaultConfig\s*\{\n)",
            r'\1        testInstrumentationRunner = "pl.leancode.patrol.PatrolJUnitRunner"\n'
            r'        testInstrumentationRunnerArguments["clearPackageData"] = "true"\n',
            text, count=1)
        if n != 1:
            print("Could not find `defaultConfig {` in build.gradle.kts", file=sys.stderr)
            return 1
    if "ANDROIDX_TEST_ORCHESTRATOR" not in text:
        text = re.sub(r"(android\s*\{\n)",
                      r'\1    testOptions {\n        execution = "ANDROIDX_TEST_ORCHESTRATOR"\n    }\n',
                      text, count=1)
    if "androidx.test:orchestrator" not in text:
        text += '\ndependencies {\n    androidTestUtil("androidx.test:orchestrator:1.5.1")\n}\n'
    GRADLE.write_text(text)

    TEST_FILE.parent.mkdir(parents=True, exist_ok=True)
    if not TEST_FILE.exists():
        TEST_FILE.write_text(MAIN_ACTIVITY_TEST)

    print("Patrol Android setup applied:", GRADLE.relative_to(ROOT), "and", TEST_FILE.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
