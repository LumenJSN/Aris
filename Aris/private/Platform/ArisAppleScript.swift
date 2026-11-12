//
//  ArisAppleScript.swift
//  Aris
//
//  Runs AppleScript out of process: /usr/bin/osascript as a child, ended at a hard time limit (QA BUG-37). It is never
//  compiled in the app (NSAppleScript, OSAKit): there OSACompile asks SystemPolicy's script scanner over XPC, and that
//  lookup blocked forever while the load of the AppleScript component held the runtime's locks, so the main thread
//  froze on its next protocol-conformance lookup and Aris hung whole. A child that hangs is killed; Aris goes on.
//  A script returns text (several values joined by `separator`); a script error is thrown with osascript's message.
//  The script goes in as -e lines of ASCII (bundle ids, validated ids): Foundation passes arguments decomposed (NFD).
//

import Foundation

struct ArisAppleScriptError: LocalizedError, Equatable {
    let message: String
    let number: Int?

    var errorDescription: String? { message }

    static let timedOut = ArisAppleScriptError(message: "The script took too long and was stopped.", number: nil)
    static let cancelled = ArisAppleScriptError(message: "The script was cancelled.", number: nil)
}

enum ArisAppleScript {
    static let executable = "/usr/bin/osascript"
    /// How long a script may run before its osascript is killed.
    static let timeLimit: TimeInterval = 8
    /// What is read of its output at most (a track's artwork as hex runs to a few MB).
    static let outputLimit = 24 << 20
    /// Joins the values a script returns as one text: `character id 31` in the script.
    static let separator = "\u{1F}"
    /// The script's way of writing `separator`.
    static let separatorInScript = "(character id 31)"

    /// Runs `source` in osascript and returns what it printed (its result as text, without the last newline). Thrown:
    /// the script's error, `timedOut` (the child killed), or `cancelled` (the task was, and the child with it).
    static func run(_ source: String, timeout: TimeInterval = timeLimit) async throws -> String {
        let child = ArisScriptChild()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(with: child.run(arguments(for: source), timeout: timeout))
                }
            }
        } onCancel: {
            child.stop()
        }
    }

    /// osascript's arguments: one -e per line of the script.
    static func arguments(for source: String) -> [String] {
        source.split(separator: "\n", omittingEmptySubsequences: false).flatMap { ["-e", String($0)] }
    }

    // MARK: - What osascript prints

    /// The values of a result joined by `separator`.
    static func fields(_ printed: String) -> [String] {
        printed.components(separatedBy: separator)
    }

    /// A number AppleScript wrote as text (a decimal comma in some locales).
    static func number(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    /// Raw data as osascript prints it: «data JPEG FFD8…» (any four-character type, then hex).
    static func data(_ printed: String) -> Data? {
        let text = printed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("«data "), text.hasSuffix("»") else { return nil }
        let hex = text.dropFirst("«data ".count + 4).dropLast()
        guard !hex.isEmpty, hex.count.isMultiple(of: 2) else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }

    /// osascript's complaint ("0:52: execution error: Music got an error: … (-1728)") as the script's error.
    static func error(from complaint: String) -> ArisAppleScriptError {
        let line = complaint.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        var message = line
        if let range = message.range(of: "execution error: ") { message = String(message[range.upperBound...]) }
        var number: Int?
        if let open = message.range(of: " (", options: .backwards), message.hasSuffix(")"),
           let code = Int(message[open.upperBound..<message.index(before: message.endIndex)]) {
            number = code
            message = String(message[..<open.lowerBound])
        }
        message = message.trimmingCharacters(in: .whitespaces)
        return ArisAppleScriptError(message: message.isEmpty ? "The script failed." : message, number: number)
    }
}

/// One osascript run: started, read, and ended at its time limit or on cancel, whichever comes first.
final class ArisScriptChild: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var stopped = false

    /// Ends the child now (the task was cancelled).
    func stop() {
        lock.lock()
        stopped = true
        let running = process
        lock.unlock()
        if let running { Self.end(running) }
    }

    /// Blocks until osascript ends or is killed.
    func run(_ arguments: [String], timeout: TimeInterval) -> Result<String, Error> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ArisAppleScript.executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let ended = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in ended.signal() }
        lock.lock()
        guard !stopped else { lock.unlock(); return .failure(ArisAppleScriptError.cancelled) }
        self.process = process
        lock.unlock()
        do { try process.run() } catch {
            return .failure(ArisAppleScriptError(message: "osascript could not start: \(error.localizedDescription)", number: nil))
        }
        let printed = ArisPipeDrain(output.fileHandleForReading, limit: ArisAppleScript.outputLimit)
        let complaint = ArisPipeDrain(errors.fileHandleForReading, limit: 64 << 10)
        if ended.wait(timeout: .now() + timeout) == .timedOut {
            Self.end(process)
            _ = ended.wait(timeout: .now() + 2)
            return .failure(ArisAppleScriptError.timedOut)
        }
        lock.lock()
        let cancelled = stopped
        lock.unlock()
        if cancelled { return .failure(ArisAppleScriptError.cancelled) }
        let out = String(decoding: printed.wait(), as: UTF8.self)
        let err = String(decoding: complaint.wait(), as: UTF8.self)
        guard process.terminationStatus == 0 else { return .failure(ArisAppleScript.error(from: err)) }
        return .success(out.hasSuffix("\n") ? String(out.dropLast()) : out)
    }

    /// SIGTERM, then SIGKILL a moment later if it is still there.
    private static func end(_ process: Process) {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }
}

/// Reads a pipe to its end on its own thread (so a big output never stalls the child), keeping at most `limit` bytes.
final class ArisPipeDrain: @unchecked Sendable {
    private let done = DispatchSemaphore(value: 0)
    private var data = Data()

    init(_ handle: FileHandle, limit: Int) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                if data.count < limit { data.append(chunk.prefix(limit - data.count)) }
            }
            try? handle.close()
            done.signal()
        }
    }

    /// What was read, once the pipe ended (or after 2 s, what there is).
    func wait() -> Data {
        _ = done.wait(timeout: .now() + 2)
        return data
    }
}
