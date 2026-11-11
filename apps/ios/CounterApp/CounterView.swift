import SwiftUI

struct CounterView: View {
    @State private var counter = Counter()

    var body: some View {
        VStack(spacing: 24) {
            Text(counter.label)
                .font(.largeTitle)
                .accessibilityIdentifier("count_label")
            HStack(spacing: 16) {
                Button("Decrement") { counter.decrement() }
                    .accessibilityIdentifier("decrement_button")
                Button("Increment") { counter.increment() }
                    .accessibilityIdentifier("increment_button")
            }
            .buttonStyle(.borderedProminent)
            Button("Reset") { counter.reset() }
                .accessibilityIdentifier("reset_button")
        }
        .padding()
    }
}

#Preview { CounterView() }
