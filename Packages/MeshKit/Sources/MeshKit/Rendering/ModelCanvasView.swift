#if canImport(UIKit) || canImport(AppKit)
import MetalKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The interactive 3D view. On iPhone and iPad: one finger orbits, two fingers pan,
/// pinch zooms, twist turns, double tap frames the model. On the Mac: drag orbits,
/// right-drag or Option-drag pans, the scroll wheel or a pinch zooms, two-finger
/// scrolling pans, rotating on the trackpad turns, arrow keys orbit, double-click
/// frames. Draws only when something changes, so an idle model costs no GPU time.
@MainActor
public final class ModelCanvasView: MTKView, MTKViewDelegate {
    public private(set) var renderer: SceneRenderer?
    public private(set) var camera = OrbitCamera()

    /// How the model is drawn. (Not `appearance`, which AppKit views already have.)
    public var renderAppearance = RenderAppearance() {
        didSet {
            guard renderAppearance != oldValue else { return }
            renderer?.appearance = renderAppearance
            if renderAppearance.plateID != oldValue.plateID {
                frameModel(animated: true)
            }
            requestDraw()
        }
    }

    /// Called while the user moves the camera, for hiding chrome or dismissing hints.
    public var onInteraction: (() -> Void)?

    /// What a single tap (or click) on the model does.
    public enum Tool: Sendable, Equatable {
        /// Nothing: taps are ignored (a double tap still frames the model).
        case none
        /// Picks points, snapping to a nearby corner of the face.
        case measure
        /// Picks a face, for laying it flat.
        case face
    }

    public var tool: Tool = .none {
        didSet {
            guard tool != oldValue else { return }
            #if canImport(UIKit)
            // A tool that needs taps on the model lets VoiceOver users touch it
            // directly; otherwise swipes keep reaching the camera actions.
            accessibilityTraits = tool == .none ? [.image] : [.image, .allowsDirectInteraction]
            accessibilityHint = tool == .none ? nil : "Touch the model directly to pick a point."
            #endif
        }
    }

    /// A tap landed on the model while a tool is active. For `.measure` the point is
    /// snapped to a corner within reach of the finger.
    public var onSurfaceTap: ((SurfaceHit, SIMD3<Float>) -> Void)?

    /// Points drawn over the model (world space): a dot each, and a line between each
    /// pair in turn. Used for measuring.
    public var markers: [SIMD3<Float>] = [] {
        didSet {
            guard markers != oldValue else { return }
            updateMarkers()
        }
    }
    private let markerHalo = CAShapeLayer()
    private let markerLine = CAShapeLayer()
    private let markerDots = CAShapeLayer()

    /// How much of the view's height a sheet covers from the bottom (0 to 1). The
    /// model glides up to stay centred in what's left.
    public var bottomObscured: CGFloat = 0 {
        didSet {
            guard bottomObscured != oldValue else { return }
            if Self.reduceMotion || window == nil {
                verticalShift = Float(bottomObscured)
                requestDraw()
            } else {
                startDisplayLink()
            }
        }
    }
    private var verticalShift: Float = 0

    private var needsFit = true
    private var displayLink: CADisplayLink?
    private var velocity = SIMD2<Float>.zero
    private var animation: (from: OrbitCamera, to: OrbitCamera, start: CFTimeInterval, duration: CFTimeInterval)?

