//
//  ArisConvertJobs.swift
//  aris-tools
//
//  The four file jobs, each planned whole before anything is made (a refusal leaves no file), then done one file at
//  a time under one deadline for the whole call (ArisConvertJob), each new file handed on as it lands (the activity
//  log is written then). ArisConvert checks the files and options; ArisConvertImages, ArisConvertPDF and
//  ArisConvertMedia do the work.
//

import Foundation
import PDFKit

/// One call's work: its deadline and limits, and what it has made so far.
final class ArisConvertJob {
    let home: String
    let deadline: Date
    let limits: ArisConvert.Limits
    private let placed: ([String]) -> Void
    private(set) var made: [(shown: String, real: String)] = []
    private(set) var written: Int64 = 0

    init(home: String, deadline: Date, limits: ArisConvert.Limits, placed: @escaping ([String]) -> Void) {
        self.home = home
        self.deadline = deadline
        self.limits = limits
        self.placed = placed
    }

    /// Seconds left for an export.
    var remaining: TimeInterval { max(0, deadline.timeIntervalSinceNow) }

    func checkTime() throws {
        if Date() >= deadline { throw ArisConvertError("it took too long, so Aris stopped (nothing more was made)") }
    }

    /// A new file of `bytes` may land: within the call's total.
    func checkRoom(_ bytes: Int64) throws {
        guard written + bytes <= limits.outputBytes else {
            throw ArisConvertError("that would make more new files than \(ByteCountFormatter.string(fromByteCount: limits.outputBytes, countStyle: .file)) in one go")
        }
    }

    func landed(_ file: (shown: String, real: String), bytes: Int64) {
        made.append(file)
        written += bytes
        placed(made.map(\.real))
    }
}

/// Where a new file goes: the folder (links resolved) and the folder as the brain gave it (for what is shown).
struct ArisConvertDestination {
    let folder: String
    let shownFolder: String
}

extension ArisConvert {
    /// Runs one call: `home` and `cwd` for the paths (tests pass their own), one `deadline` for the whole call (its
    /// own budget unless a caller's is sooner), `selection` for the files a selector stands for (the Finder selection,
    /// the shelf; never named back), and `placed` with every file made so far, as each one lands.
    static func run(_ call: ArisConvertWords.Call, home: String, cwd: String, deadline: Date? = nil, limits: Limits = .standard,
                    selection: (ArisConvertWords.Selector) throws -> [String] = { _ in [] },
                    placed: @escaping ([String]) -> Void = { _ in }) throws -> ArisConvertResult {
        let job = ArisConvertJob(home: home, deadline: deadline ?? ArisConvertWords.deadline(call), limits: limits, placed: placed)
        let options = try options(call)
        let files = try sources(try picked(call, selection), home: home, cwd: cwd, quiet: call.selector != nil, limits: limits)
        switch call.verb {
        case "convert": return try convert(files, options, job)
        case "merge": return try merge(files, options, job)
        case "split": return try split(files[0], options, job)
        case "compress": return try compress(files, options, job)
        default: throw ArisConvertError("usage: convert | merge | split | compress")
        }
    }

    /// The files: as named, or what the selector stands for (as many as the verb takes).
    private static func picked(_ call: ArisConvertWords.Call, _ selection: (ArisConvertWords.Selector) throws -> [String]) throws -> [String] {
        guard let selector = call.selector else { return call.paths }
        let paths = try selection(selector)
        guard !paths.isEmpty else { throw ArisConvertError(selector == .finder ? "nothing is selected in Finder" : "the shelf has no files") }
        guard paths.count <= ArisConvertWords.mostFiles else { throw ArisConvertError("that's more than \(ArisConvertWords.mostFiles) files") }
        if call.verb == "merge", paths.count < 2 { throw ArisConvertError("merge takes two or more files (\(paths.count) picked)") }
        if call.verb == "split", paths.count != 1 { throw ArisConvertError("split takes one PDF (\(paths.count) picked)") }
        return paths
    }

