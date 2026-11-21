//
//  ArisSkillArchive.swift
//  aris-agent
//
//  A GitHub tarball (tar.gz) read by Aris itself, never by git or tar: no hooks, no submodules, nothing run. Inflating
//  stops at a byte cap (a small download can't become a huge folder), and only plain files and folders come out:
//  links, devices and anything whose path is absolute, holds "..", or is too deep or too long are refused. Pure (the
//  Compression library and the bytes), so the tests feed it archives of their own.
//

import Compression
import Foundation

struct ArisArchiveEntry: Equatable {
    /// Relative, "/"-separated, without the archive's top folder.
    let path: String
    let data: Data
}

enum ArisArchiveProblem: Error, Equatable {
    case notGzip
    case corrupt
    case tooBig
    case tooMany
    case unsafePath(String)
    case link(String)

    var message: String {
        switch self {
        case .notGzip, .corrupt: return "받은 파일이 올바른 압축 파일이 아니에요."
        case .tooBig: return "압축을 풀면 너무 커요."
        case .tooMany: return "파일이 너무 많아요."
        case .unsafePath(let path): return "이상한 경로가 있어요: \(path.prefix(80))"
        case .link(let path): return "링크 파일이 있어요: \(path.prefix(80))"
        }
    }
}

enum ArisSkillArchive {
    /// The most a tarball may inflate to, and how many entries it may hold.
    static let maxInflated = 60 * 1_048_576
    static let maxEntries = 5_000

    /// The DEFLATE stream inside a gzip file, inflated up to `limit` bytes.
    static func gunzip(_ data: Data, limit: Int = maxInflated) -> Result<Data, ArisArchiveProblem> {
        deflated(data).flatMap { inflate($0, limit: limit) }
    }

    /// The raw DEFLATE bytes of a gzip file (its header and trailer taken off).
    static func deflated(_ data: Data) -> Result<[UInt8], ArisArchiveProblem> {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8 else { return .failure(.notGzip) }
        let flags = bytes[3]
        var at = 10
        if flags & 0x04 != 0 {
            guard at + 2 <= bytes.count else { return .failure(.corrupt) }
            at += 2 + Int(bytes[at]) + Int(bytes[at + 1]) << 8
        }
        for bit: UInt8 in [0x08, 0x10] where flags & bit != 0 {
            while at < bytes.count, bytes[at] != 0 { at += 1 }
            at += 1
        }
        if flags & 0x02 != 0 { at += 2 }
        guard at < bytes.count - 8 else { return .failure(.corrupt) }
        return .success(Array(bytes[at..<(bytes.count - 8)]))
    }

    /// Raw DEFLATE, streamed, stopping as soon as the output passes `limit`.
    static func inflate(_ input: [UInt8], limit: Int) -> Result<Data, ArisArchiveProblem> {
        var output = Data()
        if let problem = inflate(input, limit: limit, into: { output.append($0); return nil }) { return .failure(problem) }
        return .success(output)
    }

    /// Raw DEFLATE, streamed piece by piece into `sink` (which may stop it with a problem), stopping as soon as the
    /// output passes `limit`. Nil when it all came through.
    static func inflate(_ input: [UInt8], limit: Int, into sink: (UnsafeBufferPointer<UInt8>) -> ArisArchiveProblem?) -> ArisArchiveProblem? {
        let destinationSize = 64 * 1_024
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationSize)
        defer { destination.deallocate() }
        var stream = compression_stream(dst_ptr: destination, dst_size: destinationSize, src_ptr: destination, src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else { return .corrupt }
        defer { compression_stream_destroy(&stream) }
        var total = 0
        return input.withUnsafeBufferPointer { source -> ArisArchiveProblem? in
            guard let base = source.baseAddress else { return .corrupt }
            stream.src_ptr = base
            stream.src_size = source.count
            while true {
                stream.dst_ptr = destination
                stream.dst_size = destinationSize
                let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = destinationSize - stream.dst_size
                if produced > 0 {
                    total += produced
                    if total > limit { return .tooBig }
                    if let problem = sink(UnsafeBufferPointer(start: destination, count: produced)) { return problem }
                }
                switch status {
                case COMPRESSION_STATUS_END: return nil
                case COMPRESSION_STATUS_OK: if produced == 0 && stream.src_size == 0 { return .corrupt }
                default: return .corrupt
                }
            }
        }
    }

    // MARK: - A repository's tarball, read for one folder

    /// A repository's tarball may inflate to this much and hold this many entries while it is read for one skill
    /// folder: only that folder's files count toward maxInflated and maxEntries and are checked for links and odd paths
    /// (nothing else is ever written).
    static let maxStream = 1_024 * 1_048_576
    static let maxListed = 200_000

