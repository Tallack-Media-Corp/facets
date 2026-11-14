import SwiftUI

extension Optional {
    /// Whether there's a value; setting it false clears it. As a binding
    /// (`$failure.isPresent`), it shows an alert or dialog while the optional is set.
    var isPresent: Bool {
        get { self != nil }
        set { if !newValue { self = nil } }
    }
}

extension View {
    /// Says what went wrong while `message` is set, under a title from the string catalog. OK clears it.
    func errorAlert(_ title: LocalizedStringResource, message: Binding<String?>) -> some View {
        errorAlert(Text(title), isPresented: message.isPresent, message: message.wrappedValue)
    }

    /// The same, for a title worked out with the message (which operation failed).
    func errorAlert(_ failure: Binding<(title: String, message: String)?>) -> some View {
        errorAlert(Text(verbatim: failure.wrappedValue?.title ?? ""), isPresented: failure.isPresent, message: failure.wrappedValue?.message)
    }

    private func errorAlert(_ title: Text, isPresented: Binding<Bool>, message: String?) -> some View {
        alert(title, isPresented: isPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    /// Asks for a new name while `item` is set; `text` starts as the current name.
    func renameAlert<Item>(_ title: LocalizedStringResource, item: Binding<Item?>, text: Binding<String>, rename: @escaping (Item) -> Void) -> some View {
        alert(Text(title), isPresented: item.isPresent) {
            TextField("Name", text: text)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let current = item.wrappedValue { rename(current) }
            }
        }
    }
}