    /// The new formats, as said ("PNG", "JPG·PDF").
    private static func kinds(_ made: [(shown: String, real: String)]) -> String {
        var seen: [String] = []
        for ext in made.map({ ($0.real as NSString).pathExtension.uppercased() }) where !seen.contains(ext) { seen.append(ext) }
        return seen.joined(separator: "·")
    }

    // MARK: - convert

    private enum Plan {
        case picture(String)
        case picturePDF
        case pages(String, [Int])
        case media(ArisConvertMedia.Output, String)
    }

    private static func plan(_ file: Source, _ options: Options) throws -> Plan {
        let name = file.label, own = ownFormat(file.real)
        let resizing = options.maxSide != nil || options.percent != nil
        if options.pages != nil, file.kind != .pdf { throw ArisConvertError("--pages is for a PDF; \(name) isn't one") }
        switch file.kind {
        case .image:
            let to = options.to ?? own
            if to == "pdf" { return .picturePDF }
            guard imageOutputs.contains(to) else { throw ArisConvertError("a picture can't become .\(to): pick PNG, JPEG, HEIC, TIFF, GIF, BMP or PDF") }
            if to == "webp", !ArisConvertImages.canWrite("webp") { throw ArisConvertError("this Mac reads WebP pictures but can't write them: pick PNG or JPEG") }
            if to == own, !resizing, options.quality == nil { throw ArisConvertError("\(name) is already \(to.uppercased()): say what to change (--to, --max, --percent or --quality)") }
            return .picture(to)
        case .pdf:
            guard let to = options.to, to != "pdf" else {
                throw ArisConvertError(options.to == nil ? "say what to make of \(name): --to png or jpg (one picture a page)" : "\(name) is already a PDF (to cut it up, use split)")
            }
            guard imageOutputs.contains(to) else { throw ArisConvertError("a PDF's pages become pictures: pick PNG, JPEG, HEIC, TIFF, GIF or BMP") }
            let count: Int
            do { count = try ArisConvertPDF.open(URL(fileURLWithPath: file.real)).pageCount } catch {
                throw ArisConvertError("\(name): \(message(error, quiet: file.quiet))")
            }
            guard let groups = options.pages.map({ ArisConvertPDF.ranges($0, count: count) }) ?? [Array(0..<count)] else {
                throw ArisConvertError("--pages is like 1-3,5, with pages 1 to \(count)")
            }
            let pages = groups.flatMap { $0 }
            guard pages.count <= ArisConvertPDF.mostPages else { throw ArisConvertError("that's more than \(ArisConvertPDF.mostPages) pages: name fewer with --pages") }
            return .pages(to, pages)
        case .video, .audio:
            if resizing || options.quality != nil { throw ArisConvertError("to make \(name) smaller, use compress") }
            guard let to = options.to else { throw ArisConvertError("say what to make of \(name): --to \(file.kind == .video ? "mp4, mov or m4a" : "m4a")") }
            if file.kind == .audio {
                guard to == "m4a" else { throw ArisConvertError("a sound becomes M4A (\(name) has no picture)") }
                guard own != "m4a" else { throw ArisConvertError("\(name) is already M4A") }
                return .media(.sound, "m4a")
            }
            if to == "m4a" { return .media(.sound, "m4a") }
            guard let type = ArisConvertMedia.fileType(to), to != "m4a" else { throw ArisConvertError("a video becomes MP4, MOV or M4A (its sound)") }
            guard to != own else { throw ArisConvertError("\(name) is already \(to.uppercased())") }
            return .media(.video(type), to)
        }
    }

