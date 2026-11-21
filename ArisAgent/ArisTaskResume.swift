//
//  ArisTaskResume.swift
//  aris-agent
//
//  The brains whose job can be reopened after the helper restarted (ArisTaskRecoveryLive): their handle for it, which
//  the journal keeps, and how the next start reopens it. Codex's turn can be stopped too (turn/interrupt).
//

import Foundation

protocol ArisResumableDriver: AnyObject {
    /// The handle a job's journal keeps (nil for a process that keeps none).
    var sessionHandle: String? { get }
    /// The next start reopens `handle` instead of starting a new conversation.
    func resume(from handle: String)
}

extension ArisClaudeDriver: ArisResumableDriver {
    var sessionHandle: String? { keepsSession ? session : nil }
    func resume(from handle: String) { resumeSession = handle }
}

extension ArisCodexDriver: ArisResumableDriver, ArisInterruptibleDriver {
    var sessionHandle: String? { keepsThread ? threadHandle : nil }
    func resume(from handle: String) { resumeThread = handle }
}
