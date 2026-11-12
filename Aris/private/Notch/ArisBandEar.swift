//
//  ArisBandEar.swift
//  Aris
//
//  What the closed star band's right ear shows, as one rule (the views are ArisActivity's trailing slot): the files
//  given to Aris that wait for the next request were counted there only while the star rested, so with an answer
//  parked the band showed the star and the answer's blue dot and no paperclip (the second upgrade VM run, B12 and
//  bug 4). Now the paperclip and its count show whenever files wait, and the parked answer's dot (or the paused
//  listening mark) rides on the count's corner, so both are read in the one ear the band has: the ear is about 40 to
//  50 points wide and the count with its 14-point inset already takes 46, so a dot beside it would sit under the
//  camera housing. Foundation only (tested).
//

import Foundation

enum ArisBandEar {
    /// A mark that rides on the count's corner.
    enum Badge: Equatable {
        /// An answer waits (blue), or the turn failed (red): the dot the ear shows without files.
        case dot
        /// Listening waits while another app plays or records.
        case paused
    }

    enum Shows: Equatable {
        /// Aris keeps listening by itself: the lock, a press ends it (the files wait in the open notch).
        case lock
        /// A paperclip and count, with the turn's own mark on its corner when there is one.
        case files(count: Int, badge: Badge?)
        /// A turn's or a parked answer's ear as before: its dot or pause mark, and the muted mark.
        case answer
        /// The resting star's ear: the muted mark, or nothing.
        case rest
    }

    /// `resting`: the star rests (nothing asked, nothing parked). `answerDot`: the ear would show the waiting answer's
    /// (or a failure's) dot. The muted mark gives way to the count, as it did at rest.
    static func shows(resting: Bool, files: Int, handsFreeLock: Bool, answerDot: Bool, paused: Bool) -> Shows {
        if handsFreeLock, !resting { return .lock }
        if files > 0 { return .files(count: files, badge: resting ? nil : paused ? .paused : answerDot ? .dot : nil) }
        return resting ? .rest : .answer
    }

    /// The badge's size and how far its centre sits in from the count capsule's top-right corner.
    static let badgeSize: CGFloat = 7
    static let badgeInset: CGFloat = 1
}
