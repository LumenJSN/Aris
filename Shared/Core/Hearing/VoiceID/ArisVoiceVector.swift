//
//  ArisVoiceVector.swift
//  Shared/Core (app, tests)
//
//  The arithmetic of a voice vector (F1, the owner's voice): the speaker-embedding model turns an utterance into 256
//  numbers, and two utterances of the same person point the same way. Unit length, the cosine between two, and the
//  mean of several. Pure.
//

import Foundation

enum ArisVoiceVector {
    /// The vector at unit length; nil when it has no length or holds a number that isn't finite.
    static func normalized(_ vector: [Float]) -> [Float]? {
        guard !vector.isEmpty, vector.allSatisfy(\.isFinite) else { return nil }
        let length = vector.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        guard length > 1e-6 else { return nil }
        return vector.map { $0 / length }
    }

    /// How much two vectors point the same way, -1...1; nil when either has no direction or their sizes differ.
    static func cosine(_ a: [Float], _ b: [Float]) -> Float? {
        guard a.count == b.count, let a = normalized(a), let b = normalized(b) else { return nil }
        let dot = zip(a, b).reduce(Float(0)) { $0 + $1.0 * $1.1 }
        return min(1, max(-1, dot))
    }

    /// The direction of several vectors together (each counted at unit length); nil when none has a direction or
    /// their sizes differ.
    static func mean(_ vectors: [[Float]]) -> [Float]? {
        let units = vectors.compactMap(normalized)
        guard let first = units.first, units.count == vectors.count, units.allSatisfy({ $0.count == first.count }) else { return nil }
        var sum = [Float](repeating: 0, count: first.count)
        for unit in units { for index in sum.indices { sum[index] += unit[index] } }
        return normalized(sum)
    }

    /// `old` moved towards `new` by `weight` (0...1), at unit length.
    static func blended(_ old: [Float], _ new: [Float], weight: Float) -> [Float]? {
        guard old.count == new.count, let old = normalized(old), let new = normalized(new) else { return nil }
        let w = min(1, max(0, weight))
        return normalized(zip(old, new).map { $0 * (1 - w) + $1 * w })
    }
}
