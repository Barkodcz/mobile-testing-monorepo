// Component (UI) tests: render the screen in Node and interact like a user.
// React Native Testing Library v14+: render and fireEvent are async.
import React from 'react';
import { fireEvent, render, screen } from '@testing-library/react-native';
import App from '../App';

describe('Counter screen', () => {
  test('starts at zero', async () => {
    await render(<App />);
    expect(screen.getByText('Count: 0')).toBeOnTheScreen();
  });

  test('increment, decrement and reset update the label', async () => {
    await render(<App />);
    await fireEvent.press(screen.getByTestId('increment_button'));
    await fireEvent.press(screen.getByTestId('increment_button'));
    expect(screen.getByText('Count: 2')).toBeOnTheScreen();

    await fireEvent.press(screen.getByTestId('decrement_button'));
    expect(screen.getByText('Count: 1')).toBeOnTheScreen();

    await fireEvent.press(screen.getByTestId('reset_button'));
    expect(screen.getByText('Count: 0')).toBeOnTheScreen();
  });

  test('matches the component snapshot', async () => {
    const { toJSON } = await render(<App />);
    expect(toJSON()).toMatchSnapshot();
  });
});
