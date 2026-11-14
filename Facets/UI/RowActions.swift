import SwiftUI

/// The actions list rows and cards offer, each with its one title, symbol and role.
/// Callers say what it does, and pass a title where the wording is theirs
/// ("Remove from Recents").
enum RowAction {
    static func delete(_ title: LocalizedStringKey = "Delete", action: @escaping () -> Void) -> some View {
        Button(title, systemImage: "trash", role: .destructive, action: action)
    }

    static func rename(action: @escaping () -> Void) -> some View {
        Button("Rename", systemImage: "pencil", action: action)
    }

    /// Takes something off a list without touching the file.
    static func remove(_ title: LocalizedStringKey = "Remove", action: @escaping () -> Void) -> some View {
        Button(title, systemImage: "minus.circle", role: .destructive, action: action)
    }

    static func restore(action: @escaping () -> Void) -> some View {
        Button("Restore", systemImage: "arrow.uturn.backward", action: action)
    }
}
