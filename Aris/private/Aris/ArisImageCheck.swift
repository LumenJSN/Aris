//
//  ArisImageCheck.swift
//  Aris (also built into aris-agent)
//
//  Whether PNG or JPEG bytes are a whole image, read from their structure: ImageIO alone takes a truncated or
//  damaged file and fills the gap with grey, and neither Codex nor Claude refuses one (P1.0), so this is what
//  stops bad bytes reaching a brain. Nothing is decoded. Pure, so the tests run it.
//

import Foundation

enum ArisImageCheck {
    /// The pixel size a whole PNG declares: the signature, IHDR first, every chunk inside the bytes with a correct
    /// CRC, at least one IDAT, and IEND ending the file exactly. Nil for anything else.
    static func png(_ data: Data) -> (width: Int, height: Int)? {
        data.withUnsafeBytes { raw -> (Int, Int)? in
            let bytes = raw.bindMemory(to: UInt8.self)
            guard bytes.count >= 8 + 25 + 12, Array(bytes.prefix(8)) == pngSignature else { return nil }
            var offset = 8, size: (Int, Int)?, sawData = false, chunks = 0
            while offset + 12 <= bytes.count, chunks < maxChunks {
                chunks += 1
                let length = Int(be32(bytes, offset))
                guard length <= bytes.count - offset - 12 else { return nil }
                let type = Array(bytes[(offset + 4)..<(offset + 8)])
                let end = offset + 8 + length
                guard crc32(bytes, from: offset + 4, to: end) == be32(bytes, end) else { return nil }
                switch type {
                case ihdr:
                    guard size == nil, offset == 8, length == 13 else { return nil }
                    size = (Int(be32(bytes, offset + 8)), Int(be32(bytes, offset + 12)))
                case idat:
                    guard size != nil else { return nil }
                    sawData = true
                case iend:
                    guard let size, sawData, length == 0, end + 4 == bytes.count, size.0 > 0, size.1 > 0 else { return nil }
                    return size
                default:
                    guard size != nil else { return nil }
                }
                offset = end + 4
            }
            return nil
        }
    }

    /// The pixel size a whole JPEG declares: SOI, marker segments inside the bytes up to the scan, a frame header
    /// (SOFn) before it, and EOI as the last two bytes. Nil for anything else.
    static func jpeg(_ data: Data) -> (width: Int, height: Int)? {
        data.withUnsafeBytes { raw -> (Int, Int)? in
            let bytes = raw.bindMemory(to: UInt8.self)
            let count = bytes.count
            guard count >= 4, bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[count - 2] == 0xFF, bytes[count - 1] == 0xD9 else { return nil }
            var offset = 2, size: (Int, Int)?, segments = 0
            while offset + 4 <= count, segments < maxChunks {
                segments += 1
                guard bytes[offset] == 0xFF else { return nil }
                var marker = bytes[offset + 1]
                // Fill bytes before a marker.
                while marker == 0xFF, offset + 2 < count {
                    offset += 1
                    marker = bytes[offset + 1]
                }
                // Markers with no length.
                if marker == 0x01 || (0xD0...0xD7).contains(marker) {
                    offset += 2
                    continue
                }
                guard marker != 0xD8, marker != 0xD9, offset + 4 <= count else { return nil }
                let length = Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
                guard length >= 2, offset + 2 + length <= count - 2 else { return nil }
                if marker == 0xDA {
                    guard let size, size.0 > 0, size.1 > 0 else { return nil }
                    return size
                }
                if (0xC0...0xCF).contains(marker), ![0xC4, 0xC8, 0xCC].contains(marker) {
                    guard length >= 8 else { return nil }
                    size = (Int(bytes[offset + 7]) << 8 | Int(bytes[offset + 8]), Int(bytes[offset + 5]) << 8 | Int(bytes[offset + 6]))
                }
                offset += 2 + length
            }
            return nil
        }
    }

    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    private static let ihdr = Array("IHDR".utf8), idat = Array("IDAT".utf8), iend = Array("IEND".utf8)
    /// More chunks or segments than any real screenshot has.
    private static let maxChunks = 100_000

    private static func be32(_ bytes: UnsafeBufferPointer<UInt8>, _ at: Int) -> UInt32 {
        UInt32(bytes[at]) << 24 | UInt32(bytes[at + 1]) << 16 | UInt32(bytes[at + 2]) << 8 | UInt32(bytes[at + 3])
    }

    private static let crcTable: [UInt32] = (0..<256).map { n in
        (0..<8).reduce(UInt32(n)) { c, _ in c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
    }

    /// CRC-32 (ISO 3309, as PNG uses) of `bytes[from..<to]`.
    private static func crc32(_ bytes: UnsafeBufferPointer<UInt8>, from: Int, to: Int) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        crcTable.withUnsafeBufferPointer { table in
            for i in from..<to { crc = table[Int((crc ^ UInt32(bytes[i])) & 0xFF)] ^ (crc >> 8) }
        }
        return crc ^ 0xFFFF_FFFF
    }
}