    /// One entry of a tar as the scan sees it: its name as written (the top folder still on), its type and size.
    struct Listed: Equatable {
        let name: String
        let type: UInt8
        let size: Int
    }

    /// Reads a gzip'd tar entry by entry without holding it whole: `visit` sees each entry (after its pax or GNU long
    /// name) and says whether its body is wanted; a wanted body then reaches `body`. Bodies not wanted are skipped as
    /// they stream. Nil when the whole archive was read.
    static func scan(_ gzip: Data, limit: Int = maxStream, visit: @escaping (Listed) -> Bool,
                     body: @escaping (Listed, Data) -> ArisArchiveProblem?) -> ArisArchiveProblem? {
        let input: [UInt8]
        switch deflated(gzip) {
        case .failure(let problem): return problem
        case .success(let bytes): input = bytes
        }
        var reader = TarReader(visit: visit, body: body)
        let problem = inflate(input, limit: limit) { reader.feed($0) }
        return problem ?? reader.problem ?? (reader.ended ? nil : reader.leftover)
    }

    /// The tar state machine behind `scan`: a header, then its body kept, read as a name, or skipped.
    private struct TarReader {
        let visit: (Listed) -> Bool
        let body: (Listed, Data) -> ArisArchiveProblem?
        var pending = [UInt8]()
        var start = 0
        var current: (entry: Listed, keep: Bool, meta: UInt8?)?
        var remaining = 0
        var padding = 0
        var collected = Data()
        var longName: String?
        var count = 0
        var ended = false
        var problem: ArisArchiveProblem?

        /// Bytes left over that aren't a whole archive: a tar that stops mid-entry.
        var leftover: ArisArchiveProblem? { current != nil || pending.count - start > 0 && pending[start...].contains(where: { $0 != 0 }) ? .corrupt : nil }

        init(visit: @escaping (Listed) -> Bool, body: @escaping (Listed, Data) -> ArisArchiveProblem?) {
            self.visit = visit
            self.body = body
        }

        mutating func feed(_ chunk: UnsafeBufferPointer<UInt8>) -> ArisArchiveProblem? {
            guard !ended else { return nil }
            pending.append(contentsOf: chunk)
            while problem == nil, !ended {
                if current != nil {
                    guard step() else { break }
                } else {
                    guard pending.count - start >= 512 else { break }
                    header(Array(pending[start..<(start + 512)]))
                    start += 512
                }
            }
            if start > 1_048_576 || start == pending.count {
                pending.removeFirst(start)
                start = 0
            }
            return problem
        }

        /// One header: the entry it starts (or the end of the archive).
        mutating func header(_ header: [UInt8]) {
            if header.allSatisfy({ $0 == 0 }) { ended = true; return }
            count += 1
            guard count <= ArisSkillArchive.maxListed else { problem = .tooMany; return }
            guard let size = ArisSkillArchive.octal(header[124..<136]), size >= 0 else { problem = .corrupt; return }
            let type = header[156]
            let name = longName ?? ArisSkillArchive.fullName(header)
            let entry = Listed(name: name, type: type, size: size)
            remaining = size
            padding = (size + 511) / 512 * 512 - size
            collected = Data()
            switch type {
            case UInt8(ascii: "x"), UInt8(ascii: "L"):
                // A long name for the next entry: kept, at most a megabyte.
                guard size <= 1_048_576 else { problem = .corrupt; return }
                current = (entry, true, type)
            case UInt8(ascii: "g"):
                longName = nil
                current = (entry, false, nil)
            default:
                longName = nil
                current = (entry, visit(entry), nil)
            }
        }

        /// The body under way: consumed as far as the bytes go; true when it is done (the next header can be read).
        mutating func step() -> Bool {
            guard let (entry, keep, meta) = current else { return true }
            let available = pending.count - start
            if remaining > 0 {
                let take = min(remaining, available)
                if keep { collected.append(contentsOf: pending[start..<(start + take)]) }
                start += take
                remaining -= take
                if remaining > 0 { return false }
            }
            let skip = min(padding, pending.count - start)
            start += skip
            padding -= skip
            if padding > 0 { return false }
            current = nil
            switch meta {
            case UInt8(ascii: "x"): longName = ArisSkillArchive.paxPath(collected)
            case UInt8(ascii: "L"): longName = String(decoding: collected.prefix { $0 != 0 }, as: UTF8.self)
            default: if keep, let problem = body(entry, collected) { self.problem = problem }
            }
            collected = Data()
            return true
        }
    }