    private static func convert(_ files: [Source], _ options: Options, _ job: ArisConvertJob) throws -> ArisConvertResult {
        let plans = try files.map { try plan($0, options) }
        for (file, plan) in zip(files, plans) {
            let source = URL(fileURLWithPath: file.real), stem = stem(file.given)
            do {
                switch plan {
                case .picture(let to):
                    try autoreleasepool {
                        let image = ArisConvertImages.scaled(try ArisConvertImages.load(source, maxSide: options.maxSide), percent: options.percent)
                        try place(stem: stem, ext: to, to: file.destination, job) { try ArisConvertImages.write(image, to: $0, format: to, quality: options.quality) }
                    }
                case .picturePDF:
                    try autoreleasepool {
                        let image = ArisConvertImages.scaled(try ArisConvertImages.load(source, maxSide: options.maxSide), percent: options.percent)
                        let dpi = ArisConvertImages.dpi(source)
                        try place(stem: stem, ext: "pdf", to: file.destination, job) { try ArisConvertImages.writePDF([(image, dpi)], to: $0) }
                    }
                case .pages(let to, let pages):
                    let document = try ArisConvertPDF.open(source)
                    for index in pages {
                        try autoreleasepool {
                            guard let page = document.page(at: index) else { return }
                            let image = try ArisConvertPDF.pageImage(page, maxSide: options.maxSide, percent: options.percent)
                            try place(stem: "\(stem) (\(index + 1)쪽)", ext: to, to: file.destination, job) {
                                try ArisConvertImages.write(image, to: $0, format: to, quality: options.quality)
                            }
                        }
                    }
                case .media(let output, let ext):
                    try place(stem: stem, ext: ext, to: file.destination, job) {
                        try ArisConvertMedia.export([source], labels: [file.label], to: $0, output: output, preset: nil, limit: job.remaining)
                    }
                }
            } catch {
                throw partial(job.made, failed: file, error)
            }
        }
        let made = job.made, quiet = files[0].quiet
        let first = (files[0].given as NSString).lastPathComponent
        let summary = quiet ? "변환: \(files.count)개 → \(kinds(made))"
            : "변환: \(first)\(files.count > 1 ? " 외 \(files.count - 1)개" : "") → \(made.count == 1 ? (made[0].real as NSString).lastPathComponent : "\(made.count)개")"
        let line = made.count == files.count ? "\(files.count)개를 \(kinds(made))로 바꿨어요 (원본 옆에 저장)"
            : "\(files.count)개를 \(kinds(made)) \(made.count)개로 바꿨어요 (원본 옆에 저장)"
        return ArisConvertResult(shown: quiet ? [] : made.map(\.shown), made: made.map(\.real), notSmaller: [], summary: summary,
                                 quietLine: quiet ? line : nil)
    }

    /// A job that stopped partway: what was made stays (it is named, and the log's undo takes it away).
    struct Partial: Error, LocalizedError {
        let made: [(shown: String, real: String)]
        let message: String
        var errorDescription: String? { message }
    }

    private static func partial(_ made: [(shown: String, real: String)], failed file: Source, _ error: Error) -> Error {
        let name = file.label
        let why = message(error, quiet: file.quiet)
        guard !made.isEmpty else { return ArisConvertError("couldn't convert \(name): \(why)") }
        return Partial(made: made, message: "made \(made.count) file(s), then couldn't convert \(name): \(why)")
    }

    // MARK: - merge

