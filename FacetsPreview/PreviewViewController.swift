import MeshKit
import QuickLook
#if os(iOS)
import UIKit

/// Quick Look for STL, 3MF and OBJ: long-press a model in Files, or tap one in Mail or
/// Messages, and it turns in 3D right there.
final class PreviewViewController: UIViewController, QLPreviewingController {
    private let canvas = ModelCanvasView()
    private let backdrop = CAGradientLayer()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.layer.insertSublayer(backdrop, at: 0)
        canvas.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(canvas)
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: view.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        updateColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (controller: PreviewViewController, _) in
            controller.updateColors()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backdrop.frame = view.bounds
    }

    private func updateColors() {
        let dark = traitCollection.userInterfaceStyle == .dark
        // The app's Stage, Pure Black included, so Quick Look and the viewer match.
        let stage = Palette.stage(pureBlack: SharedSettings.pureBlack)
        backdrop.colors = [stage.top, stage.floor].map { $0.resolvedColor(with: traitCollection).cgColor }
        canvas.renderAppearance.gridColor = RenderAppearance.gridColor(dark: dark)
    }

    /// The preview extension has a small memory budget, and a mesh lives twice (in
    /// memory and in its Metal buffer). Past these, it says so instead of being
    /// stopped mid-load. A 3MF's entries are also capped as they inflate.
    private static let limitSTL = 40_000_000
    private static let limitOBJ = 15_000_000
    private static let inflateLimit = 80_000_000

    func preparePreviewOfFile(at url: URL) async throws {
        ZipArchive.maximumEntrySize = Self.inflateLimit
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        switch url.pathExtension.lowercased() {
        case "stl" where size > Self.limitSTL, "obj" where size > Self.limitOBJ:
            throw ModelError.tooLarge
        default:
            break
        }
        let model = try await Task.detached(priority: .userInitiated) {
            try ModelLoader.load(url)
        }.value
        canvas.renderAppearance.plateID = model.plates.first?.id
        canvas.setModel(model)
    }
}
#else
import AppKit
import Quartz

/// Quick Look for STL, 3MF and OBJ in the Finder: press Space on a model and it turns
/// in 3D, on Quick Look's own background.
final class PreviewViewController: NSViewController, QLPreviewingController {
    private let canvas = ModelCanvasView()

    override func loadView() {
        let stage = StageView()
        stage.onAppearanceChange = { [weak self] dark in
            self?.canvas.renderAppearance.gridColor = RenderAppearance.gridColor(dark: dark)
        }
        canvas.frame = stage.bounds
        canvas.autoresizingMask = [.width, .height]
        stage.addSubview(canvas)
        view = stage
        preferredContentSize = NSSize(width: 800, height: 600)
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let model = try await Task.detached(priority: .userInitiated) {
            try ModelLoader.load(url)
        }.value
        canvas.renderAppearance.plateID = model.plates.first?.id
        canvas.setModel(model)
    }
}

/// No stage of our own on the Mac: the model sits on the Quick Look panel's own
/// translucent material, as the system's 3D preview does (it sets a clear
/// background), so it feels part of the Finder in light and dark. Only the grid
/// follows the appearance.
private final class StageView: NSView {
    var onAppearanceChange: ((Bool) -> Void)? {
        didSet { updateColors() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        onAppearanceChange?(effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
    }
}
#endif