    public init() {
        let context = RenderContext.shared
        super.init(frame: .zero, device: context?.device)
        if let context { renderer = SceneRenderer(context: context) }
        colorPixelFormat = RenderContext.colorFormat
        depthStencilPixelFormat = RenderContext.depthFormat
        sampleCount = RenderContext.sampleCount
        #if os(iOS)
        // Depth is never read back: keep the multisampled depth in tile memory
        // instead of a full-size texture (tens of MB on a large screen).
        depthStencilStorageMode = .memoryless
        #endif
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        isPaused = true
        enableSetNeedsDisplay = true
        autoResizeDrawable = true
        delegate = self
        #if canImport(UIKit)
        isOpaque = false
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        isAccessibilityElement = true
        // No direct interaction: it would hand VoiceOver's swipes to the model and
        // hide the camera actions below.
        accessibilityTraits = [.image]
        accessibilityLabel = "3D model"
        installGestures()
        #else
        wantsLayer = true
        layer?.isOpaque = false
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("3D model")
        #endif
        installAccessibilityActions()
        installMarkerLayers()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    public func setModel(_ model: Model3D?) {
        renderer?.setModel(model)
        renderer?.appearance = renderAppearance
        camera = OrbitCamera()
        needsFit = true
        #if canImport(UIKit)
        layoutIfNeeded()
        #else
        layoutSubtreeIfNeeded()
        #endif
        if bounds.width > 0 { frameModel(animated: false) }
        requestDraw()
    }

    /// Swaps in a rearranged version of the same model (turned or laid flat), keeping
    /// the viewing angle and easing to the new framing.
    public func replaceModel(_ model: Model3D?) {
        renderer?.setModel(model)
        renderer?.appearance = renderAppearance
        frameModel(animated: true)
        requestDraw()
    }

    /// Frames what's visible without changing the viewing angle.
    public func frameModel(animated: Bool) {
        guard let renderer, bounds.width > 0, bounds.height > 0 else { needsFit = true; return }
        var next = camera
        next.fitTightly(renderer.visibleParts, aspect: aspect, fill: 0.72, recenter: false, including: bedCorners)
        move(to: next, animated: animated)
        needsFit = false
    }

    public func show(_ preset: OrbitCamera.Preset, animated: Bool = true) {
        guard let renderer else { return }
        var next = camera
        next.apply(preset)
        next.fitTightly(renderer.visibleParts, aspect: aspect, fill: 0.72, recenter: false, including: bedCorners)
        move(to: next, animated: animated)
    }

    /// The bed's corners, when framing should show the whole bed: the model doesn't
    /// fit (so the overhang is in view), or it covers much of the bed. A small part
    /// on a big bed is framed on its own, or it would be a speck.
    private var bedCorners: [SIMD3<Float>] {
        guard let renderer, renderAppearance.showsGrid, let bed = renderAppearance.bed else { return [] }
        let footprint = renderer.focusBounds
        guard !footprint.isEmpty else { return [] }
        let bedSpan = max(bed.max.x - bed.min.x, bed.max.y - bed.min.y)
        let modelSpan = max(footprint.size.x, footprint.size.y)
        guard !bed.fits || modelSpan > bedSpan * 0.5 else { return [] }
        let z = footprint.min.z
        return [SIMD3(bed.min.x, bed.min.y, z), SIMD3(bed.max.x, bed.min.y, z), SIMD3(bed.max.x, bed.max.y, z), SIMD3(bed.min.x, bed.max.y, z)]
    }

    public func resetView() {
        show(.isometric)
    }

    private var aspect: Float {
        Float(max(bounds.width, 1) / max(bounds.height, 1))
    }

    private func move(to next: OrbitCamera, animated: Bool) {
        velocity = .zero
        if animated, !Self.reduceMotion, window != nil {
            animation = (camera, next, CACurrentMediaTime(), 0.4)
            startDisplayLink()
        } else {
            animation = nil
            camera = next
            requestDraw()
        }
    }

    private func nudge(yaw: Float, pitch: Float) {
        var next = camera
        next.orbit(dx: yaw, dy: pitch)
        move(to: next, animated: true)
    }

    private func interrupt() {
        animation = nil
        velocity = .zero
        onInteraction?()
    }

    // MARK: Platform

    private static var reduceMotion: Bool {
        #if canImport(UIKit)
        UIAccessibility.isReduceMotionEnabled
        #else
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #endif
    }

    private func requestDraw() {
        #if canImport(UIKit)
        setNeedsDisplay()
        #else
        needsDisplay = true
        #endif
    }

    private var pointScale: CGFloat {
        #if canImport(UIKit)
        contentScaleFactor
        #else
        window?.backingScaleFactor ?? 2
        #endif
    }

    /// Says something out loud to VoiceOver: what an action did, out of sight.
    private func announce(_ text: String) {
        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: text)
        #else
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
        #endif
    }

