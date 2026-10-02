import Foundation

/// Opens any supported file, choosing the reader by content rather than trusting the
/// extension (a 3MF renamed .stl still opens).
public enum ModelLoader {
    public static let supportedExtensions: Set<String> = ["stl", "3mf", "obj"]

    public static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    public static func load(_ url: URL) throws -> Model3D {
        let name = url.deletingPathExtension().lastPathComponent
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        return try load(data, name: name, fileExtension: url.pathExtension)
    }

    public static func load(_ data: Data, name: String, fileExtension: String = "") throws -> Model3D {
        guard !data.isEmpty else { throw ModelError.emptyFile }
        if isZip(data) {
            return try ThreeMFReader.read(ZipArchive(data: data), name: name)
        }
        if fileExtension.lowercased() == "3mf" {
            throw ModelError.corrupt("it isn't a ZIP package")
        }
        // OBJ is plain text with nothing to sniff for reliably; go by the name.
        if fileExtension.lowercased() == "obj" {
            return try OBJReader.read(data, name: name)
        }
        return try STLReader.read(data, name: name)
    }

    static func isZip(_ data: Data) -> Bool {
        data.count >= 4 && data.prefix(4).elementsEqual([0x50, 0x4B, 0x03, 0x04])
    }
}
