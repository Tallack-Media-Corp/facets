import SwiftUI

extension View {
    /// Keeps a centred floating piece (a chip, a card, a panel, a toast) off a fold
    /// that runs down through it, as on iPhone Duo's inner screen held sideways: it
    /// moves into the leading half, centred there. A fold across the screen (the Duo
    /// upright) passes above or below these, so nothing moves; nor on any other
    /// device. Apply it in place of centring, on the overlay content, so it measures
    /// the full width it's centred in.
    func clearOfFold() -> some View {
        modifier(ClearOfFold())
    }
}

private struct ClearOfFold: ViewModifier {
    /// The room left of the fold, in this view's space, while one runs through it.
    @State private var room: ClosedRange<CGFloat>?

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 27.1, *) {
            content
                .frame(maxWidth: room.map { $0.upperBound - $0.lowerBound })
                .frame(maxWidth: .infinity, alignment: room == nil ? .center : .leading)
                .onGeometryChange(for: ClosedRange<CGFloat>?.self) { proxy in
                    Self.room(in: proxy)
                } action: { room = $0 }
        } else {
            content
        }
        #else
        content
        #endif
    }

    #if os(iOS)
    /// From the leading edge to the fold's own margin, when an active fold runs
    /// vertically through the middle of the view. Open flat, the Duo still reports
    /// its fold but as inactive (one flat screen, which content may cross); only
    /// half-open, like a book, does it become active.
    @available(iOS 27.1, *)
    nonisolated private static func room(in proxy: GeometryProxy) -> ClosedRange<CGFloat>? {
        let width = proxy.size.width
        guard let fold = proxy.reservedRegions(kind: .division).first(where: {
            $0.isActive && $0.frame.height > $0.frame.width
                && $0.frame.minX > 0 && $0.frame.maxX < width
        }) else { return nil }
        // `frame` already includes the margins Apple asks interactive content to keep.
        let end = fold.frame.minX
        guard end > 160 else { return nil }
        return 0...end
    }
    #endif
}