    private static func merge(_ files: [Source], _ options: Options, _ job: ArisConvertJob) throws -> ArisConvertResult {
        let kinds = files.map(\.kind)
        if options.pages != nil || options.quality != nil || options.maxSide != nil || options.percent != nil {
            throw ArisConvertError("merge takes only --to")
        }
        let pageKinds: Set<Kind> = [.pdf, .image]
        let ext: String
        let first = files[0], name = (first.given as NSString).lastPathComponent, labels = files.map(\.label)
        var make: (URL) throws -> Void
        let sources = files.map { URL(fileURLWithPath: $0.real) }
        if kinds.allSatisfy(pageKinds.contains) {
            guard options.to == nil || options.to == "pdf" else { throw ArisConvertError("PDFs and pictures merge into one PDF: --to pdf") }
            ext = "pdf"
            make = { try ArisConvertPDF.merge(sources, kinds: kinds, labels: labels, most: job.limits.pages, to: $0) }
        } else if kinds.allSatisfy({ $0 == .video }) {
            let to = options.to ?? (ownFormat(first.real) == "mov" ? "mov" : "mp4")
            guard ["mp4", "mov", "m4a"].contains(to) else { throw ArisConvertError("videos merge into MP4, MOV or M4A (their sound)") }
            ext = to
            let output: ArisConvertMedia.Output = to == "m4a" ? .sound : .video(ArisConvertMedia.fileType(to)!)
            make = { try ArisConvertMedia.export(sources, labels: labels, to: $0, output: output, preset: nil, limit: job.remaining) }
        } else if kinds.allSatisfy({ $0 == .audio }) {
            guard options.to == nil || options.to == "m4a" else { throw ArisConvertError("sounds merge into one M4A: --to m4a") }
            ext = "m4a"
            make = { try ArisConvertMedia.export(sources, labels: labels, to: $0, output: .sound, preset: nil, limit: job.remaining) }
        } else {
            throw ArisConvertError("can't merge \(describe(kinds)) together: merge one kind (PDFs and pictures into a PDF, videos into a video, sounds into a sound)")
        }
        // The pictures' pixels together, from their headers, before any is drawn.
        let pixels = files.filter { $0.kind == .image }.reduce(0) { total, file in
            let size = pixelSize(file.real) ?? (0, 0)
            return total + size.0 * size.1
        }
        guard pixels <= job.limits.mergePixels else {
            throw ArisConvertError("those pictures are over \(job.limits.mergePixels / 1_000_000) megapixels together, more than one merge takes")
        }
        // Files from one folder: the merge goes beside them. From several: Downloads, never a folder the order of the
        // files would pick (a shared or synced one).
        let together = Set(files.map(\.folder)).count == 1
        let destination = together ? first.destination : try downloads(job.home)
        do { try place(stem: "\(stem(first.given)) (합침)", ext: ext, to: destination, job, make) } catch {
            throw ArisConvertError("couldn't merge them: \(message(error, quiet: first.quiet))")
        }
        let result = job.made[0], whereTo = together ? "첫 파일 옆에 저장" : "다운로드 폴더에 저장"
        return ArisConvertResult(shown: first.quiet ? [] : [result.shown], made: [result.real], notSmaller: [],
                                 summary: first.quiet ? "합침: \(files.count)개 → \(ext.uppercased())"
                                     : "합침: \(name) 외 \(files.count - 1)개 → \((result.real as NSString).lastPathComponent)",
                                 quietLine: first.quiet ? "\(files.count)개를 \(ext.uppercased()) 하나로 합쳤어요 (\(whereTo))" : nil,
                                 note: together ? nil : "다운로드 폴더에 저장 (the files were in different folders)")
    }

    /// The Downloads folder (made if it isn't there), checked like any other place.
    private static func downloads(_ home: String) throws -> ArisConvertDestination {
        let path = home + "/Downloads"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        let folder = try ArisActivity.checkedPath(path, home: home)
        return ArisConvertDestination(folder: folder, shownFolder: path)
    }

    private static func describe(_ kinds: [Kind]) -> String {
        let words: [(Kind, String)] = [(.pdf, "PDFs"), (.image, "pictures"), (.video, "videos"), (.audio, "sounds")]
        let present = words.filter { kinds.contains($0.0) }.map(\.1)
        return present.count == 2 ? present.joined(separator: " and ") : present.dropLast().joined(separator: ", ") + " and " + (present.last ?? "")
    }

    // MARK: - split

