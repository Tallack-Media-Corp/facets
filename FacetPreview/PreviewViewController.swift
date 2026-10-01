import MeshKit
import QuickLook
import UIKit

/// Quick Look for STL and 3MF: long-press a model in Files, or tap one in Mail or
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
        backdrop.colors = dark
            ? [UIColor(white: 0.18, alpha: 1).cgColor, UIColor(white: 0.07, alpha: 1).cgColor]
            : [UIColor(white: 0.97, alpha: 1).cgColor, UIColor(white: 0.86, alpha: 1).cgColor]
        canvas.appearance.gridColor = RenderAppearance.gridColor(dark: dark)
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let model = try await Task.detached(priority: .userInitiated) {
            try ModelLoader.load(url)
        }.value
        canvas.appearance.plateID = model.plates.first?.id
        canvas.setModel(model)
    }
}
