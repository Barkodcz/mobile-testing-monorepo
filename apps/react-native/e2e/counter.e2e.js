// Detox E2E test: runs the real app on an iOS simulator.
describe('Counter app', () => {
  beforeAll(async () => {
    await device.launchApp({ newInstance: true });
  });

  beforeEach(async () => {
    await device.reloadReactNative();
  });

  it('shows the initial count', async () => {
    await expect(element(by.id('count_label'))).toHaveText('Count: 0');
    await device.takeScreenshot('initial_count');
  });

  it('increments and resets', async () => {
    await element(by.id('increment_button')).tap();
    await element(by.id('increment_button')).tap();
    await expect(element(by.id('count_label'))).toHaveText('Count: 2');
    await device.takeScreenshot('after_increment');
    await element(by.id('reset_button')).tap();
    await expect(element(by.id('count_label'))).toHaveText('Count: 0');
    await device.takeScreenshot('after_reset');
  });
});
