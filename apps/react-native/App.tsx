import React, { useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { decrement, formatCount, increment } from './src/counter';

function Button({ label, testID, onPress }: { label: string; testID: string; onPress: () => void }) {
  return (
    <Pressable accessibilityRole="button" testID={testID} onPress={onPress} style={styles.button}>
      <Text style={styles.buttonText}>{label}</Text>
    </Pressable>
  );
}

export default function App() {
  const [count, setCount] = useState(0);

  return (
    <View style={styles.container}>
      <Text testID="count_label" style={styles.count}>
        {formatCount(count)}
      </Text>
      <View style={styles.row}>
        <Button label="Decrement" testID="decrement_button" onPress={() => setCount(decrement)} />
        <Button label="Increment" testID="increment_button" onPress={() => setCount(increment)} />
      </View>
      <Button label="Reset" testID="reset_button" onPress={() => setCount(0)} />
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 24 },
  count: { fontSize: 32, fontWeight: '600' },
  row: { flexDirection: 'row', gap: 16 },
  button: { backgroundColor: '#6c3ce0', paddingHorizontal: 20, paddingVertical: 12, borderRadius: 8 },
  buttonText: { color: 'white', fontSize: 16 },
});
