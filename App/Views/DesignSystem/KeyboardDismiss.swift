import SwiftUI

extension View {
    func keyboardDoneButton<F: Hashable>(_ focus: FocusState<F?>.Binding) -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Xong") { focus.wrappedValue = nil }
                    .accessibilityIdentifier("keyboard.done")
            }
        }
    }
}
