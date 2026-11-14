import Observation
import SwiftUI

/// A short confirmation that floats above the content: "Saved to Library", "Deleted
/// 'funnel' · Undo". One at a time; VoiceOver hears each one.
@MainActor
@Observable
final class ToastCenter {
    struct Toast: Identifiable {
        enum Kind { case success, warning }

        let id = UUID()
        let message: String
        let symbol: String
        var kind = Kind.success
        var actionTitle: String?
        var action: (() -> Void)?
    }

    private(set) var current: Toast?
    private var dismissal: Task<Void, Never>?

    /// Shows a toast, replacing any already up. One with an action stays a little
    /// longer so there's time to reach it.
    func show(_ message: String, symbol: String = Symbol.success, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        post(Toast(message: message, symbol: symbol, actionTitle: actionTitle, action: action))
    }

    /// Something didn't work: a warning sign, and a warning tap.
    func warn(_ message: String) {
        post(Toast(message: message, symbol: Symbol.warning, kind: .warning))
    }

    private func post(_ toast: Toast) {
        let message = toast.message, actionTitle = toast.actionTitle, action = toast.action
        withAnimation(Motion.standard) { current = toast }
        var announcement = message
        if let actionTitle { announcement = String(localized: "\(message). \(actionTitle) is available.", comment: "VoiceOver: a toast's message, then its button") }
        AccessibilityNotification.Announcement(announcement).post()

        dismissal?.cancel()
        let shown = action == nil ? Motion.toastShown : Motion.toastWithActionShown
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: shown)
            guard !Task.isCancelled else { return }
            self?.dismiss(toast.id)
        }
    }

    func dismiss(_ id: UUID? = nil) {
        guard id == nil || current?.id == id else { return }
        withAnimation(Motion.standard) { current = nil }
    }
}

private struct ToastView: View {
    let toast: ToastCenter.Toast
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            Label(toast.message, systemImage: toast.symbol)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            if let title = toast.actionTitle {
                Button(title, action: onAction)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                    .frame(minHeight: Size.minTapTarget)
            }
        }
        // The same chip as the gesture hint; a button sets its own height.
        .glassChip(toast.actionTitle == nil ? ChipPadding.toast : ChipPadding.toastWithAction)
        .padding(.horizontal)
    }
}

extension View {
    /// Shows `ToastCenter`'s toast along the bottom edge, clear of what's there: the
    /// tab bar on iPhone (iPad's is at the top), or the viewer's bottom toolbar on
    /// iPhone and iPad with `aboveBottomToolbar`. On the Mac neither is at the bottom.
    func toastHost(aboveBottomToolbar: Bool = false) -> some View {
        modifier(ToastHost(aboveBottomToolbar: aboveBottomToolbar))
    }
}

private struct ToastHost: ViewModifier {
    let aboveBottomToolbar: Bool
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clearance: CGFloat {
        #if os(iOS)
        if aboveBottomToolbar { return Size.toastOverToolbar }
        return sizeClass == .compact ? Size.toastOverTabBar : Spacing.xxl
        #else
        Spacing.xxl
        #endif
    }

    func body(content: Content) -> some View {
        content
            // A warning toast taps like a warning; everything else like a success.
            .sensoryFeedback(trigger: toasts.current?.id) { _, _ in
                guard let toast = toasts.current else { return nil }
                return toast.kind == .warning ? .warning : .success
            }
            .overlay(alignment: .bottom) {
                if let toast = toasts.current {
                    ToastView(toast: toast) {
                        toast.action?()
                        toasts.dismiss(toast.id)
                    }
                    .padding(.bottom, clearance)
                    .clearOfFold()
                    // Slides up; with Reduce Motion, fades.
                    .transition(Motion.transition(.move(edge: .bottom).combined(with: .opacity), reduceMotion: reduceMotion))
                    .id(toast.id)
                }
            }
    }
}
