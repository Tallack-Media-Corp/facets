import Observation
import SwiftUI

/// A short confirmation that floats above the content: "Saved to Library", "Deleted
/// 'funnel' · Undo". One at a time; VoiceOver hears each one.
@MainActor
@Observable
final class ToastCenter {
    struct Toast: Identifiable {
        let id = UUID()
        let message: String
        let symbol: String
        var actionTitle: String?
        var action: (() -> Void)?
    }

    private(set) var current: Toast?
    private var dismissal: Task<Void, Never>?

    /// Shows a toast, replacing any already up. One with an action stays a little
    /// longer so there's time to reach it.
    func show(_ message: String, symbol: String = "checkmark.circle.fill", actionTitle: String? = nil, action: (() -> Void)? = nil) {
        let toast = Toast(message: message, symbol: symbol, actionTitle: actionTitle, action: action)
        withAnimation(.snappy) { current = toast }
        var announcement = message
        if let actionTitle { announcement += ". \(actionTitle) is available." }
        AccessibilityNotification.Announcement(announcement).post()

        dismissal?.cancel()
        let seconds: Double = action == nil ? 3 : 6
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.dismiss(toast.id)
        }
    }

    func dismiss(_ id: UUID? = nil) {
        guard id == nil || current?.id == id else { return }
        withAnimation(.snappy) { current = nil }
    }
}

private struct ToastView: View {
    let toast: ToastCenter.Toast
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label(toast.message, systemImage: toast.symbol)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            if let title = toast.actionTitle {
                Button(title, action: onAction)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, toast.actionTitle == nil ? 16 : 12)
        .padding(.vertical, toast.actionTitle == nil ? 10 : 0)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal)
    }
}

extension View {
    /// Shows `ToastCenter`'s toast along the bottom edge, clear of the tab bar or
    /// bottom toolbar by `clearance`.
    func toastHost(clearance: CGFloat) -> some View {
        modifier(ToastHost(clearance: clearance))
    }
}

private struct ToastHost: ViewModifier {
    let clearance: CGFloat
    @Environment(ToastCenter.self) private var toasts

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast = toasts.current {
                ToastView(toast: toast) {
                    toast.action?()
                    toasts.dismiss(toast.id)
                }
                .padding(.bottom, clearance)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(toast.id)
            }
        }
    }
}
