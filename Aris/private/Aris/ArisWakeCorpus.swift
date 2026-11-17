//
//  ArisWakeCorpus.swift
//  Aris
//
//  Where 호출어 녹음 and 하루 소리 모으기 keep what they record, and the manifest the wake word's bench and its training
//  read (tests/wake-bench `bench corpus`, tools/wakenet). Everything is in the app's own container
//  (Application Support/Aris/wake-corpus): the folders 0700, every file 0600, nothing sent anywhere, and 다 지우기
//  removes the folder. Clips are 16 kHz mono 16-bit WAV. The manifest says for each clip what it is (a call of the
//  name, a word like it, or room audio kept around speech or a wake candidate), how it was said and on which kind of
//  microphone, so the bench can count misses per condition. Foundation only (tested over a temporary folder).
//

import Foundation

/// The labelled clips, as written to manifest.json.
struct ArisWakeManifest: Codable, Equatable {
    enum Label: String, Codable, CaseIterable {
        /// 호출어 녹음: the name, and the words that only sound like it.
        case call, confusable
        /// 하루 소리 모으기: room audio around a phrase of speech, and around a phrase stage 1 handed on.
        case ambientSpeech = "ambient-speech"
        case ambientCandidate = "ambient-candidate"
        /// Synthetic sets only (tools/wakenet): everyday talk that never says the name, and sounds that are no speech.
        case speech, noise
    }

    struct Entry: Codable, Equatable {
        /// Relative to the corpus folder: "calls/call-plain-aris-t03.wav".
        let file: String
        let label: Label
        /// What was asked to be said (recorded takes only).
        var phrase: String?
        var prompt: String?
        var take: Int?
        var style: String?
        var distance: String?
        var background: String?
        /// The microphone the take asked for ("built-in", "airpods").
        var mic: String?
        /// The kind of device it really came from (ArisAudioDevice.Transport's raw value).
        var device: String?
        let seconds: Double
        /// ISO 8601.
        let recordedAt: String
        /// Ambient candidates: how the wake check ended ("voice", "whisper", "recognizer", "rejected"), and stage 1's
        /// distance; never what was said.
        var outcome: String?
        var score: Double?
        /// Synthetic sets: which voice said it ("owner" for the one the bench enrolls DTW from); nil for the user's own.
        var speaker: String?
    }

    var version = 1
    var sampleRate = 16_000
    var entries: [Entry] = []
    /// 하루 소리 모으기: seconds the room was listened to while it was on (false wakes per hour need the hours).
    var listenedSeconds: Double = 0

    /// The manifest with `entry` in it (an entry for the same file is replaced: a take recorded again).
    func adding(_ entry: Entry) -> ArisWakeManifest {
        var next = self
        next.entries = entries.filter { $0.file != entry.file } + [entry]
        return next
    }

    func removing(files: Set<String>) -> ArisWakeManifest {
        var next = self
        next.entries = entries.filter { !files.contains($0.file) }
        return next
    }

    func listening(_ seconds: Double) -> ArisWakeManifest {
        var next = self
        next.listenedSeconds = listenedSeconds + max(0, seconds)
        return next
    }

    /// The recorded takes' keys (ArisWakeStep.key).
    var recordedTakes: Set<String> {
        Set(entries.filter { $0.label == .call || $0.label == .confusable }.compactMap { entry in
            guard let prompt = entry.prompt, let take = entry.take else { return nil }
            return String(format: "%@-t%02d", prompt, take)
        })
    }

    func count(_ labels: Set<Label>) -> Int { entries.filter { labels.contains($0.label) }.count }

    static func timestamp(_ date: Date) -> String {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format.string(from: date)
    }
}

