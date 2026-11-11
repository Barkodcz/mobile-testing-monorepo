module.exports = {
  preset: '@react-native/jest-preset',
  // Detox E2E tests live in e2e/ and have their own Jest config.
  testPathIgnorePatterns: ['/node_modules/', '/e2e/'],
  reporters: [
    'default',
    // Writes JUnit XML for the Bitrise Tests tab.
    ['jest-junit', { outputDirectory: 'test-results', outputName: 'jest-junit.xml' }],
  ],
};
