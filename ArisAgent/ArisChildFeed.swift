//
//  ArisChildFeed.swift
//  aris-agent
//
//  Handing a helper child its input and reading its answer, without ever staking the agent on the child (audit desk-7:
//  click-at wrote a multi-megabyte screenshot to the vision child's stdin with a blocking write before it started
//  reading: a child that exited first killed aris-agent with SIGPIPE, mid-turn; one that stalled hung the write for
//  good, since the time limit only covered the read that came after). Here the write end never raises SIGPIPE (a closed
//  pipe is an error the write returns), the answer is read from the start (a child that prints while it still reads
//  can't block both sides), the write runs on its own queue, and one time limit covers all of it: past it the child
//  is ended, which also frees a write still waiting on it.
//

import Darwin
import Foundation

enum ArisChildFeed {
    /// How long a write freed by ending the child is waited for before giving up on it.
    static let writeGrace: TimeInterval = 2

    /// Writes `input` to a started child's stdin on a queue of its own, so the caller's reader and time limit are already
    /// running while it goes: a child that stalls without reading can't hold its caller for good (ending the child at
    /// the time limit frees the write), and one that is gone is an error the write returns, never SIGPIPE.
    /// `closing`: the child sees the end of its input once all of it is written (a child that takes one question and
    /// answers); false for one that keeps its stdin open (agy's stream).
    static func feed(_ input: Data, to writer: FileHandle, closing: Bool) {
        let descriptor = writer.fileDescriptor
        _ = fcntl(descriptor, F_SETNOSIGPIPE, 1)
        DispatchQueue.global(qos: .userInitiated).async {
            input.withUnsafeBytes { buffer in
                guard let base = buffer.baseAddress else { return }
                var offset = 0
                while offset < buffer.count {
                    let count = Darwin.write(descriptor, base + offset, buffer.count - offset)
                    if count > 0 { offset += count } else if count < 0, errno == EINTR { continue } else { break }
                }
            }
            if closing { try? writer.close() }
        }
    }

    /// Starts `process` (its stdin and stdout are set here), writes `input` to it and returns everything it printed.
    /// Nil when it couldn't start or hadn't finished printing within `timeout`: it is ended then.
    static func exchange(_ process: Process, input: Data, timeout: TimeInterval) -> Data? {
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        let writer = stdin.fileHandleForWriting
        let descriptor = writer.fileDescriptor
        // A write to a child that is gone fails with EPIPE; it never signals this process.
        _ = fcntl(descriptor, F_SETNOSIGPIPE, 1)
        do { try ArisChildren.run(process) } catch { return nil }
        let printed = ArisChildOutput()
        let read = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            printed.set(stdout.fileHandleForReading.readDataToEndOfFile())
            read.signal()
        }
        let wrote = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            input.withUnsafeBytes { buffer in
                guard let base = buffer.baseAddress else { return }
                var offset = 0
                while offset < buffer.count {
                    let count = Darwin.write(descriptor, base + offset, buffer.count - offset)
                    if count > 0 { offset += count } else if count < 0, errno == EINTR { continue } else { break }
                }
            }
            // The child sees the end of its input (or is already gone).
            try? writer.close()
            wrote.signal()
        }
        let finished = read.wait(timeout: .now() + timeout) == .success
        if process.isRunning { ArisProcessEnd.end(process) }
        _ = wrote.wait(timeout: .now() + writeGrace)
        return finished ? printed.value : nil
    }
}

/// The child's output, handed from the reading queue.
private final class ArisChildOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = Data()
    func set(_ data: Data) { lock.withLock { stored = data } }
    var value: Data { lock.withLock { stored } }
}
