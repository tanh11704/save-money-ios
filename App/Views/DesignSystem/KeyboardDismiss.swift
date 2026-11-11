import SwiftUI

extension View {
    func keyboardDoneButton<F: Hashable>(_ focus: FocusState<F?>.Binding) -> some View {
        // Keep the accessory in our layout instead of the system keyboard toolbar,
        // avoiding toolbar layout transitions while focus and keyboard visibility change.
        safeAreaInset(edge: .bottom, spacing: 0) {
            if focus.wrappedValue != nil {
                HStack {
                    Spacer(minLength: 0)
                    Button("Xong") { focus.wrappedValue = nil }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("keyboard.done")
                }
                .padding(.horizontal, Spacing.l)
                .background(.bar)
            }
        }
    }
}
