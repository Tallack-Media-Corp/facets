import Foundation

/// A minimal, allocation-free XML tokenizer for 3MF model parts. A model can hold
/// millions of `<vertex>` elements; Foundation's XMLParser builds a dictionary of
/// Strings for each one, which is most of the load time. This hands the caller byte
/// ranges instead, and skips what 3MF never needs (DTDs, CDATA, namespaces).
struct XMLScanner {
    struct Attribute {
        var name: Range<Int>
        var value: Range<Int>
    }

    struct Element {
        var name: Range<Int> = 0..<0
        var attributes: [Attribute] = []
        var isSelfClosing = false
    }

    enum Event {
        case start
        case end(Range<Int>)
    }

    let bytes: UnsafeRawBufferPointer
    private(set) var position = 0
    /// Reused for every start tag, so scanning doesn't allocate.
    private(set) var element = Element()

    init(_ bytes: UnsafeRawBufferPointer) {
        self.bytes = bytes
        element.attributes.reserveCapacity(16)
    }

    /// Advances to the next start or end tag. Text between tags is skipped; call
    /// `text()` right after a start tag to read it.
    mutating func next() -> Event? {
        let end = bytes.count
        while position < end {
            guard let lt = find(UInt8(ascii: "<"), from: position) else {
                position = end
                return nil
            }
            var i = lt + 1
            guard i < end else { position = end; return nil }
            let c = bytes[i]
            if c == UInt8(ascii: "?") {
                position = (find(UInt8(ascii: ">"), from: i) ?? end - 1) + 1
                continue
            }
            if c == UInt8(ascii: "!") {
                if i + 2 < end, bytes[i + 1] == UInt8(ascii: "-"), bytes[i + 2] == UInt8(ascii: "-") {
                    position = (findCommentEnd(from: i + 3) ?? end - 1) + 1
                } else {
                    position = (find(UInt8(ascii: ">"), from: i) ?? end - 1) + 1
                }
                continue
            }
            if c == UInt8(ascii: "/") {
                i += 1
                let nameStart = i
                while i < end, !ByteScan.isSpace(bytes[i]), bytes[i] != UInt8(ascii: ">") { i += 1 }
                let name = nameStart..<i
                position = (find(UInt8(ascii: ">"), from: i) ?? end - 1) + 1
                return .end(name)
            }

            // Start tag.
            let nameStart = i
            while i < end, !ByteScan.isSpace(bytes[i]), bytes[i] != UInt8(ascii: ">"), bytes[i] != UInt8(ascii: "/") { i += 1 }
            element.name = nameStart..<i
            element.attributes.removeAll(keepingCapacity: true)
            element.isSelfClosing = false
            while i < end {
                while i < end, ByteScan.isSpace(bytes[i]) { i += 1 }
                guard i < end else { break }
                if bytes[i] == UInt8(ascii: ">") { i += 1; break }
                if bytes[i] == UInt8(ascii: "/") {
                    element.isSelfClosing = true
                    i += 1
                    continue
                }
                let attrStart = i
                while i < end, bytes[i] != UInt8(ascii: "="), !ByteScan.isSpace(bytes[i]), bytes[i] != UInt8(ascii: ">") { i += 1 }
                let attrName = attrStart..<i
                while i < end, ByteScan.isSpace(bytes[i]) { i += 1 }
                guard i < end, bytes[i] == UInt8(ascii: "=") else { continue }
                i += 1
                while i < end, ByteScan.isSpace(bytes[i]) { i += 1 }
                guard i < end else { break }
                let quote = bytes[i]
                guard quote == UInt8(ascii: "\"") || quote == UInt8(ascii: "'") else { continue }
                i += 1
                let valueStart = i
                let valueEnd = find(quote, from: i) ?? end
                element.attributes.append(Attribute(name: attrName, value: valueStart..<valueEnd))
                i = valueEnd + 1
            }
            // An unclosed value runs to the end; don't step past it.
            position = min(i, bytes.count)
            return .start
        }
        return nil
    }

    /// The text up to the next tag, unescaped. For `<metadata name="Title">…`.
    mutating func text() -> String {
        let start = min(position, bytes.count)
        let stop = find(UInt8(ascii: "<"), from: start) ?? bytes.count
        guard start < stop else {
            position = start
            return ""
        }
        position = stop
        return ByteScan.string(bytes, start..<stop).xmlUnescaped
    }

    func isElement(_ name: StaticString) -> Bool {
        ByteScan.localNameEquals(bytes, element.name, name)
    }

    func isName(_ range: Range<Int>, _ name: StaticString) -> Bool {
        ByteScan.localNameEquals(bytes, range, name)
    }

    /// The value range of an attribute, matched on its local name.
    func attribute(_ name: StaticString) -> Range<Int>? {
        for attribute in element.attributes where ByteScan.localNameEquals(bytes, attribute.name, name) {
            return attribute.value
        }
        return nil
    }

    func string(_ name: StaticString) -> String? {
        attribute(name).map { ByteScan.string(bytes, $0).xmlUnescaped }
    }

    func int(_ name: StaticString) -> Int? {
        attribute(name).flatMap { ByteScan.parseInt(bytes, $0) }
    }

    func float(_ name: StaticString) -> Float? {
        guard let range = attribute(name) else { return nil }
        var i = range.lowerBound
        return ByteScan.parseFloat(bytes, &i, end: range.upperBound)
    }

    private func find(_ byte: UInt8, from start: Int) -> Int? {
        guard start < bytes.count, let base = bytes.baseAddress else { return nil }
        guard let hit = memchr(base + start, Int32(byte), bytes.count - start) else { return nil }
        return base.distance(to: UnsafeRawPointer(hit))
    }

    private func findCommentEnd(from start: Int) -> Int? {
        var i = start
        while let dash = find(UInt8(ascii: "-"), from: i) {
            if dash + 2 < bytes.count, bytes[dash + 1] == UInt8(ascii: "-"), bytes[dash + 2] == UInt8(ascii: ">") {
                return dash + 2
            }
            i = dash + 1
        }
        return nil
    }
}
