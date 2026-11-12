//
//  ArisConvert.swift
//  aris-tools
//
//  `convert`, `merge`, `split` and `compress` (ArisConvertWords reads the words): what each file is, what it becomes
//  and where the new file goes. Everything is checked before anything is made: every file in the home folder and
//  outside the protected places (ArisActivity.checkedPath, links followed), of a kind Aris handles, and every option
//  in range. New files go next to the first original, never over anything: `name.png`, else `name 2.png` (Finder's
//  way); a merge is `name (합침).pdf`, a split page `name (3쪽).pdf`, a smaller copy `name (압축).jpg`. Each is
//  written in a temporary folder on the same disk and moved into place in one step that never replaces what is there.
//  What comes back names only the new files, as the brain gave the folder (the home folder as ~), never contents.
//

import Foundation
import ImageIO

struct ArisConvertError: Error, LocalizedError, Equatable {
    /// Never a file's name when the files were picked by a selector (only "file 2").
    let message: String
    /// The system's own words (they may name a file): said only for files the brain named.
    var detail: String? = nil
    init(_ message: String, detail: String? = nil) {
        self.message = message
        self.detail = detail
    }
    var errorDescription: String? { message + (detail.map { ": " + $0 } ?? "") }
}

struct ArisConvertResult: Equatable {
    /// The new files as shown: the folder as given (the home folder as ~), the new name. Empty for a selector.
    let shown: [String]
    /// Where they really are (for the log and its undo).
    let made: [String]
    /// Originals left as they were because nothing smaller came out of them (compress), as shown.
    let notSmaller: [String]
    /// The activity log's line.
    let summary: String
    /// For files a selector picked: what is said instead of any name (counts, the new kind, where they went).
    var quietLine: String? = nil
    /// Said after the new files (a merge that went to Downloads).
    var note: String? = nil
}

enum ArisConvert {
    enum Kind: Equatable { case image, pdf, video, audio }

    static let imageInputs: Set<String> = ["heic", "heif", "jpg", "jpeg", "png", "tiff", "tif", "gif", "bmp", "webp"]
    static let imageOutputs = ["png", "jpg", "heic", "tiff", "gif", "bmp", "webp"]

    static let supportedLine = "Aris handles pictures (HEIC, JPEG, PNG, TIFF, GIF, BMP; WebP to read), PDFs, video (MOV, MP4, M4V) and sound (M4A, MP3, WAV, AIFF, CAF, AAC)"

    /// The one-line refusal for a kind of file Aris doesn't handle. `label`: for a file a selector picked ("file 2"),
    /// which is all that is said of it besides a plain extension.
    static func unsupported(_ name: String, label: String? = nil) -> ArisConvertError {
        let ext = (name as NSString).pathExtension.lowercased()
        let plain = ext.range(of: "^[a-z0-9]{1,5}$", options: .regularExpression) != nil ? ext : ""
        if let label { return ArisConvertError("Aris can't convert \(label)\(plain.isEmpty ? "" : " (.\(plain))") yet. \(supportedLine).") }
        return ArisConvertError("Aris can't convert \(ext.isEmpty ? name : "." + ext) files yet. \(supportedLine).")
    }

    /// What is said for a failure: for files a selector picked (`quiet`), never the system's words or a name.
    static func message(_ error: Error, quiet: Bool) -> String {
        if let error = error as? ArisConvertError { return quiet ? error.message : error.errorDescription ?? error.message }
        if let partial = error as? Partial { return partial.message }
        return quiet ? "it didn't work" : error.localizedDescription
    }

    static func kind(_ path: String) -> Kind? {
        let ext = (path as NSString).pathExtension.lowercased()
        if imageInputs.contains(ext) { return .image }
        if ext == "pdf" { return .pdf }
        if ArisConvertWords.videoTypes.contains(ext) { return .video }
        if ArisConvertWords.audioTypes.contains(ext) { return .audio }
        return nil
    }

    /// A format as said (`.JPEG`, `jpg`, `tif`…) in Aris's own spelling; nil for one it never makes.
    static func format(_ word: String) -> String? {
        var format = word.lowercased()
        if format.hasPrefix(".") { format.removeFirst() }
        switch format {
        case "jpeg": format = "jpg"
        case "tif": format = "tiff"
        case "heif": format = "heic"
        default: break
        }
        return (imageOutputs + ["pdf", "mp4", "mov", "m4a"]).contains(format) ? format : nil
    }

    /// The format a file already is, in Aris's spelling (m4v counts as mp4).
    static func ownFormat(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        return ext == "m4v" ? "mp4" : format(ext) ?? ext
    }