    // MARK: VoiceOver

    /// VoiceOver users can't drag or pinch, so the camera moves by action instead:
    /// swipe up or down on the model (or use the actions rotor on the Mac).
    private func installAccessibilityActions() {
        let step = Float.pi / 6
        let actions: [(String, @MainActor (ModelCanvasView) -> Void)] = [
            ("Turn left", { $0.nudge(yaw: step, pitch: 0) }),
            ("Turn right", { $0.nudge(yaw: -step, pitch: 0) }),
            ("Tilt up", { $0.nudge(yaw: 0, pitch: step / 2) }),
            ("Tilt down", { $0.nudge(yaw: 0, pitch: -step / 2) }),
            ("Front view", { $0.show(.front) }),
            ("Top view", { $0.show(.top) }),
            ("Isometric view", { $0.show(.isometric) }),
            ("Fit to screen", { $0.frameModel(animated: true) }),
        ]
        #if canImport(UIKit)
        accessibilityCustomActions = actions.map { name, perform in
            UIAccessibilityCustomAction(name: name) { [weak self] _ in
                guard let self else { return false }
                perform(self)
                self.announce(name)
                return true
            }
        }
        #else
        setAccessibilityCustomActions(actions.map { name, perform in
            NSAccessibilityCustomAction(name: name) { [weak self] in
                guard let self else { return false }
                perform(self)
                self.announce(name)
                return true
            }
        })
        #endif
    }

    // MARK: Drawing

    #if canImport(UIKit)
    public override func layoutSubviews() {
        super.layoutSubviews()
        fitIfNeeded()
    }
    #else
    public override func layout() {
        super.layout()
        fitIfNeeded()
    }

    /// Top-left origin, like UIKit, so screen points mean the same on both.
    public override var isFlipped: Bool { true }
    #endif

    private func fitIfNeeded() {
        if needsFit, bounds.width > 0, renderer?.model != nil {
            frameModel(animated: false)
        }
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        requestDraw()
    }

    public func draw(in view: MTKView) {
        guard let renderer,
              let pass = currentRenderPassDescriptor,
              let drawable = currentDrawable,
              let commands = renderer.context.queue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        let size = drawableSize
        renderer.encode(into: encoder, camera: camera, aspect: Float(size.width / max(size.height, 1)), pixelsPerPoint: Float(pointScale), verticalShift: verticalShift)
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
        if !markers.isEmpty { updateMarkers() }
    }

    // MARK: Picking and markers

    private var viewProjection: simd_float4x4? {
        guard let renderer, bounds.width > 0, bounds.height > 0 else { return nil }
        return renderer.viewProjection(camera: camera, aspect: aspect, verticalShift: verticalShift)
    }

    /// Where a world point lands on screen, in points from the top left; nil behind
    /// the camera.
    public func screenPoint(of world: SIMD3<Float>) -> CGPoint? {
        guard let viewProjection else { return nil }
        let clip = viewProjection * SIMD4(world, 1)
        guard clip.w > 0 else { return nil }
        let ndc = SIMD2(clip.x, clip.y) / clip.w
        return CGPoint(x: CGFloat((ndc.x + 1) / 2) * bounds.width, y: CGFloat((1 - ndc.y) / 2) * bounds.height)
    }

    /// The ray from the eye through a point on screen.
    private func ray(through point: CGPoint) -> (origin: SIMD3<Float>, direction: SIMD3<Float>)? {
        guard let viewProjection else { return nil }
        let inverse = viewProjection.inverse
        let x = Float(point.x / bounds.width) * 2 - 1
        let y = 1 - Float(point.y / bounds.height) * 2
        let near = inverse * SIMD4(x, y, 0, 1)
        let far = inverse * SIMD4(x, y, 1, 1)
        guard near.w != 0, far.w != 0 else { return nil }
        let a = SIMD3(near.x, near.y, near.z) / near.w
        let b = SIMD3(far.x, far.y, far.z) / far.w
        let direction = b - a
        guard simd_length(direction) > 0 else { return nil }
        return (a, simd_normalize(direction))
    }