    private static func split(_ file: Source, _ options: Options, _ job: ArisConvertJob) throws -> ArisConvertResult {
        let name = file.label
        guard file.kind == .pdf else { throw ArisConvertError("split cuts up a PDF; \(name) isn't one") }
        if options.to != nil || options.quality != nil || options.maxSide != nil || options.percent != nil { throw ArisConvertError("split takes only --pages") }
        let document: PDFDocument
        do { document = try ArisConvertPDF.open(URL(fileURLWithPath: file.real)) } catch { throw ArisConvertError("\(name): \(message(error, quiet: file.quiet))") }
        let count = document.pageCount
        guard let groups = options.pages.map({ ArisConvertPDF.ranges($0, count: count) }) ?? (0..<count).map({ [$0] }) else {
            throw ArisConvertError("--pages is like 1-3,5, with pages 1 to \(count)")
        }
        guard count > 1 || options.pages != nil else { throw ArisConvertError("\(name) has only one page") }
        guard groups.count <= job.limits.pages else { throw ArisConvertError("that's more than \(job.limits.pages) files") }
        do {
            for group in groups {
                try autoreleasepool {
                    try place(stem: "\(stem(file.given)) (\(ArisConvertPDF.label(group))쪽)", ext: "pdf", to: file.destination, job) {
                        try ArisConvertPDF.extract(document, pages: group, to: $0)
                    }
                }
            }
        } catch {
            throw partial(job.made, failed: file, error)
        }
        let made = job.made
        return ArisConvertResult(shown: file.quiet ? [] : made.map(\.shown), made: made.map(\.real), notSmaller: [],
                                 summary: file.quiet ? "나눔: PDF 1개 → \(made.count)개" : "나눔: \((file.given as NSString).lastPathComponent) → \(made.count)개",
                                 quietLine: file.quiet ? "PDF를 \(made.count)개로 나눴어요 (원본 옆에 저장)" : nil)
    }

    // MARK: - compress

    private static func compress(_ files: [Source], _ options: Options, _ job: ArisConvertJob) throws -> ArisConvertResult {
        if options.to != nil || options.percent != nil || options.pages != nil { throw ArisConvertError("compress takes only --quality and --max") }
        for file in files where file.kind == .pdf {
            throw ArisConvertError("compress takes pictures, videos and sounds; \(file.label) is a PDF")
        }
        var notSmaller: [String] = []
        for file in files {
            let source = URL(fileURLWithPath: file.real)
            let ext: String
            let make: (URL) throws -> Void
            switch file.kind {
            case .image:
                ext = ownFormat(file.real) == "heic" ? "heic" : "jpg"
                make = { url in
                    try autoreleasepool {
                        try ArisConvertImages.write(try ArisConvertImages.load(source, maxSide: options.maxSide), to: url, format: ext, quality: options.quality ?? 0.7)
                    }
                }
            case .video:
                ext = ownFormat(file.real) == "mov" ? "mov" : "mp4"
                make = { try ArisConvertMedia.export([source], labels: [file.label], to: $0, output: .video(ArisConvertMedia.fileType(ext)!),
                                                      preset: ArisConvertMedia.compressPreset(maxSide: options.maxSide), limit: job.remaining) }
            case .audio, .pdf:
                ext = "m4a"
                make = { try ArisConvertMedia.export([source], labels: [file.label], to: $0, output: .sound, preset: nil, limit: job.remaining) }
            }
            let original = fileSize(file.real)
            do {
                if try !place(stem: "\(stem(file.given)) (압축)", ext: ext, to: file.destination, job, keep: { fileSize($0.path) < original }, make) {
                    notSmaller.append(shown(file.given, home: job.home))
                }
            } catch {
                throw partial(job.made, failed: file, error)
            }
        }
        let made = job.made, quiet = files[0].quiet
        let first = (files[0].given as NSString).lastPathComponent
        let kept = notSmaller.isEmpty ? "" : made.isEmpty ? "\(notSmaller.count)개 모두 더 작아지지 않아 그대로 뒀어요" : " · \(notSmaller.count)개는 더 작아지지 않아 그대로 뒀어요"
        let line = made.isEmpty ? kept : "\(made.count)개를 줄였어요 (원본 옆에 저장)" + kept
        return ArisConvertResult(shown: quiet ? [] : made.map(\.shown), made: made.map(\.real), notSmaller: quiet ? [] : notSmaller,
                                 summary: quiet ? "압축: \(files.count)개 → \(made.count)개"
                                     : "압축: \(first)\(files.count > 1 ? " 외 \(files.count - 1)개" : "") → \(made.count)개",
                                 quietLine: quiet ? line : nil)
    }

    static func fileSize(_ path: String) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    // MARK: - Placing a new file

    /// Where scratch files are made (a folder per new file, swept when stale), and the one in use now (for SIGTERM).
    static var scratchRoot: URL { FileManager.default.temporaryDirectory }
    nonisolated(unsafe) static var scratchInUse: URL?
    /// A copy staged in the user's folder (another disk), removed with the scratch folder on SIGTERM.
    nonisolated(unsafe) static var stagedInUse: String?