    /// What the brain reads back: the new files (at most 20 named), and the originals nothing smaller came out of.
    static func report(_ result: ArisConvertResult) -> String {
        if let quiet = result.quietLine { return quiet }
        var lines = result.shown.prefix(20).map { "made \($0)" + (result.note.map { " (\($0))" } ?? "") }
        if result.shown.count > 20 { lines.append("and \(result.shown.count - 20) more next to them") }
        lines += result.notSmaller.map { "kept \($0) as it was: nothing smaller came out of it" }
        return lines.joined(separator: "\n")
    }

    // MARK: - Names

    /// A Finder-like free name in `folder`: `stem.ext`, else `stem 2.ext`, `stem 3.ext`…
    static func freeName(stem: String, ext: String, taken: (String) -> Bool) -> String {
        let first = "\(stem).\(ext)"
        if !taken(first) { return first }
        for number in 2...9_999 where !taken("\(stem) \(number).\(ext)") { return "\(stem) \(number).\(ext)" }
        return "\(stem) \(UUID().uuidString.prefix(8)).\(ext)"
    }

    static func stem(_ path: String) -> String { ((path as NSString).lastPathComponent as NSString).deletingPathExtension }

    /// A path for the brain: the home folder as ~.
    static func shown(_ path: String, home: String) -> String {
        for base in [home, URL(fileURLWithPath: home).resolvingSymlinksInPath().path] where base.count > 1 && (path == base || path.hasPrefix(base + "/")) {
            return "~" + path.dropFirst(base.count)
        }
        return path
    }

    // MARK: - The files

    /// One original: as given (absolute), and where it really is.
    struct Source: Equatable {
        let given: String
        let real: String
        /// What messages call it: its name, or for a file a selector picked only "file 2".
        let label: String
        /// Picked by a selector: its name is never said.
        let quiet: Bool
        /// The folder it is in, links resolved: new files go here.
        let folder: String
        let kind: Kind

        var destination: ArisConvertDestination {
            ArisConvertDestination(folder: folder, shownFolder: (given as NSString).deletingLastPathComponent)
        }
    }

    /// How long before a turn began its question's record may have been kept (the screen look, routing, a card).
    static let freshFor: TimeInterval = 180

    /// What one call may take on.
    struct Limits: Equatable {
        /// A picture or PDF read at most this big, a video or sound this big.
        var sourceBytes: Int64 = 200 << 20
        var mediaBytes: Int64 = 2 << 30
        /// A picture of at most this many pixels.
        var pixels = 100_000_000
        /// Pages in a merged PDF, or files out of one split.
        var pages = 500
        /// All the new files of one call together.
        var outputBytes: Int64 = 2 << 30
        /// The pictures of one merge together, from their headers before any is drawn.
        var mergePixels = 400_000_000
        static let standard = Limits()
    }

    /// Why a selector can't be used now, or nil: never in a background job (no one picked anything for it), and
    /// `--finder` only when Finder was in front as the user asked (else the selection may be an old one).
    /// The record must be this question's: kept as the user asked it, just before `turnStarted` (the turn's own credential
    /// file, new each turn), or for a relayed line just now.
    static func selectorRefusal(_ selector: ArisConvertWords.Selector, environment: [String: String], state: ArisShelfFiles.State?,
                                turnStarted: Date? = nil, now: Date = Date()) -> String? {
        if environment[ArisConvertWords.taskKey] == "1" {
            return "a background job can't use --finder or --shelf (nobody picked files for it): name the files' paths"
        }
        let start = turnStarted ?? now
        if let state, state.at > start.addingTimeInterval(5) || start.timeIntervalSince(state.at) > freshFor {
            return "what Aris knows of the shelf and Finder is from an earlier question: ask which files (or for a path)"
        }
        guard selector == .finder else { return nil }
        return state?.front == "com.apple.finder" ? nil
            : "Finder wasn't in front when the user asked, so its selection may be an old one: ask which files (or for a path)"
    }