    /// What's under a point on screen; respects the cross-section, so a cut-away top
    /// can't be picked. Runs off the main thread: a big mesh is millions of triangles.
    public func surface(at point: CGPoint) async -> SurfaceHit? {
        guard let renderer, let model = renderer.model, let ray = ray(through: point) else { return nil }
        let appearance = renderer.appearance
        let step = max(renderer.focusBounds.radius * 1e-5, 1e-4)
        let work = Task.detached(priority: .userInitiated) { () -> SurfaceHit? in
            guard let cut = appearance.sectionHeight else {
                return model.hit(origin: ray.origin, direction: ray.direction, plateID: appearance.plateID, hidden: appearance.hiddenObjects)
            }
            // Step past hits in the removed part until one lies below the cut.
            var origin = ray.origin
            for _ in 0..<32 {
                guard let hit = model.hit(origin: origin, direction: ray.direction, plateID: appearance.plateID, hidden: appearance.hiddenObjects) else { return nil }
                if hit.point.z <= cut + 0.001 { return hit }
                origin = hit.point + ray.direction * step
            }
            return nil
        }
        // Cancelling the caller (a newer tap) stops the scan too.
        return await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    }

    /// A tap or click at a point: picks a surface for the open tool.
    private func tapped(at location: CGPoint) {
        guard tool != .none else { return }
        let modelID = renderer?.model?.id
        pickTask?.cancel()
        pickTask = Task { @MainActor in
            guard let hit = await surface(at: location), !Task.isCancelled, renderer?.model?.id == modelID else { return }
            pick(hit, near: location)
        }
    }

    /// The tap being resolved; a newer one replaces it.
    private var pickTask: Task<Void, Never>?

    private func pick(_ hit: SurfaceHit, near location: CGPoint) {
        guard tool != .none else { return }
        var point = hit.point
        if tool == .measure {
            // A corner within a fingertip wins: measuring edge to edge is the usual job.
            #if canImport(UIKit)
            var best: CGFloat = 22
            #else
            var best: CGFloat = 10
            #endif
            for corner in hit.corners {
                guard let screen = screenPoint(of: corner) else { continue }
                let d = hypot(screen.x - location.x, screen.y - location.y)
                if d < best {
                    best = d
                    point = corner
                }
            }
        }
        onSurfaceTap?(hit, point)
    }

