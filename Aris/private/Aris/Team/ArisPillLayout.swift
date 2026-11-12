//
//  ArisPillLayout.swift
//  Aris
//
//  The user's P1 pill (mockups/7-character.html, A6 · P1) in one line, the user's B (mockups/pill-oneline.html): the face slot in
//  a left column, the text centred, the elapsed time in a right column. Both columns are as wide as the wider one, so
//  the text sits on the notch's centre line whatever the sides hold. 30 tall like the dictation pill, 10 in, 10 between
//  columns, at least 168 wide; a longer line makes it wider, never taller.
//  The face slot holds one face: Aris's star when the job is Aris's own, else the teammate who works (never both);
//  with two jobs or more, small faces overlapped and "+N".
//

import CoreGraphics
import Foundation

/// Someone working on a live job, oldest job first: Aris itself (its star) or a teammate.
struct ArisPillWorker: Equatable {
    let id: UUID
    let aris: Bool
}

/// Who sits in the pill's face slot.
enum ArisPillFace: Hashable {
    /// Aris's one star (ArisStarStage drops it into this seat).
    case star
    /// A teammate's face, by its job's id.
    case mate(UUID)
}

/// What the face slot shows: one face, or (two jobs or more) up to two small ones and how many more jobs run.
struct ArisPillFaces: Equatable {
    let faces: [ArisPillFace]
    let more: Int
    let small: Bool

    var holdsStar: Bool { faces.contains(.star) }
}

enum ArisPillLayout {
    static let height: CGFloat = 30
    static let padding: CGFloat = 10
    static let gap: CGFloat = 10
    static let minWidth: CGFloat = 168

    /// The face alone (mockup `.face`, 22) and the small ones (`.stack .face`, 18, the next 5 under the first).
    static let faceSize: CGFloat = 22
    static let smallFaceSize: CGFloat = 18
    static let faceOverlap: CGFloat = 5
    static let stackShown = 2
    /// Between the small faces and "+N".
    static let plusGap: CGFloat = 3

    /// The face slot for `workers` (the live jobs' workers, oldest first). Aris is one star however many of its jobs
    /// run. No live job (끝났어요) is the star's.
    static func faces(_ workers: [ArisPillWorker]) -> ArisPillFaces {
        let firstAris = workers.firstIndex { $0.aris }
        let all: [ArisPillFace] = workers.indices.compactMap { i in
            workers[i].aris ? (i == firstAris ? .star : nil) : .mate(workers[i].id)
        }
        guard workers.count >= 2 else { return ArisPillFaces(faces: [all.first ?? .star], more: 0, small: false) }
        let shown = Array(all.prefix(stackShown))
        return ArisPillFaces(faces: shown, more: workers.count - shown.count, small: true)
    }

    /// The faces' width, without "+N".
    static func faceWidth(count: Int, small: Bool) -> CGFloat {
        guard small else { return faceSize }
        return smallFaceSize + CGFloat(max(0, count - 1)) * (smallFaceSize - faceOverlap)
    }

    /// Each side column: as wide as the wider side, and wider still while the pill is under its minimum.
    static func side(left: CGFloat, center: CGFloat, right: CGFloat) -> CGFloat {
        max(left, right, (minWidth - 2 * padding - 2 * gap - center) / 2)
    }

    static func width(left: CGFloat, center: CGFloat, right: CGFloat) -> CGFloat {
        2 * padding + 2 * side(left: left, center: center, right: right) + 2 * gap + center
    }

    /// Where the text's centre falls, from the pill's leading edge.
    static func centerX(left: CGFloat, center: CGFloat, right: CGFloat) -> CGFloat {
        padding + side(left: left, center: center, right: right) + gap + center / 2
    }

    /// "0:42", "10:05", "1:02:03".
    static func elapsed(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let (h, m, s) = (total / 3_600, total % 3_600 / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
