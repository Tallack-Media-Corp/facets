// contact-sheet <out.png> <columns> <cell height> <a.png> <b.png> ...: lays the images
// in a grid, each keeping its shape and named underneath, on a mid-grey ground that
// sets off light and dark screens alike.
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count > 4, let columns = Int(args[2]), let cellHeight = Double(args[3]) else {
    print("usage: contact-sheet out.png columns cellHeight images..."); exit(2)
}
let shots = args.dropFirst(4).compactMap { path -> (image: CGImage, name: String)? in
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    return (image, URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
}
let images = shots.map(\.image)
guard !images.isEmpty else { print("no images"); exit(1) }
let widths = images.map { Double($0.width) / Double($0.height) * cellHeight }
let label = 36.0, fontSize = 22.0
let cellWidth = widths.max() ?? cellHeight, gap = 12.0, rows = (images.count + columns - 1) / columns
let rowHeight = cellHeight + label + gap
let width = Int(Double(min(columns, images.count)) * (cellWidth + gap)), height = Int(Double(rows) * rowHeight)
let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.setFillColor(CGColor(gray: 0.5, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: width, height: height))
context.interpolationQuality = .high
let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil)!
for (i, shot) in shots.enumerated() {
    let x = Double(i % columns) * (cellWidth + gap), top = Double(height) - Double(i / columns) * rowHeight
    context.draw(shot.image, in: CGRect(x: x, y: top - cellHeight, width: widths[i], height: cellHeight))
    let text = NSAttributedString(string: shot.name, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
    ])
    context.textPosition = CGPoint(x: x + 4, y: top - cellHeight - label + 10)
    CTLineDraw(CTLineCreateWithAttributedString(text), context)
}
let out = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(out, context.makeImage()!, nil)
exit(CGImageDestinationFinalize(out) ? 0 : 1)
