/** @type {Detox.DetoxConfig} */
module.exports = {
  testRunner: {
    args: { $0: 'jest', config: 'e2e/jest.config.js' },
    jest: { setupTimeout: 120000 },
  },
  apps: {
    'ios.release': {
      type: 'ios.app',
      binaryPath: 'ios/build/Build/Products/Release-iphonesimulator/CounterRN.app',
      build:
        'xcodebuild -workspace ios/CounterRN.xcworkspace -scheme CounterRN -configuration Release -sdk iphonesimulator -derivedDataPath ios/build -quiet',
    },
  },
  devices: {
    simulator: { type: 'ios.simulator', device: { type: 'iPhone 16' } },
  },
  configurations: {
    'ios.sim.release': { device: 'simulator', app: 'ios.release' },
  },
  artifacts: {
    // Same directory jest-junit writes detox-junit.xml to (e2e/jest.config.js):
    // custom-test-results-export only matches attachment filenames under its
    // base_path, so artifacts and the JUnit XML have to be co-located.
    rootDir: './test-results',
    // Names every screenshot/video/log per Bitrise's attachment convention
    // so custom-test-results-export attaches it to its test case.
    pathBuilder: './e2e/bitrisePathBuilder.js',
    plugins: {
      // Modes (all/failing/none) are set per-run via the --record-videos and
      // --take-screenshots CLI flags (mapped from $RECORD_VIDEO), not here.
      screenshot: { enabled: true },
      video: { enabled: true },
      log: { enabled: true },
    },
  },
};
