//
//  ArisAppleEvents.swift
//  Aris
//
//  Music and Spotify driven by raw Apple Events sent from the app itself: built as NSAppleEventDescriptors and sent
//  off the main thread with a timeout, never a script compiled (QA BUG-37: compiling loaded the OSA component under
//  the runtime's locks and froze Aris). Only the app's own sends carry its Automation grant and its sandbox's
//  apple-events exceptions: a child osascript got errAEPrivilegeError (-10004). Before the first send to an app its
//  permission is checked (AEDeterminePermissionToAutomateTarget, off the main thread, with a time limit); a read
//  never asks the user, a command they gave may. The builders and the reply readers are pure; the sender is a seam.
//

import CoreServices
import Foundation

struct ArisAppleEventError: LocalizedError, Equatable {
    let number: Int
    let message: String

    var errorDescription: String? { message }

    static let timeout = -1712
    static let notPermitted = -1743
    static let wouldAsk = -1744
    static let privilege = -10004
    static let notRunning = -600

    static func from(_ number: Int) -> ArisAppleEventError {
        let message = switch number {
        case notPermitted, privilege: "Aris isn't allowed to control this app (System Settings › Privacy & Security › Automation)."
        case wouldAsk: "Aris hasn't been allowed to control this app yet."
        case timeout: "The app didn't answer in time."
        case notRunning: "The app isn't running."
        default: "The app said no (\(number))."
        }
        return ArisAppleEventError(number: number, message: message)
    }

    var isPermission: Bool { [Self.notPermitted, Self.privilege, Self.wouldAsk].contains(number) }
}

/// One value out of a reply, as plain Swift.
enum ArisAEValue: Equatable, Sendable {
    case none
    case text(String)
    case number(Double)
    case enumerated(String)
    case data(Data)
}

enum ArisAppleEvents {
    static func code(_ text: String) -> FourCharCode {
        text.utf8.prefix(4).reduce(0) { ($0 << 8) | FourCharCode($1) }
    }

    static func text(_ code: FourCharCode) -> String {
        String(bytes: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }, encoding: .macOSRoman) ?? ""
    }

    /// A command with no arguments (`spfyPlay`, `hookPaus`): its suite and id, eight characters.
    static func command(_ suiteAndID: String, to bundle: String) -> NSAppleEventDescriptor {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundle)
        return NSAppleEventDescriptor(eventClass: code(String(suiteAndID.prefix(4))), eventID: code(String(suiteAndID.dropFirst(4))),
                                      targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID),
                                      transactionID: AETransactionID(kAnyTransactionID))
    }

    /// `get` a property path of the application: ["pTrk", "pnam"] is name of current track.
    static func get(_ path: [String], of bundle: String) -> NSAppleEventDescriptor {
        let event = command("coregetd", to: bundle)
        event.setParam(specifier(path), forKeyword: keyDirectObject)
        return event
    }

    /// `get` a property of the nth element of a property path: (["pTrk"], "cArt", 1, "pRaw") is raw data of artwork 1
    /// of current track.
    static func get(_ path: [String], element: String, index: Int, property: String, of bundle: String) -> NSAppleEventDescriptor {
        let event = command("coregetd", to: bundle)
        let item = objectSpecifier(want: code(element), form: code("indx"), data: NSAppleEventDescriptor(int32: Int32(index)), from: specifier(path))
        event.setParam(objectSpecifier(want: code("prop"), form: code("prop"), data: NSAppleEventDescriptor(typeCode: code(property)), from: item),
                       forKeyword: keyDirectObject)
        return event
    }

    /// The property path as nested object specifiers, from the application (the null container) in.
    static func specifier(_ path: [String]) -> NSAppleEventDescriptor {
        path.reduce(NSAppleEventDescriptor.null()) { container, property in
            objectSpecifier(want: code("prop"), form: code("prop"), data: NSAppleEventDescriptor(typeCode: code(property)), from: container)
        }
    }

    private static func objectSpecifier(want: FourCharCode, form: FourCharCode, data: NSAppleEventDescriptor,
                                        from container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: want), forKeyword: code("want"))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: form), forKeyword: code("form"))
        record.setDescriptor(data, forKeyword: code("seld"))
        record.setDescriptor(container, forKeyword: code("from"))
        return record.coerce(toDescriptorType: code("obj ")) ?? record
    }

    /// The reply's error, if it carries one.
    static func error(in reply: NSAppleEventDescriptor) -> ArisAppleEventError? {
        guard let number = reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value, number != 0 else { return nil }
        return ArisAppleEventError.from(Int(number))
    }

    /// The reply's direct value.
    static func value(of reply: NSAppleEventDescriptor) -> ArisAEValue {
        guard let result = reply.paramDescriptor(forKeyword: keyDirectObject) else { return .none }
        return value(result)
    }

    static func value(_ result: NSAppleEventDescriptor) -> ArisAEValue {
        switch result.descriptorType {
        case code("enum"): return .enumerated(text(result.enumCodeValue))
        case code("long"), code("shor"), code("doub"), code("sing"), code("comp"), code("magn"):
            return .number(result.doubleValue)
        case code("utxt"), code("TEXT"), code("utf8"): return .text(result.stringValue ?? "")
        case code("null"), code("msng"): return .none
        case code("tdta"), code("JPEG"), code("PNGf"), code("TIFF"), code("GIFf"), code("BMP "): return .data(result.data)
        default:
            if let text = result.coerce(toDescriptorType: code("utxt"))?.stringValue { return .text(text) }
            return .data(result.data)
        }
    }
}