    /// What a signal or a stopped run leaves behind: the scratch folder and a staged copy.
    static func removeLeftovers() {
        if let scratch = scratchInUse { try? FileManager.default.removeItem(at: scratch) }
        if let staged = stagedInUse { try? FileManager.default.removeItem(atPath: staged) }
    }

    /// Scratch folders of earlier runs over an hour old (a run that was killed left them): only folders named
    /// aris-convert-<UUID> that belong to this user.
    static func sweepScratch(in root: URL = scratchRoot, olderThan age: TimeInterval = 3_600) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        for name in names where name.hasPrefix("aris-convert-") && UUID(uuidString: String(name.dropFirst("aris-convert-".count))) != nil {
            let url = root.appendingPathComponent(name)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  attributes[.type] as? FileAttributeType == .typeDirectory,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                  let changed = attributes[.modificationDate] as? Date, Date().timeIntervalSince(changed) > age else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// One new file, kept: it always lands (or throws).
    private static func place(stem: String, ext: String, to destination: ArisConvertDestination, _ job: ArisConvertJob,
                              _ make: (URL) throws -> Void) throws {
        _ = try place(stem: stem, ext: ext, to: destination, job, keep: { _ in true }, make)
    }

    /// Makes the file in a scratch folder (inside the call's deadline and size limit), then moves it into
    /// `destination` under a free name, never over anything (a name taken in between is skipped), and hands it on.
    /// `keep` false: it is thrown away (false).
    @discardableResult
    static func place(stem: String, ext: String, to destination: ArisConvertDestination, _ job: ArisConvertJob, keep: (URL) -> Bool,
                      _ make: (URL) throws -> Void) throws -> Bool {
        try job.checkTime()
        let scratch = scratchRoot.appendingPathComponent("aris-convert-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        scratchInUse = scratch
        defer {
            try? FileManager.default.removeItem(at: scratch)
            scratchInUse = nil
        }
        let temporary = scratch.appendingPathComponent("new.\(ext)")
        try make(temporary)
        try job.checkTime()
        let bytes = fileSize(temporary.path)
        guard FileManager.default.fileExists(atPath: temporary.path), bytes > 0 else { throw ArisConvertError("nothing came out") }
        guard keep(temporary) else { return false }
        try job.checkRoom(bytes)
        var taken: Set<String> = []
        for _ in 0..<50 {
            let name = freeName(stem: stem, ext: ext) { taken.contains($0) || FileManager.default.fileExists(atPath: destination.folder + "/" + $0) }
            let target = try ArisActivity.checkedPath(destination.folder + "/" + name, home: job.home)
            var moved = renamex_np(temporary.path, target, UInt32(RENAME_EXCL)) == 0
            var failure = moved ? 0 : errno
            if !moved, failure == EXDEV {
                // Another disk: copied under a name of Aris's own there first (removed if the copy fails), then renamed into
                // place, still never over anything.
                let staged = destination.folder + "/.aris-convert-\(UUID().uuidString).\(ext)"
                stagedInUse = staged
                defer { stagedInUse = nil }
                guard (try? FileManager.default.copyItem(atPath: temporary.path, toPath: staged)) != nil else {
                    try? FileManager.default.removeItem(atPath: staged)
                    throw ArisConvertError("couldn't copy the new file there")
                }
                do { try job.checkTime() } catch {
                    try? FileManager.default.removeItem(atPath: staged)
                    throw error
                }
                moved = renamex_np(staged, target, UInt32(RENAME_EXCL)) == 0
                failure = moved ? 0 : errno
                if !moved { try? FileManager.default.removeItem(atPath: staged) }
            }
            if moved {
                job.landed((shown(destination.shownFolder + "/" + name, home: job.home), target), bytes: bytes)
                return true
            }
            if failure == EEXIST { taken.insert(name); continue }
            throw ArisConvertError("couldn't put the new file there: \(String(cString: strerror(failure)))")
        }
        throw ArisConvertError("couldn't find a free name for it")
    }
}
