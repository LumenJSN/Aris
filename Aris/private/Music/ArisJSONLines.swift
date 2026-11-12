//
//  ArisJSONLines.swift
//  Aris
//
//  Splits the now-playing adapter's output into JSON objects, one per line. Bytes arrive in arbitrary chunks; a line
//  ends at "\n" (a trailing "\r" is dropped), blank lines are skipped, and a line that isn't a JSON object counts as
//  bad. Three bad lines in a row mean the stream is broken: the reader stops and reports it.
//

import Foundation

struct ArisJSONLines {
    static let badLineLimit = 3

    private var pending = Data()
    private var badInARow = 0
    private(set) var isBroken = false

    /// Feeds a chunk; returns the objects of every line it completed. After the stream breaks, returns nothing.
    mutating func feed(_ chunk: Data) -> [[String: Any]] {
        guard !isBroken else { return [] }
        pending.append(chunk)
        var objects: [[String: Any]] = []
        while let end = pending.firstIndex(of: UInt8(ascii: "\n")) {
            var line = pending[pending.startIndex..<end]
            pending = Data(pending[pending.index(after: end)...])
            if line.last == UInt8(ascii: "\r") { line = line.dropLast() }
            if line.allSatisfy({ $0 == UInt8(ascii: " ") || $0 == UInt8(ascii: "\t") }) { continue }
            if let object = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any] {
                badInARow = 0
                objects.append(object)
            } else {
                badInARow += 1
                if badInARow >= Self.badLineLimit {
                    isBroken = true
                    pending.removeAll()
                    break
                }
            }
        }
        return objects
    }
}