/// Sends an event and waits for its reply (blocking; never on the main thread).
protocol ArisAppleEventSending: Sendable {
    /// AEDeterminePermissionToAutomateTarget's answer for `bundle` (asking the user only when `ask`).
    func permission(for bundle: String, ask: Bool) -> Int
    func send(_ event: NSAppleEventDescriptor, timeout: TimeInterval) throws -> NSAppleEventDescriptor
}

struct ArisLiveAppleEvents: ArisAppleEventSending {
    func permission(for bundle: String, ask: Bool) -> Int {
        guard let desc = NSAppleEventDescriptor(bundleIdentifier: bundle).aeDesc else { return ArisAppleEventError.notRunning }
        return Int(AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask))
    }

    func send(_ event: NSAppleEventDescriptor, timeout: TimeInterval) throws -> NSAppleEventDescriptor {
        do {
            return try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: timeout)
        } catch let error as NSError {
            throw ArisAppleEventError.from(error.code)
        }
    }
}

/// One app's events: sent in order on its own queue, after its permission is known.
final class ArisAppleEventClient: @unchecked Sendable {
    /// How long a send waits for the app's reply.
    static let sendTimeout: TimeInterval = 4
    /// How long the permission check may take before the send is given up (it can wait on the system).
    static let permissionTimeout: TimeInterval = 4
    /// How long the check may wait when it asks the user (the system's Automation question is on screen).
    static let askTimeout: TimeInterval = 60

    let bundle: String
    private let sender: ArisAppleEventSending
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var granted = false

    init(bundle: String, sender: ArisAppleEventSending = ArisLiveAppleEvents()) {
        self.bundle = bundle
        self.sender = sender
        queue = DispatchQueue(label: "com.lumenjsn.aris.apple-events.\(bundle)", qos: .userInitiated)
    }

    /// Builds the event (on the queue) and sends it; the reply read as `read` says. `ask`: a command the user gave, which
    /// may bring up the system's Automation question; a read never does.
    func send<Value: Sendable>(ask: Bool, _ build: @escaping @Sendable (String) -> NSAppleEventDescriptor,
                               read: @escaping @Sendable (NSAppleEventDescriptor) -> Value) async throws -> Value {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, Error>) in
            queue.async { [self] in
                do {
                    try checkPermission(ask: ask)
                    let reply = try sender.send(build(bundle), timeout: Self.sendTimeout)
                    if let error = ArisAppleEvents.error(in: reply) { throw error }
                    continuation.resume(returning: read(reply))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Once granted it stays so for this run; otherwise asked again each time (on another thread, with a limit).
    private func checkPermission(ask: Bool) throws {
        if lock.withLock({ granted }) { return }
        let answer = Self.bounded(ask ? Self.askTimeout : Self.permissionTimeout) { [sender, bundle] in sender.permission(for: bundle, ask: ask) }
        guard let answer else { throw ArisAppleEventError.from(ArisAppleEventError.timeout) }
        guard answer == 0 else { throw ArisAppleEventError.from(answer) }
        lock.withLock { granted = true }
    }

    /// `work` on another thread, given up (nil) after `limit`.
    static func bounded(_ limit: TimeInterval, _ work: @escaping @Sendable () -> Int) -> Int? {
        final class Box: @unchecked Sendable { var value: Int? }
        let box = Box(), done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            box.value = work()
            done.signal()
        }
        return done.wait(timeout: .now() + limit) == .success ? box.value : nil
    }
}