/// 16 kHz mono 16-bit PCM WAV.
enum ArisWAV {
    static func encode(_ samples: [Float], sampleRate: Int = 16_000) -> Data {
        var data = Data()
        func put32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func put16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); put32(36 + bytes); data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); put32(16); put16(1); put16(1); put32(UInt32(sampleRate)); put32(UInt32(sampleRate * 2)); put16(2); put16(16)
        data.append(contentsOf: Array("data".utf8)); put32(bytes)
        data.reserveCapacity(data.count + samples.count * 2)
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            put16(UInt16(bitPattern: Int16((clamped * 32767).rounded())))
        }
        return data
    }

    /// The samples of a WAV this file wrote (16-bit PCM mono); nil for anything else.
    static func decode(_ data: Data) -> [Float]? {
        guard data.count >= 44, String(decoding: data[0..<4], as: UTF8.self) == "RIFF", String(decoding: data[8..<12], as: UTF8.self) == "WAVE" else { return nil }
        let bytes = [UInt8](data)
        func u32(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24 }
        var offset = 12
        while offset + 8 <= bytes.count {
            let id = String(decoding: bytes[offset..<(offset + 4)], as: UTF8.self), size = u32(offset + 4)
            if id == "data" {
                let end = min(bytes.count, offset + 8 + size)
                return stride(from: offset + 8, to: end - 1, by: 2).map { Float(Int16(bitPattern: UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8)) / 32767 }
            }
            offset += 8 + size + (size & 1)
        }
        return nil
    }
}

/// The corpus folder on disk.
struct ArisWakeCorpusStore {
    let folder: URL

    static let manifestName = "manifest.json"
    static let folderMode = 0o700
    static let fileMode = 0o600

    /// The app's own: Application Support/Aris/wake-corpus (inside the sandbox's container).
    static var standard: ArisWakeCorpusStore? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            .map { ArisWakeCorpusStore(folder: $0.appendingPathComponent("Aris/wake-corpus", isDirectory: true)) }
    }

    var manifestURL: URL { folder.appendingPathComponent(Self.manifestName) }

    func load() -> ArisWakeManifest {
        guard let data = try? Data(contentsOf: manifestURL), let manifest = try? JSONDecoder().decode(ArisWakeManifest.self, from: data) else { return ArisWakeManifest() }
        return manifest
    }

    /// Writes the clip and the manifest that lists it; returns the new manifest.
    @discardableResult
    func save(_ samples: [Float], as entry: ArisWakeManifest.Entry, into manifest: ArisWakeManifest) throws -> ArisWakeManifest {
        let url = folder.appendingPathComponent(entry.file)
        try makeFolder(url.deletingLastPathComponent())
        try write(ArisWAV.encode(samples), to: url)
        let next = manifest.adding(entry)
        try write(next)
        return next
    }

    func write(_ manifest: ArisWakeManifest) throws {
        try makeFolder(folder)
        let coder = JSONEncoder()
        coder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try write(try coder.encode(manifest), to: manifestURL)
    }

    /// Removes the clips named and drops them from the manifest.
    @discardableResult
    func remove(_ files: Set<String>, from manifest: ArisWakeManifest) throws -> ArisWakeManifest {
        for file in files { try? FileManager.default.removeItem(at: folder.appendingPathComponent(file)) }
        let next = manifest.removing(files: files)
        try write(next)
        return next
    }

    /// 다 지우기: the whole folder, every clip and the manifest.
    func removeAll() throws {
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        try FileManager.default.removeItem(at: folder)
    }

    /// The bytes the clips take.
    func bytes(_ manifest: ArisWakeManifest) -> Int {
        manifest.entries.reduce(0) { total, entry in
            let size = (try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(entry.file).path)[.size]) as? NSNumber
            return total + (size?.intValue ?? 0)
        }
    }

    private func makeFolder(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: Self.folderMode])
        // A folder made before (or by a parent's creation) is narrowed too.
        try FileManager.default.setAttributes([.posixPermissions: Self.folderMode], ofItemAtPath: url.path)
        if url.standardizedFileURL != folder.standardizedFileURL {
            try FileManager.default.setAttributes([.posixPermissions: Self.folderMode], ofItemAtPath: folder.path)
        }
    }

    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: Self.fileMode], ofItemAtPath: url.path)
    }
}
