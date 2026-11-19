import SwiftUI

/// The actions list rows and cards offer, each with its one title, symbol and role.
/// Callers say what it does, and pass a title where the wording is theirs
/// ("Remove from Recents").
enum RowAction {
    static func delete(_ title: LocalizedStringKey = "Delete", action: @escaping () -> Void) -> some View {
        Button(title, systemImage: Symbol.delete, role: .destructive, action: action)
    }

    static func rename(action: @escaping () -> Void) -> some View {
        Button("Rename", systemImage: Symbol.rename, action: action)
    }

    /// Takes something off a list without touching the file.
    static func remove(_ title: LocalizedStringKey = "Remove", action: @escaping () -> Void) -> some View {
        Button(title, systemImage: Symbol.remove, role: .destructive, action: action)
    }

    static func restore(action: @escaping () -> Void) -> some View {
        Button("Restore", systemImage: Symbol.restore, action: action)
    }
}
