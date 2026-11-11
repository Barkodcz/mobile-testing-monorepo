/** Jest config used by Detox for the E2E tests in this folder. */
module.exports = {
  rootDir: '..',
  testMatch: ['<rootDir>/e2e/**/*.e2e.js'],
  testTimeout: 120000,
  maxWorkers: 1,
  globalSetup: 'detox/runners/jest/globalSetup',
  globalTeardown: 'detox/runners/jest/globalTeardown',
  testEnvironment: 'detox/runners/jest/testEnvironment',
  reporters: [
    'detox/runners/jest/reporter',
    ['jest-junit', { outputDirectory: 'test-results', outputName: 'detox-junit.xml' }],
  ],
  verbose: true,
};
