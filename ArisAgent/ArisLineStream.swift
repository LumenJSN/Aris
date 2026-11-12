//
//  ArisLineStream.swift
//  aris-agent
//
//  Newline-separated logs read a chunk at a time, so the cost scan holds one chunk plus the line in progress,
//  never a whole transcript (Claude's run to hundreds of MB; reading them whole kept the agent near 1.7 GB).
//

import Foundation

enum ArisLineStream {
    static let defaultChunk = 1 << 20

    /// Calls `body` with each newline-terminated line (without its newline) that `read` yields, inside an
    /// autorelease pool per chunk. With `flushTail`, an unterminated last line counts too. Returns the bytes up to and
    /// including the last line delivered, so a caller can resume after it.
    @discardableResult
    static func forEachLine(chunk: Int = defaultChunk, flushTail: Bool = false,
                            read: (UnsafeMutableRawPointer, Int) -> Int,
                            _ body: (UnsafeRawBufferPointer) -> Void) -> Int {
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: chunk, alignment: 1)
        defer { buffer.deallocate() }
        var carry = Data()
        var total = 0, consumed = 0
        while true {
            let count = read(buffer, chunk)
            guard count > 0 else { break }
            autoreleasepool {
                var start = 0
                while start < count, let newline = memchr(buffer + start, 0x0A, count - start) {
                    let end = buffer.distance(to: newline)
                    if carry.isEmpty {
                        body(UnsafeRawBufferPointer(start: buffer + start, count: end - start))
                    } else {
                        carry.append(buffer.advanced(by: start).assumingMemoryBound(to: UInt8.self), count: end - start)
                        carry.withUnsafeBytes(body)
                        carry = Data()
                    }
                    start = end + 1
                    consumed = total + start
                }
                if start < count { carry.append(buffer.advanced(by: start).assumingMemoryBound(to: UInt8.self), count: count - start) }
            }
            total += count
        }
        if flushTail, !carry.isEmpty {
            autoreleasepool { carry.withUnsafeBytes(body) }
            consumed = total
        }
        return consumed
    }

    /// The lines of a file from `offset`; the bytes consumed, or nil when it can't be opened.
    static func forEachLine(inFile url: URL, from offset: UInt64, flushTail: Bool = false,
                            _ body: (UnsafeRawBufferPointer) -> Void) -> Int? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: offset)) != nil else { return nil }
        return forEachLine(flushTail: flushTail, read: reader(handle.fileDescriptor), body)
    }

    /// The lines a command prints (the last one even without a newline); false when it fails or runs past `timeout`.
    static func forEachLine(ofCommand path: String, _ arguments: [String], timeout: TimeInterval,
                            _ body: (UnsafeRawBufferPointer) -> Void) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        guard (try? ArisChildren.run(process)) != nil else { return false }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { ArisProcessEnd.end(process) }
        forEachLine(flushTail: true, read: reader(out.fileHandleForReading.fileDescriptor), body)
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    static func contains(_ line: UnsafeRawBufferPointer, _ needle: StaticString) -> Bool {
        guard let base = line.baseAddress, line.count >= needle.utf8CodeUnitCount else { return false }
        return memmem(base, line.count, needle.utf8Start, needle.utf8CodeUnitCount) != nil
    }

    private static func reader(_ fd: Int32) -> (UnsafeMutableRawPointer, Int) -> Int {
        { buffer, count in
            while true {
                let got = Darwin.read(fd, buffer, count)
                if got >= 0 || errno != EINTR { return got }
            }
        }
    }
}
