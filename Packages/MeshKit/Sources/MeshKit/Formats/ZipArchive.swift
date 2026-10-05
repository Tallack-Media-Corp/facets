import Compression
import Foundation

/// The read side of ZIP, enough for 3MF packages: stored and deflated entries, and
/// ZIP64 for archives over 4 GB or with huge entries. The file is memory-mapped and
/// only the entries asked for are inflated.
public struct ZipArchive: Sendable {
    struct Entry: Sendable {
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private let data: Data
    private let entries: [String: Entry]
    /// Lowercased paths, because some writers disagree with their own relationships
    /// about case.
    private let folded: [String: String]

    public init(url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .alwaysMapped))
    }

    public init(data: Data) throws {
        self.data = data
        let entries = try data.withUnsafeBytes { try Self.readDirectory($0) }
        self.entries = entries
        var folded: [String: String] = [:]
        for key in entries.keys { folded[key.lowercased()] = key }
        self.folded = folded
    }

    public var paths: [String] { Array(entries.keys) }

    public func contains(_ path: String) -> Bool { entry(for: path) != nil }

    private func entry(for path: String) -> Entry? {
        let key = Self.normalize(path)
        if let entry = entries[key] { return entry }
        if let real = folded[key.lowercased()] { return entries[real] }
        return nil
    }

    /// Strips the leading slash 3MF relationship targets use, and percent-escapes.
    static func normalize(_ path: String) -> String {
        var p = path
        while p.hasPrefix("/") { p.removeFirst() }
        return p.removingPercentEncoding ?? p
    }

    public func data(for path: String) throws -> Data {
        guard let entry = entry(for: path) else {
            throw ModelError.corrupt("\(path) is missing from the package")
        }
        return try data.withUnsafeBytes { raw -> Data in
            let local = entry.localHeaderOffset
            guard local + 30 <= raw.count, raw.loadUnaligned(fromByteOffset: local, as: UInt32.self).littleEndian == 0x0403_4B50 else {
                throw ModelError.corrupt("a package entry header is damaged")
            }
            let nameLength = Int(raw.loadUnaligned(fromByteOffset: local + 26, as: UInt16.self).littleEndian)
            let extraLength = Int(raw.loadUnaligned(fromByteOffset: local + 28, as: UInt16.self).littleEndian)
            let start = local + 30 + nameLength + extraLength
            guard start + entry.compressedSize <= raw.count else {
                throw ModelError.corrupt("a package entry runs past the end of the file")
            }
            let source = UnsafeRawBufferPointer(rebasing: raw[start..<(start + entry.compressedSize)])
            switch entry.method {
            case 0:
                return Data(source)
            case 8:
                return try Self.inflate(source, size: entry.uncompressedSize)
            default:
                throw ModelError.corrupt("the package uses an unsupported compression method (\(entry.method))")
            }
        }
    }

    /// The most one entry may expand to. Quick Look extensions lower it to stay
    /// inside their memory budget; a declared size above it is refused before
    /// anything is allocated (a ZIP bomb, or simply too big to show).
    nonisolated(unsafe) public static var maximumEntrySize = 1_500_000_000

    private static func inflate(_ source: UnsafeRawBufferPointer, size: Int) throws -> Data {
        if size == 0 { return Data() }
        guard size <= maximumEntrySize else {
            throw ModelError.tooLarge
        }
        // Deflate can't shrink data by more than about 1032:1.
        guard size / 1032 <= max(source.count, 1) else {
            throw ModelError.corrupt("a package entry is damaged")
        }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { out -> Int in
            guard let dst = out.bindMemory(to: UInt8.self).baseAddress,
                  let src = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            // COMPRESSION_ZLIB is raw DEFLATE (RFC 1951), which is what ZIP stores.
            return compression_decode_buffer(dst, size, src, source.count, nil, COMPRESSION_ZLIB)
        }
        guard written == size else {
            throw ModelError.corrupt("a package entry didn't decompress")
        }
        return output
    }

    private static func readDirectory(_ raw: UnsafeRawBufferPointer) throws -> [String: Entry] {
        func u16(_ o: Int) -> Int { Int(raw.loadUnaligned(fromByteOffset: o, as: UInt16.self).littleEndian) }
        func u32(_ o: Int) -> Int { Int(raw.loadUnaligned(fromByteOffset: o, as: UInt32.self).littleEndian) }
        // A value that doesn't fit an Int is damage; -1 fails every range check below.
        func u64(_ o: Int) -> Int { Int(exactly: raw.loadUnaligned(fromByteOffset: o, as: UInt64.self).littleEndian) ?? -1 }

        guard raw.count >= 22 else { throw ModelError.corrupt("it isn't a ZIP package") }
        // The end-of-central-directory record sits in the last 64 KB + 22 bytes.
        var eocd = -1
        let floor = max(0, raw.count - 65_557)
        var i = raw.count - 22
        while i >= floor {
            if u32(i) == 0x0605_4B50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ModelError.corrupt("it isn't a ZIP package") }

        var count = u16(eocd + 10)
        var directoryOffset = u32(eocd + 16)
        if count == 0xFFFF || directoryOffset == 0xFFFF_FFFF {
            // ZIP64: the locator sits just before the classic record.
            let locator = eocd - 20
            guard locator >= 0, u32(locator) == 0x0706_4B50 else { throw ModelError.corrupt("the ZIP64 directory is missing") }
            let record = u64(locator + 8)
            guard record >= 0, record + 56 <= raw.count, u32(record) == 0x0606_4B50 else { throw ModelError.corrupt("the ZIP64 directory is damaged") }
            count = u64(record + 32)
            directoryOffset = u64(record + 48)
        }
        // Each directory record is at least 46 bytes; a count the file can't hold is damage.
        guard count >= 0, directoryOffset >= 0, directoryOffset <= raw.count, count <= (raw.count - directoryOffset) / 46 else {
            throw ModelError.corrupt("the package directory is damaged")
        }

        var entries: [String: Entry] = [:]
        entries.reserveCapacity(count)
        var p = directoryOffset
        for _ in 0..<count {
            guard p >= 0, p + 46 <= raw.count, u32(p) == 0x0201_4B50 else {
                throw ModelError.corrupt("the package directory is damaged")
            }
            let method = UInt16(u16(p + 10))
            var compressed = u32(p + 20)
            var uncompressed = u32(p + 24)
            let nameLength = u16(p + 28)
            let extraLength = u16(p + 30)
            let commentLength = u16(p + 32)
            var localOffset = u32(p + 42)
            guard p + 46 + nameLength + extraLength <= raw.count else {
                throw ModelError.corrupt("the package directory is damaged")
            }
            let name = String(decoding: UnsafeRawBufferPointer(rebasing: raw[(p + 46)..<(p + 46 + nameLength)]), as: UTF8.self)

            // ZIP64 extra field: only the values that overflowed are present, in order.
            var e = p + 46 + nameLength
            let extraEnd = e + extraLength
            while e + 4 <= extraEnd {
                let id = u16(e)
                let size = u16(e + 2)
                if id == 0x0001 {
                    var f = e + 4
                    if uncompressed == 0xFFFF_FFFF, f + 8 <= extraEnd { uncompressed = u64(f); f += 8 }
                    if compressed == 0xFFFF_FFFF, f + 8 <= extraEnd { compressed = u64(f); f += 8 }
                    if localOffset == 0xFFFF_FFFF, f + 8 <= extraEnd { localOffset = u64(f) }
                }
                e += 4 + size
            }

            guard compressed >= 0, uncompressed >= 0, localOffset >= 0 else {
                throw ModelError.corrupt("the package directory is damaged")
            }
            if !name.hasSuffix("/") {
                entries[normalize(name)] = Entry(method: method, compressedSize: compressed, uncompressedSize: uncompressed, localHeaderOffset: localOffset)
            }
            p += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }
}
