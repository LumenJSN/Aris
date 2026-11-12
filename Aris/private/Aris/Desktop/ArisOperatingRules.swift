//
//  ArisOperatingRules.swift
//  Aris
//
//  When the "working on this window" overlay shows, where, and what the notch says (the owner: "당연히 그 애들 위에
//  띄워놔야지"). Each desktop call the agent streams (ArisAgentReply.operating) shows it on that window; it comes down
//  once calls stop for a few seconds or the answer comes, and whenever the window is gone, minimised or on another
//  Space. Its frame follows the window in AppKit coordinates, on whichever display the window is. Pure.
//

import CoreGraphics
import Foundation

struct ArisOperatingState: Equatable {
    /// One window being worked in, and when it was last heard of.
    private struct Work: Equatable {
        let target: ArisOperatingTarget
        let heard: Date
    }

    /// Who works where: the conversation's turn (nil) and each background job by its id (audit imp-5: with one slot
    /// for all of them, a job that ended took down the overlay of another job still at work).
    private var work: [UUID?: Work] = [:]

    /// Calls this far apart still count as one stretch of work (a card waiting for the user says it again when they answers).
    static let idle: TimeInterval = 8

    /// A desktop call is under way in this window, for `owner` (a job's id; nil: the turn).
    mutating func heard(_ target: ArisOperatingTarget, at now: Date, owner: UUID? = nil) {
        work[owner] = Work(target: target, heard: now)
    }

    /// `owner`'s answer came (or it failed or was stopped): its window's overlay is down at once, nobody else's.
    mutating func finished(owner: UUID? = nil) {
        work[owner] = nil
    }

    /// The window to mark: the one most lately worked in, while that work is fresh.
    func current(at now: Date) -> ArisOperatingTarget? {
        work.values.filter { now.timeIntervalSince($0.heard) < Self.idle }.max { $0.heard < $1.heard }?.target
    }
}

enum ArisOperatingPlacement {
    /// The overlay's AppKit frame for a window's CG frame (top-left origin of the primary display, y down): the same
    /// rectangle, flipped against the primary display's height, so it lands on any display the window is on. Nil for
    /// a window too small to be a real one.
    static func frame(windowCG: CGRect, primaryHeight: CGFloat) -> CGRect? {
        guard windowCG.width >= ArisWindowLocator.minimumSide, windowCG.height >= ArisWindowLocator.minimumSide else { return nil }
        return ArisPerchGeometry.toAppKit(windowCG, primaryHeight: primaryHeight)
    }

    /// Where the overlay goes: the window the agent named when it still belongs to the pid and is on screen, else the
    /// pid's front window. `named` and `front` read CGWindowList (ArisWindowLocator).
    static func window(for target: ArisOperatingTarget, named: (Int32, Int) -> CGRect?, front: (Int32) -> (number: Int, frame: CGRect)?)
        -> (number: Int, frame: CGRect)? {
        if let number = target.window, let frame = named(target.pid, number) { return (number, frame) }
        return front(target.pid)
    }
}
