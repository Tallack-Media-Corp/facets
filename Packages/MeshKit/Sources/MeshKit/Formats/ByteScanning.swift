import Foundation

/// Byte-level helpers shared by the text formats (ASCII STL and 3MF XML). They work on
/// raw buffers so a 100 MB file is read without building a String per number.
enum ByteScan {
    static func isSpace(_ b: UInt8) -> Bool {
        b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D
    }

    /// Parses a decimal float starting at `i`, advancing past it. Handles sign,
    /// fraction and exponent; returns nil if there's no number there.
    static func parseFloat(_ p: UnsafeRawBufferPointer, _ i: inout Int, end: Int) -> Float? {
        var j = i
        while j < end, isSpace(p[j]) { j += 1 }
        guard j < end else { return nil }
        var negative = false
        if p[j] == UInt8(ascii: "-") { negative = true; j += 1 } else if p[j] == UInt8(ascii: "+") { j += 1 }

        var mantissa: UInt64 = 0
        var exponent = 0
        var digits = 0
        var sawDigit = false
        while j < end, p[j] >= 0x30, p[j] <= 0x39 {
            if digits < 18 { mantissa = mantissa * 10 + UInt64(p[j] - 0x30); digits += 1 } else { exponent += 1 }
            sawDigit = true
            j += 1
        }
        if j < end, p[j] == UInt8(ascii: ".") {
            j += 1
            while j < end, p[j] >= 0x30, p[j] <= 0x39 {
                if digits < 18 { mantissa = mantissa * 10 + UInt64(p[j] - 0x30); digits += 1; exponent -= 1 }
                sawDigit = true
                j += 1
            }
        }
        guard sawDigit else {
            // "nan" / "inf" appear in broken exports; read them so the caller can skip.
            return nil
        }
        if j < end, p[j] == UInt8(ascii: "e") || p[j] == UInt8(ascii: "E") {
            var k = j + 1
            var expNegative = false
            if k < end, p[k] == UInt8(ascii: "-") { expNegative = true; k += 1 } else if k < end, p[k] == UInt8(ascii: "+") { k += 1 }
            var e = 0
            var sawExp = false
            while k < end, p[k] >= 0x30, p[k] <= 0x39 {
                if e < 10_000 { e = e * 10 + Int(p[k] - 0x30) }
                sawExp = true
                k += 1
            }
            if sawExp {
                exponent += expNegative ? -e : e
                j = k
            }
        }
        i = j
        var value = Double(mantissa)
        if exponent != 0 {
            value *= pow(10, Double(exponent))
        }
        return Float(negative ? -value : value)
    }

    static func parseInt(_ p: UnsafeRawBufferPointer, _ range: Range<Int>) -> Int? {
        var j = range.lowerBound
        let end = range.upperBound
        while j < end, isSpace(p[j]) { j += 1 }
        var negative = false
        if j < end, p[j] == UInt8(ascii: "-") { negative = true; j += 1 }
        var value = 0
        var saw = false
        while j < end, p[j] >= 0x30, p[j] <= 0x39 {
            value = value &* 10 &+ Int(p[j] - 0x30)
            saw = true
            j += 1
        }
        return saw ? (negative ? -value : value) : nil
    }

    static func string(_ p: UnsafeRawBufferPointer, _ range: Range<Int>) -> String {
        String(decoding: UnsafeRawBufferPointer(rebasing: p[range]), as: UTF8.self)
    }

    /// True if the bytes in `range` equal `literal`.
    static func equals(_ p: UnsafeRawBufferPointer, _ range: Range<Int>, _ literal: StaticString) -> Bool {
        guard range.count == literal.utf8CodeUnitCount else { return false }
        let lit = literal.utf8Start
        for k in 0..<range.count where p[range.lowerBound + k] != lit[k] {
            return false
        }
        return true
    }

    /// Like `equals`, but ignores a namespace prefix ("p:path" matches "path").
    static func localNameEquals(_ p: UnsafeRawBufferPointer, _ range: Range<Int>, _ literal: StaticString) -> Bool {
        var start = range.lowerBound
        for k in range where p[k] == UInt8(ascii: ":") { start = k + 1 }
        return equals(p, start..<range.upperBound, literal)
    }
}

extension String {
    /// Decodes the five XML entities and numeric references. Names in 3MF files are
    /// often double-escaped by slicers; one pass is what the format promises.
    var xmlUnescaped: String {
        guard contains("&") else { return self }
        var out = ""
        out.reserveCapacity(count)
        var rest = self[...]
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            guard let semi = rest[amp...].firstIndex(of: ";"), rest.distance(from: amp, to: semi) <= 10 else {
                out += "&"
                rest = rest[rest.index(after: amp)...]
                continue
            }
            let entity = rest[rest.index(after: amp)..<semi]
            switch entity {
            case "amp": out += "&"
            case "lt": out += "<"
            case "gt": out += ">"
            case "quot": out += "\""
            case "apos": out += "'"
            default:
                if entity.hasPrefix("#x"), let code = UInt32(entity.dropFirst(2), radix: 16), let scalar = Unicode.Scalar(code) {
                    out.unicodeScalars.append(scalar)
                } else if entity.hasPrefix("#"), let code = UInt32(entity.dropFirst()), let scalar = Unicode.Scalar(code) {
                    out.unicodeScalars.append(scalar)
                } else {
                    out += rest[amp...semi]
                }
            }
            rest = rest[rest.index(after: semi)...]
        }
        out += rest
        return out
    }
}