    private func installMarkerLayers() {
        #if canImport(UIKit)
        let host = layer
        #else
        guard let host = layer else { return }
        #endif
        for marker in [markerHalo, markerLine, markerDots] {
            marker.fillColor = nil
            marker.lineCap = .round
            marker.lineJoin = .round
            marker.actions = ["path": NSNull(), "position": NSNull(), "bounds": NSNull()]
            host.addSublayer(marker)
        }
        // Ink on a halo: the model is often the accent colour, so the accent alone
        // would vanish against it.
        markerHalo.lineWidth = 6
        markerLine.lineWidth = 2
        markerDots.lineWidth = 2.5
        updateMarkerColors()
        #if canImport(UIKit)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: ModelCanvasView, _: UITraitCollection) in
            view.updateMarkerColors()
        }
        #endif
    }

    #if canImport(AppKit) && !canImport(UIKit)
    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateMarkerColors()
    }
    #endif

    private func updateMarkerColors() {
        #if canImport(UIKit)
        let ink = UIColor.label.resolvedColor(with: traitCollection).cgColor
        let halo = UIColor.systemBackground.resolvedColor(with: traitCollection).withAlphaComponent(0.85).cgColor
        #else
        var ink = CGColor(gray: 0, alpha: 1), halo = CGColor(gray: 1, alpha: 0.85)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            ink = NSColor.labelColor.cgColor
            halo = NSColor.windowBackgroundColor.withAlphaComponent(0.85).cgColor
        }
        #endif
        markerHalo.strokeColor = halo
        markerLine.strokeColor = ink
        markerDots.strokeColor = ink
        markerDots.fillColor = halo
    }

    private func updateMarkers() {
        markerHalo.frame = bounds
        markerLine.frame = bounds
        markerDots.frame = bounds
        #if !canImport(UIKit)
        // The view is flipped; its sublayers aren't unless told.
        for marker in [markerHalo, markerLine, markerDots] { marker.isGeometryFlipped = true }
        #endif
        let screen = markers.map { screenPoint(of: $0) }
        let line = CGMutablePath()
        var index = 0
        while index + 1 < screen.count {
            if let a = screen[index], let b = screen[index + 1] {
                line.move(to: a)
                line.addLine(to: b)
            }
            index += 2
        }
        let dots = CGMutablePath()
        for case let point? in screen {
            dots.addEllipse(in: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
        }
        markerHalo.path = line
        markerLine.path = line
        markerDots.path = dots
    }

    // MARK: Motion

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        #if canImport(UIKit)
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        #else
        let link = displayLink(target: self, selector: #selector(step(_:)))
        #endif
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let targetShift = Float(bottomObscured)
        if abs(verticalShift - targetShift) > 0.001 {
            verticalShift += (targetShift - verticalShift) * 0.2
        } else {
            verticalShift = targetShift
        }
        if let animation {
            let t = min((link.timestamp - animation.start) / animation.duration, 1)
            let eased = Float(1 - pow(1 - t, 3))
            camera = animation.from.interpolated(to: animation.to, eased)
            if t >= 1 {
                camera = animation.to
                self.animation = nil
            }
        } else if simd_length(velocity) > 0.02 {
            let dt = Float(min(link.targetTimestamp - link.timestamp, 1.0 / 30))
            camera.orbit(dx: velocity.x * dt, dy: velocity.y * dt)
            velocity *= pow(0.02, dt)
        } else {
            velocity = .zero
        }
        requestDraw()
        if animation == nil, velocity == .zero, verticalShift == targetShift { stopDisplayLink() }
    }

    #if canImport(UIKit)
    public override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil { stopDisplayLink() }
    }
    #else
    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil { stopDisplayLink() }
    }
    #endif

    // MARK: Touch (iPhone and iPad)

    #if canImport(UIKit)
    private func installGestures() {
        let orbit = UIPanGestureRecognizer(target: self, action: #selector(handleOrbit(_:)))
        orbit.maximumNumberOfTouches = 1
        orbit.delegate = gestureDelegate
        addGestureRecognizer(orbit)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.delegate = gestureDelegate
        addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = gestureDelegate
        addGestureRecognizer(pinch)

        let twist = UIRotationGestureRecognizer(target: self, action: #selector(handleTwist(_:)))
        twist.delegate = gestureDelegate
        addGestureRecognizer(twist)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.require(toFail: doubleTap)
        addGestureRecognizer(tap)
    }

    private let gestureDelegate = SimultaneousGestures()

    /// Pan, pinch and twist combine; the one-finger orbit stands alone.
    private final class SimultaneousGestures: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            let multi: (UIGestureRecognizer) -> Bool = {
                $0 is UIPinchGestureRecognizer || $0 is UIRotationGestureRecognizer
                    || (($0 as? UIPanGestureRecognizer)?.minimumNumberOfTouches ?? 0) >= 2
            }
            return multi(gestureRecognizer) && multi(other)
        }
    }

    @objc private func handleOrbit(_ gesture: UIPanGestureRecognizer) {
        let scale = Float.pi / Float(max(min(bounds.width, bounds.height), 1)) * 1.1
        switch gesture.state {
        case .began:
            interrupt()
        case .changed:
            let t = gesture.translation(in: self)
            gesture.setTranslation(.zero, in: self)
            camera.orbit(dx: Float(t.x) * scale, dy: Float(t.y) * scale)
            requestDraw()
        case .ended:
            let v = gesture.velocity(in: self)
            velocity = SIMD2(Float(v.x), Float(v.y)) * scale
            if simd_length(velocity) > 0.3, !Self.reduceMotion { startDisplayLink() } else { velocity = .zero }
        default:
            break
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began { interrupt() }
        guard gesture.state == .changed else { return }
        let t = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)
        panCamera(by: t)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .began { interrupt() }
        guard gesture.state == .changed else { return }
        zoomCamera(by: Float(gesture.scale))
        gesture.scale = 1
    }

    @objc private func handleTwist(_ gesture: UIRotationGestureRecognizer) {
        if gesture.state == .began { interrupt() }
        guard gesture.state == .changed else { return }
        camera.yaw += Float(gesture.rotation)
        gesture.rotation = 0
        requestDraw()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        interrupt()
        frameModel(animated: true)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        tapped(at: gesture.location(in: self))
    }
    #endif

    /// Moves the camera so the point under the pointer stays under it.
    private func panCamera(by translation: CGPoint) {
        let k = 2 * tan(camera.fieldOfView / 2) / Float(max(bounds.height, 1))
        camera.pan(dx: Float(translation.x) * k, dy: Float(translation.y) * k)
        requestDraw()
    }

    private func zoomCamera(by factor: Float) {
        guard let renderer else { return }
        camera.zoom(by: factor, sceneRadius: renderer.focusBounds.radius)
        requestDraw()
    }

    // MARK: Mouse, trackpad and keyboard (Mac)

    #if !canImport(UIKit)
    private var dragStart: CGPoint?
    private var dragMoved = false
    private var panning = false

    public override var acceptsFirstResponder: Bool { true }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func location(of event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    /// A click waits out the double-click interval before it picks, so a double
    /// click (fit) doesn't also drop a measuring point.
    private var pendingClick: Task<Void, Never>?

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        pendingClick?.cancel()
        pendingClick = nil
        interrupt()
        dragStart = location(of: event)
        dragMoved = false
        panning = event.modifierFlags.contains(.option)
        if event.clickCount == 2 {
            frameModel(animated: true)
            dragStart = nil
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        guard dragStart != nil else { return }
        dragMoved = true
        if panning {
            panCamera(by: CGPoint(x: event.deltaX, y: event.deltaY))
        } else {
            let scale = Float.pi / Float(max(min(bounds.width, bounds.height), 1)) * 1.1
            camera.orbit(dx: Float(event.deltaX) * scale, dy: Float(event.deltaY) * scale)
            requestDraw()
        }
    }

    public override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        guard dragStart != nil, !dragMoved, event.clickCount == 1 else { return }
        let point = location(of: event)
        pendingClick = Task { [weak self] in
            try? await Task.sleep(for: .seconds(NSEvent.doubleClickInterval))
            guard !Task.isCancelled else { return }
            self?.tapped(at: point)
        }
    }

    public override func rightMouseDown(with event: NSEvent) {
        interrupt()
    }

    public override func rightMouseDragged(with event: NSEvent) {
        panCamera(by: CGPoint(x: event.deltaX, y: event.deltaY))
    }

    public override func otherMouseDragged(with event: NSEvent) {
        panCamera(by: CGPoint(x: event.deltaX, y: event.deltaY))
    }

    /// A mouse wheel zooms; two fingers on a trackpad pan, as in Maps.
    public override func scrollWheel(with event: NSEvent) {
        if event.phase == .began { interrupt() }
        if event.hasPreciseScrollingDeltas {
            panCamera(by: CGPoint(x: -event.scrollingDeltaX, y: -event.scrollingDeltaY))
        } else {
            zoomCamera(by: Float(pow(1.1, event.scrollingDeltaY)))
        }
    }

    public override func magnify(with event: NSEvent) {
        if event.phase == .began { interrupt() }
        zoomCamera(by: Float(1 + event.magnification))
    }

    public override func rotate(with event: NSEvent) {
        if event.phase == .began { interrupt() }
        camera.yaw += Float(event.rotation) * .pi / 180
        requestDraw()
    }

    /// Arrow keys orbit in steps; Option-arrows pan.
    public override func keyDown(with event: NSEvent) {
        let step = Float.pi / 12
        let panStep: CGFloat = 40
        let pan = event.modifierFlags.contains(.option)
        switch event.specialKey {
        case .leftArrow?: pan ? panCamera(by: CGPoint(x: panStep, y: 0)) : nudge(yaw: step, pitch: 0)
        case .rightArrow?: pan ? panCamera(by: CGPoint(x: -panStep, y: 0)) : nudge(yaw: -step, pitch: 0)
        case .upArrow?: pan ? panCamera(by: CGPoint(x: 0, y: panStep)) : nudge(yaw: 0, pitch: step / 2)
        case .downArrow?: pan ? panCamera(by: CGPoint(x: 0, y: -panStep)) : nudge(yaw: 0, pitch: -step / 2)
        default: super.keyDown(with: event)
        }
    }
    #endif
}