    /// Every file checked: a path inside the home folder, outside the protected places (links followed, the file's
    /// own included), a file that is there (not a folder), of a kind Aris handles.
    static func sources(_ paths: [String], home: String, cwd: String, quiet: Bool = false, limits: Limits = .standard) throws -> [Source] {
        try paths.enumerated().map { index, path in
            let given = absolute(path.precomposedStringWithCanonicalMapping, home: home, cwd: cwd)
            let label = quiet ? "file \(index + 1)" : (given as NSString).lastPathComponent
            let checked: String
            do { checked = try ArisActivity.checkedPath(given, home: home) } catch {
                throw ArisConvertError("won't touch \(label)", detail: error.localizedDescription)
            }
            let real = URL(fileURLWithPath: checked).resolvingSymlinksInPath().path
            do { _ = try ArisActivity.checkedPath(real, home: home) } catch { throw ArisConvertError("won't touch \(label)", detail: error.localizedDescription) }
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: real, isDirectory: &isFolder) else { throw ArisConvertError("\(label) isn't there") }
            guard !isFolder.boolValue else { throw ArisConvertError("\(label) is a folder: name the files in it") }
            guard let kind = kind(real) ?? kind(given) else { throw unsupported((given as NSString).lastPathComponent, label: quiet ? label : nil) }
            try checkSize(real, kind: kind, label: label, limits: limits)
            return Source(given: given, real: real, label: label, quiet: quiet, folder: (checked as NSString).deletingLastPathComponent, kind: kind)
        }
    }

    /// A file small enough to take on: its bytes, and a picture's pixels as its header says (nothing decoded).
    private static func checkSize(_ path: String, kind: Kind, label: String, limits: Limits) throws {
        let bytes = fileSize(path), media = kind == .video || kind == .audio
        let most = media ? limits.mediaBytes : limits.sourceBytes
        guard bytes <= most else { throw ArisConvertError("\(label) is over \(ByteCountFormatter.string(fromByteCount: most, countStyle: .binary)), more than Aris takes on") }
        guard kind == .image else { return }
        guard let (width, height) = pixelSize(path) else { throw ArisConvertError("\(label): it isn't a picture Aris can read") }
        let pixels = width.multipliedReportingOverflow(by: height)
        guard !pixels.overflow, pixels.partialValue <= limits.pixels else {
            throw ArisConvertError("\(label) is over \(limits.pixels / 1_000_000) megapixels, more than Aris takes on")
        }
    }

    /// A picture's size as ImageIO reads it, else as a PNG, GIF or BMP header says (ImageIO gives nothing for a file
    /// that is only a header); nil when neither tells.
    static func pixelSize(_ path: String) -> (Int, Int)? {
        if let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int {
            return (width, height)
        }
        guard let handle = FileHandle(forReadingAtPath: path), let head = try? handle.read(upToCount: 32) else { return nil }
        try? handle.close()
        let bytes = [UInt8](head)
        func big(_ at: Int) -> Int { bytes[at..<at + 4].reduce(0) { $0 << 8 | Int($1) } }
        func little(_ at: Int, _ count: Int) -> Int { bytes[at..<at + count].reversed().reduce(0) { $0 << 8 | Int($1) } }
        if bytes.count >= 24, bytes.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) { return (big(16), big(20)) }
        if bytes.count >= 10, bytes.starts(with: Array("GIF8".utf8)) { return (little(6, 2), little(8, 2)) }
        if bytes.count >= 26, bytes.starts(with: Array("BM".utf8)) { return (abs(Int(Int32(truncatingIfNeeded: little(18, 4)))), abs(Int(Int32(truncatingIfNeeded: little(22, 4))))) }
        return nil
    }

    /// ~ expanded with `home`, and a relative path taken from `cwd`.
    static func absolute(_ path: String, home: String, cwd: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst(1) }
        return path.hasPrefix("/") ? path : cwd + "/" + path
    }

    // MARK: - Options

    struct Options: Equatable {
        var to: String?
        var quality: Double?
        var maxSide: Int?
        var percent: Int?
        var pages: String?
    }

    static func options(_ call: ArisConvertWords.Call) throws -> Options {
        var options = Options()
        if let to = call.options["--to"] {
            guard let format = format(to) else { throw ArisConvertError("Aris can't make .\(to.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))) files. It makes PNG, JPEG, HEIC, TIFF, GIF, BMP, PDF, MP4, MOV and M4A.") }
            if format == "webp", !ArisConvertImages.canWrite("webp") { throw ArisConvertError("this Mac reads WebP pictures but can't write them: pick PNG or JPEG") }
            options.to = format
        }
        if let quality = call.options["--quality"] {
            guard let value = Int(quality), (1...100).contains(value) else { throw ArisConvertError("--quality is a number from 1 to 100") }
            options.quality = Double(value) / 100
        }
        if let side = call.options["--max"] {
            guard let value = Int(side), (16...ArisConvertImages.largestSide).contains(value) else { throw ArisConvertError("--max is the longest side in pixels, 16 to 16384") }
            options.maxSide = value
        }
        if let percent = call.options["--percent"] {
            guard let value = Int(percent.trimmingCharacters(in: CharacterSet(charactersIn: "%"))), (1...100).contains(value) else { throw ArisConvertError("--percent is a number from 1 to 100") }
            options.percent = value
        }
        if options.maxSide != nil, options.percent != nil { throw ArisConvertError("give --max or --percent, not both") }
        options.pages = call.options["--pages"]
        return options
    }
}