    /// The plain files of a tar (ustar and pax), with the top folder taken off when every entry shares one.
    static func untar(_ tar: Data) -> Result<[ArisArchiveEntry], ArisArchiveProblem> {
        let bytes = [UInt8](tar)
        var at = 0
        var entries: [(String, Data)] = []
        var longName: String?
        var count = 0
        while at + 512 <= bytes.count {
            let header = Array(bytes[at..<(at + 512)])
            if header.allSatisfy({ $0 == 0 }) { break }
            count += 1
            guard count <= maxEntries else { return .failure(.tooMany) }
            guard let size = octal(header[124..<136]) else { return .failure(.corrupt) }
            let type = header[156]
            let start = at + 512
            guard size >= 0, start + size <= bytes.count else { return .failure(.corrupt) }
            let body = Data(bytes[start..<(start + size)])
            at = start + (size + 511) / 512 * 512
            let name = longName ?? fullName(header)
            longName = nil
            switch type {
            case UInt8(ascii: "x"): longName = paxPath(body)
            case UInt8(ascii: "g"): continue
            case UInt8(ascii: "L"): longName = String(decoding: body.prefix { $0 != 0 }, as: UTF8.self)
            case UInt8(ascii: "5"): continue
            case 0, UInt8(ascii: "0"), UInt8(ascii: "7"):
                guard let clean = safe(name) else { return .failure(.unsafePath(name)) }
                // Finder's, git's and archivers' own files never come along (security review I2).
                if clean.split(separator: "/").contains(where: { ArisSkillFolder.isIgnored(String($0)) }) { continue }
                entries.append((clean, body))
            case UInt8(ascii: "1"), UInt8(ascii: "2"): return .failure(.link(name))
            default: return .failure(.unsafePath(name))
            }
        }
        // GitHub wraps everything in "<owner>-<repo>-<sha>/".
        let tops = Set(entries.map { $0.0.split(separator: "/").first.map(String.init) ?? "" })
        let strip = tops.count == 1 && entries.allSatisfy { $0.0.contains("/") }
        return .success(entries.compactMap { path, data in
            let inner = strip ? path.split(separator: "/").dropFirst().joined(separator: "/") : path
            return inner.isEmpty ? nil : ArisArchiveEntry(path: inner, data: data)
        })
    }

    /// A relative path of plain parts (no "..", ".", empty or hidden-git part, no absolute start), at most 12 deep.
    static func safe(_ path: String) -> String? {
        guard !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\u{0}"), path.count <= 400, !ArisSkillText.hasHidden(path),
              !path.contains("\n"), !path.contains("\r"), !path.contains("\t") else { return nil }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty, parts.count <= 12, !parts.contains(where: { $0 == ".." || $0 == "." }) else { return nil }
        return parts.joined(separator: "/")
    }

    private static func octal(_ field: ArraySlice<UInt8>) -> Int? {
        let text = String(decoding: field.prefix { $0 != 0 && $0 != 0x20 }, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? 0 : Int(text, radix: 8)
    }

    private static func fullName(_ header: [UInt8]) -> String {
        let name = String(decoding: header[0..<100].prefix { $0 != 0 }, as: UTF8.self)
        let magic = String(decoding: header[257..<262], as: UTF8.self)
        let prefix = magic == "ustar" ? String(decoding: header[345..<500].prefix { $0 != 0 }, as: UTF8.self) : ""
        return prefix.isEmpty ? name : prefix + "/" + name
    }

    /// The `path=` record of a pax header.
    private static func paxPath(_ body: Data) -> String? {
        String(decoding: body, as: UTF8.self).split(separator: "\n").compactMap { record -> String? in
            guard let space = record.firstIndex(of: " ") else { return nil }
            let pair = record[record.index(after: space)...]
            return pair.hasPrefix("path=") ? String(pair.dropFirst(5)) : nil
        }.first
    }

    /// Writes `entries` under `folder` (new files only, 0644, folders 0755); nothing outside it.
    static func write(_ entries: [ArisArchiveEntry], to folder: URL) -> Result<Void, ArisArchiveProblem> {
        for entry in entries {
            guard let path = safe(entry.path) else { return .failure(.unsafePath(entry.path)) }
            if path.split(separator: "/").contains(where: { ArisSkillFolder.isIgnored(String($0)) }) { continue }
            let file = folder.appendingPathComponent(path)
            do {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o755])
            } catch { return .failure(.unsafePath(path)) }
            guard FileManager.default.createFile(atPath: file.path, contents: entry.data, attributes: [.posixPermissions: 0o644]) else {
                return .failure(.unsafePath(path))
            }
        }
        return .success(())
    }
}