/// Lets SwiftUI drive the camera of a `ModelCanvas` (reset, presets).
@MainActor
public final class ModelCanvasController {
    weak var view: ModelCanvasView?

    public init() {}

    public func resetView() { view?.resetView() }
    public func show(_ preset: OrbitCamera.Preset) { view?.show(preset) }
    public func frameModel() { view?.frameModel(animated: true) }
}

/// SwiftUI wrapper around `ModelCanvasView`.
public struct ModelCanvas {
    let model: Model3D?
    let appearance: RenderAppearance
    let controller: ModelCanvasController?
    let onInteraction: (() -> Void)?
    let bottomObscured: CGFloat
    let tool: ModelCanvasView.Tool
    let markers: [SIMD3<Float>]
    let onSurfaceTap: ((SurfaceHit, SIMD3<Float>) -> Void)?

    public init(model: Model3D?, appearance: RenderAppearance, controller: ModelCanvasController? = nil, bottomObscured: CGFloat = 0, tool: ModelCanvasView.Tool = .none, markers: [SIMD3<Float>] = [], onSurfaceTap: ((SurfaceHit, SIMD3<Float>) -> Void)? = nil, onInteraction: (() -> Void)? = nil) {
        self.model = model
        self.appearance = appearance
        self.controller = controller
        self.bottomObscured = bottomObscured
        self.tool = tool
        self.markers = markers
        self.onSurfaceTap = onSurfaceTap
        self.onInteraction = onInteraction
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public final class Coordinator {
        var modelID: UUID?
        var sourceID: UUID?
    }

    @MainActor private func makeView(_ coordinator: Coordinator) -> ModelCanvasView {
        let view = ModelCanvasView()
        view.renderAppearance = appearance
        view.setModel(model)
        coordinator.modelID = model?.id
        coordinator.sourceID = model?.sourceID
        controller?.view = view
        view.onInteraction = onInteraction
        return view
    }

    @MainActor private func update(_ view: ModelCanvasView, _ coordinator: Coordinator) {
        if coordinator.modelID != model?.id {
            let sameFile = model != nil && coordinator.sourceID == model?.sourceID
            coordinator.modelID = model?.id
            coordinator.sourceID = model?.sourceID
            view.renderAppearance = appearance
            if sameFile {
                // Turned or laid flat: keep the camera's angle and reframe.
                view.replaceModel(model)
            } else {
                view.setModel(model)
            }
        } else {
            view.renderAppearance = appearance
        }
        controller?.view = view
        view.onInteraction = onInteraction
        view.bottomObscured = bottomObscured
        view.tool = tool
        view.markers = markers
        view.onSurfaceTap = onSurfaceTap
    }
}

#if canImport(UIKit)
extension ModelCanvas: UIViewRepresentable {
    public func makeUIView(context: Context) -> ModelCanvasView { makeView(context.coordinator) }
    public func updateUIView(_ view: ModelCanvasView, context: Context) { update(view, context.coordinator) }
}
#else
extension ModelCanvas: NSViewRepresentable {
    public func makeNSView(context: Context) -> ModelCanvasView { makeView(context.coordinator) }
    public func updateNSView(_ view: ModelCanvasView, context: Context) { update(view, context.coordinator) }
}
#endif
#endif
