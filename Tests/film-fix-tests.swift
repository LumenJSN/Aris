//
//  film-fix-tests.swift
//  Two bugs from filming the launch video (2026-11-16, VM aris-film):
//  1. Forty photos selected in Finder, "make these smaller and put them in one pdf": the copies were made, then
//     `merge --finder` took the forty 4032×3024 originals (still the selection), went over the merge's 400-megapixel
//     total and was refused; the brain had no way to name the copies it had just made (a selector never names files),
//     and said "too many were selected at once". Now a conversion's new files are `--made` for the next step, the
//     Finder selection is taken in Finder's name order, a merge over the pixel total draws its pictures smaller
//     instead of refusing, opaque pictures go into the PDF as JPEG, and the auto check is told what a selector means.
//  2. The notch composer kept the sent words, so the next request was typed onto them ("…one pdfmake these…").
//

import CoreGraphics
import Foundation
import ImageIO

func runFilmFixTests() {
    runFilmFixMergeTests()
    runFilmFixMadeRuleTests()
    runFilmFixGateTests()
    runFilmFixComposerTests()
}

// MARK: - Bug 1: forty photos, smaller, one PDF

private func filmPicture(width: Int, height: Int, shade: Int) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    for x in stride(from: 0, to: width, by: 4) {
        context.setFillColor(CGColor(red: Double((x + shade * 7) % width) / Double(width), green: Double(shade) / 40, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: x, y: 0, width: 4, height: height))
    }
    return context.makeImage()!
}

private func writeFilmJPEG(_ image: CGImage, to path: String) {
    let writer = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.jpeg" as CFString, 1, nil)!
    CGImageDestinationAddImage(writer, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
    CGImageDestinationFinalize(writer)
}

/// Every picture a PDF's pages draw (Form XObjects followed): its pixels and whether it is kept as JPEG.
private func filmPDFImages(_ path: String) -> [(width: Int, height: Int, jpeg: Bool)] {
    guard let document = CGPDFDocument(URL(fileURLWithPath: path) as CFURL), document.numberOfPages > 0 else { return [] }
    var found: [(width: Int, height: Int, jpeg: Bool)] = []
    func walk(_ resources: CGPDFDictionaryRef, depth: Int) {
        var xobjects: CGPDFDictionaryRef?
        guard depth < 4, CGPDFDictionaryGetDictionary(resources, "XObject", &xobjects), let xobjects else { return }
        CGPDFDictionaryApplyBlock(xobjects, { _, object, _ in
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream, let info = CGPDFStreamGetDictionary(stream) else { return true }
            var subtype: UnsafePointer<CChar>?
            _ = CGPDFDictionaryGetName(info, "Subtype", &subtype)
            if subtype.map({ String(cString: $0) }) == "Form" {
                var inner: CGPDFDictionaryRef?
                if CGPDFDictionaryGetDictionary(info, "Resources", &inner), let inner { walk(inner, depth: depth + 1) }
                return true
            }
            var width: CGPDFInteger = 0, height: CGPDFInteger = 0
            _ = CGPDFDictionaryGetInteger(info, "Width", &width)
            _ = CGPDFDictionaryGetInteger(info, "Height", &height)
            var filter: UnsafePointer<CChar>?
            let jpeg = CGPDFDictionaryGetName(info, "Filter", &filter) && filter.map { String(cString: $0) } == "DCTDecode"
            found.append((Int(width), Int(height), jpeg))
            return true
        }, nil)
    }
    for number in 1...document.numberOfPages {
        guard let page = document.page(at: number)?.dictionary else { continue }
        var resources: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(page, "Resources", &resources), let resources { walk(resources, depth: 0) }
    }
    return found
}

private func filmPageWidths(_ path: String) -> [Int] {
    guard let document = CGPDFDocument(URL(fileURLWithPath: path) as CFURL) else { return [] }
    return (0..<document.numberOfPages).compactMap { document.page(at: $0 + 1).map { Int($0.getBoxRect(.mediaBox).width.rounded()) } }
}

private func filmSize(_ path: String) -> Int64 { ArisConvert.fileSize(path) }

/// The film's turn, as far as aris-tools goes: forty photos selected in Finder (handed over in no order), made smaller
/// with `compress --finder`, then those copies merged with `merge --made`; and the originals merged too, over the
/// pixel total, which now draws them smaller instead of refusing.
private func runFilmFixMergeTests() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("aris-filmfix-tests-\(UUID().uuidString)")
    let home = root.resolvingSymlinksInPath().path
    let trip = home + "/Pictures/Tokyo Trip"
    try? FileManager.default.createDirectory(atPath: trip, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let originals = (0..<40).map { trip + "/IMG_\(4101 + $0).JPG" }
    for (index, path) in originals.enumerated() { writeFilmJPEG(filmPicture(width: 300 + index, height: 200, shade: index), to: path) }
    // Forty pictures of about 60,000 pixels each (2.56 million together) against a total of one million: the film's
    // forty 12-megapixel photos against 400 million, scaled down.
    var limits = ArisConvert.Limits.standard
    limits.mergePixels = 1_000_000
    var shuffled = originals
    shuffled.swapAt(0, 39); shuffled.swapAt(3, 17); shuffled.reverse()
    let turnStarted = Date().addingTimeInterval(-2)
    let run = { (words: [String], picked: [String]) throws -> ArisConvertResult in
        guard let call = ArisConvertWords.parse(words) else { throw ArisConvertError("malformed") }
        return try ArisConvert.run(call, home: home, cwd: home, limits: limits, selection: { _ in picked })
    }

    // 1. "make these smaller": compress --finder.
    let smaller: ArisConvertResult
    do { smaller = try run(["compress", "--finder", "--max", "100"], shuffled) } catch {
        return check(false, "film merge: compress --finder of forty photos ran (\(ArisConvert.message(error, quiet: true)))")
    }
    let copies = (0..<40).map { trip + "/IMG_\(4101 + $0) (압축).jpg" }
    check(smaller.made.map { $0.precomposedStringWithCanonicalMapping } == copies.map { $0.precomposedStringWithCanonicalMapping }
          && copies.allSatisfy(FileManager.default.fileExists(atPath:)),
          "film merge: compress --finder made forty smaller copies beside the originals, in Finder's name order")
    let quiet = ArisConvert.report(smaller)
    check(quiet.hasPrefix("40개를 줄였어요 (원본 옆에 저장)") && quiet.contains("--made") && quiet.contains("from: \"made\"")
          && !quiet.contains("IMG_") && !smaller.summary.contains("IMG_"),
          "film merge: what the brain reads back is a count and how to use the new files next (--made), never a name (\(quiet))")

    // aris-tools keeps what it made, for --made (as convertCommand does after each run).
    ArisMadeFiles.save(smaller.made, home: home)
    let kept = ArisMadeFiles.state(home: home)
    let keptMode = (try? FileManager.default.attributesOfItem(atPath: ArisMadeFiles.file(home: home).path))?[.posixPermissions] as? NSNumber
    check(kept?.made == smaller.made && keptMode?.intValue == 0o600, "film merge: the made files are kept (0600) for --made, in order")
    check(ArisConvert.selectorRefusal(.made, environment: [:], state: nil, made: kept, turnStarted: turnStarted) == nil,
          "film merge: --made right after this question's compress is allowed")

    // 2. "and put them in one pdf": merge --made, the smaller copies (never the originals).
    let merged: ArisConvertResult
    do { merged = try run(["merge", "--made", "--to", "pdf"], kept?.made ?? []) } catch {
        return check(false, "film merge: merge --made of the forty copies ran (\(ArisConvert.message(error, quiet: true)))")
    }
    let pdf = merged.made.first ?? ""
    let images = filmPDFImages(pdf)
    let copyBytes = copies.reduce(Int64(0)) { $0 + filmSize($1) }
    check(merged.quietLine == "40개를 PDF 하나로 합쳤어요 (첫 파일 옆에 저장)"
          && (pdf as NSString).lastPathComponent.precomposedStringWithCanonicalMapping == "IMG_4101 (압축) (합침).pdf".precomposedStringWithCanonicalMapping
          && CGPDFDocument(URL(fileURLWithPath: pdf) as CFURL)?.numberOfPages == 40,
          "film merge: merge --made put the forty smaller copies into one PDF beside them (\(merged.quietLine ?? ""))")
    check(images.count == 40 && images.allSatisfy { $0.width == 100 && $0.jpeg },
          "film merge: every page is a smaller copy, kept as JPEG (\(images.prefix(2)))")
    check(filmSize(pdf) < 3 * copyBytes + 200_000,
          "film merge: the PDF is about the copies' own size, not many times it (\(filmSize(pdf)) bytes for \(copyBytes))")

    // 3. The originals by --finder, over the pixel total: drawn smaller to fit, never refused; pages in name order.
    let whole: ArisConvertResult
    do { whole = try run(["merge", "--finder"], shuffled) } catch {
        return check(false, "film merge: forty pictures over the pixel total still merge (refused: \(ArisConvert.message(error, quiet: true)))")
    }
    let wholePDF = whole.made.first ?? ""
    let drawn = filmPDFImages(wholePDF)
    let total = drawn.reduce(0) { $0 + $1.width * $1.height }
    check(drawn.count == 40 && total <= limits.mergePixels && total > limits.mergePixels / 2 && drawn.allSatisfy(\.jpeg),
          "film merge: over the total, each picture is drawn smaller so all of them fit (\(total) of \(limits.mergePixels) pixels)")
    check(filmPageWidths(wholePDF) == (0..<40).map { 300 + $0 },
          "film merge: every page keeps its picture's own size, in Finder's name order (IMG_4101 first)")
    check(ArisConvert.pageSides([], budget: 10).isEmpty, "film merge: no pictures, no sizes")

    // A selection is many more than fifty files at most mostPicked, and over that the true reason is said.
    let many = (0..<201).map { trip + "/x\($0).jpg" }
    let over: String
    do { _ = try run(["merge", "--finder"], many); over = "" } catch { over = ArisConvert.message(error, quiet: true) }
    check(over == "201 files are picked and one call takes at most 200: ask the user to pick fewer",
          "film merge: over the most a selector picks, the refusal says how many and the limit (\(over))")
    let sixty = (0..<60).map { trip + "/missing \($0).jpg" }
    let sixtyRefusal: String
    do { _ = try run(["merge", "--finder"], sixty); sixtyRefusal = "" } catch { sixtyRefusal = ArisConvert.message(error, quiet: true) }
    check(!sixtyRefusal.contains("more than") && sixtyRefusal.contains("isn't there"),
          "film merge: sixty selected files are not too many (only a missing file stops it: \(sixtyRefusal))")
}

/// `--made`: only this question's, never a background job's; Finder's order; long calls.
private func runFilmFixMadeRuleTests() {
    let now = Date()
    let fresh = ArisMadeFiles.State(made: ["/Users/p/a (압축).jpg"], at: now.addingTimeInterval(-5))
    check(ArisConvertWords.parse(["merge", "--made"]) == ArisConvertWords.Call(verb: "merge", paths: [], options: [:], selector: .made)
          && ArisConvertWords.parse(["compress", "--made", "--max", "1600"])?.selector == .made
          && ArisConvertWords.parse(["merge", "--made", "--finder"]) == nil && ArisConvertWords.parse(["merge", "--made", "a.pdf"]) == nil,
          "made selector: --made stands for the files, once, never with paths or another selector")
    check(ArisConvert.selectorRefusal(.made, environment: [:], state: nil, made: nil, turnStarted: now)?.contains("no conversion in this question") == true
          && ArisConvert.selectorRefusal(.made, environment: [:], state: nil, made: fresh, turnStarted: now)?.contains("no conversion in this question") == true
          && ArisConvert.selectorRefusal(.made, environment: [:], state: nil, made: fresh, turnStarted: now.addingTimeInterval(-30)) == nil
          && ArisConvert.selectorRefusal(.made, environment: [ArisConvertWords.taskKey: "1"], state: nil, made: fresh, turnStarted: now.addingTimeInterval(-30))?
              .contains("background job") == true
          && ArisConvert.selectorRefusal(.made, environment: [:], state: nil, made: fresh, turnStarted: nil, now: now) == nil
          && ArisConvert.selectorRefusal(.made, environment: [:], state: nil, made: ArisMadeFiles.State(made: ["/a.jpg"], at: now.addingTimeInterval(-600)),
                                         turnStarted: nil, now: now) != nil,
          "made selector: only files a conversion made in this question (or just now for a relayed line), never in a background job")
    check(ArisConvert.finderOrder(["/t/IMG_4110.JPG", "/t/IMG_4102.JPG", "/t/IMG_4101.JPG", "/t/b 10.jpg", "/t/b 2.jpg"])
          == ["/t/b 2.jpg", "/t/b 10.jpg", "/t/IMG_4101.JPG", "/t/IMG_4102.JPG", "/t/IMG_4110.JPG"],
          "made selector: the Finder selection is taken in Finder's name order (2 before 10)")
    let elevenFiles = ["merge"] + (0..<11).map { "~/Pictures/IMG_\($0).jpg" }
    check(ArisConvertWords.isLong(elevenFiles) && !ArisConvertWords.isLong(["merge", "~/a.jpg", "~/b.jpg"])
          && ArisConvertWords.isLong(["merge", "--made"]) && ArisConvertWords.budget(elevenFiles) == ArisConvertWords.mediaLimit
          && ArisConvertWords.deadline(ArisConvertWords.parse(elevenFiles)!).timeIntervalSinceNow > 100,
          "made selector: more than ten named files get the long time (forty photos aren't stopped at 25 seconds)")
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("aris-filmfix-made-\(UUID().uuidString)").path
    defer { try? FileManager.default.removeItem(atPath: home) }
    ArisMadeFiles.save([], home: home)
    check(ArisMadeFiles.state(home: home) == nil, "made record: a conversion that made nothing keeps nothing")
    ArisMadeFiles.save(["/a/b.jpg", "relative.jpg", "/bad\nname.jpg"], home: home, now: now.addingTimeInterval(-3_600))
    check(ArisMadeFiles.state(home: home) == nil, "made record: an hour-old record is stale")
    ArisMadeFiles.save(["/a/b.jpg", "relative.jpg", "/bad\nname.jpg"], home: home)
    check(ArisMadeFiles.state(home: home)?.made == ["/a/b.jpg"], "made record: absolute paths without control characters only")
}

/// --made behind every brain's gate, as --finder is; the API brain's functions; the card; the prompt; and the auto
/// check's view of a selector (the film's false "Stopped: you didn't ask for this").
private func runFilmFixGateTests() {
    let tools = "/Users/p/.config/aris/aris-tools"
    let calls: [[String]] = [["merge", "--made"], ["merge", "--made", "--to", "pdf"], ["compress", "--made", "--max", "1600"], ["convert", "--made", "--to", "pdf"]]
    for words in calls {
        let line = ArisAPICatalog.command(tools: tools, argv: words)
        check(ArisTurnGate.bringsNothingIn(words) && ArisTurnGate.verdict(tool: "Bash", command: line, tools: tools, tainted: false) == .allow
              && ArisAutoScope.covers(words) && ArisAutoAction.read(words, title: "파일 합치기", detail: "방금 만든 파일") != nil,
              "made gate: \(words.joined(separator: " ")) is a clean file call the auto check may look at, like --finder")
    }
    check(ArisAPICatalog.argv(name: "files_merge", arguments: #"{"from":"made","to":"pdf"}"#) == ["merge", "--made", "--to", "pdf"]
          && ArisAPICatalog.argv(name: "files_compress", arguments: #"{"from":"made","max":1600}"#) == ["compress", "--made", "--max", "1600"]
          && ArisAPICatalog.argv(name: "files_merge", arguments: #"{"from":"elsewhere"}"#) == nil,
          "made gate: the API brain's files_merge and files_compress take from: \"made\"")
    let card = ArisCodexDriver.describe(command: ArisAPICatalog.command(tools: tools, argv: ["merge", "--made"]), tools: tools)
    let english = ArisCodexDriver.describe(command: ArisAPICatalog.command(tools: tools, argv: ["merge", "--made"]), tools: tools, request: "put them in one pdf")
    check(card == ("파일 합치기", "방금 만든 파일") && english.1 == "The files Aris just made",
          "made gate: the card says the files are the ones Aris just made (\(card.1) / \(english.1))")
    check(ArisFileRelay.card(["merge", "--made"], home: "/Users/p").detail == "방금 만든 파일", "made gate: agy's relay card says so too")
    for form in [ArisAgentPrompt.DesktopForm.functions, .relay, .shell] {
        let rule = ArisAgentPrompt.convertRule("aris-tools", form: form, gated: true)
        check(rule.contains(form == .functions ? "from: \"made\"" : "`--made`") && rule.contains("never the originals again"),
              "made gate: every brain is told to take a conversion's new files as --made for the next step (\(form))")
    }
    // The auto check: a selector's field says what it is; and a several-step request asks for each step.
    let finder = ArisAutoScope.call(["convert", "--finder", "--quality", "80", "--max", "1600"])
    let fields = finder.map(ArisAutoCheck.fields) ?? []
    check(fields.contains(["name": "--finder", "value": "the files the owner himself selected in Finder"])
          && fields.contains(["name": "--max", "value": "1600"]),
          "auto check: --finder is shown as the files the owner selected in Finder, not an empty field (\(fields))")
    let made = ArisAutoScope.call(["merge", "--made"]).map(ArisAutoCheck.fields) ?? []
    check(made == [["name": "--made", "value": "the new files the previous step of this request made"]], "auto check: --made is shown with its meaning")
    check(ArisAutoCheck.instruction.contains("picks its files by code") && ArisAutoCheck.instruction.contains("asks for each of those steps")
          && ArisAutoCheck.instruction.contains("When in doubt, never \"match\""),
          "auto check: the instruction says what a selector is and that a several-step request asks for each step (the rest unchanged)")
}

// MARK: - Bug 2: the composer keeps the sent words

private func runFilmFixComposerTests() {
    let sent = "make these smaller and put them in one pdf"
    check(ArisComposerClear.stillSent(sent, sent: sent) && !ArisComposerClear.stillSent("", sent: sent) && !ArisComposerClear.stillSent("x", sent: "")
          && !ArisComposerClear.stillSent(sent + " now", sent: sent),
          "composer: right after a send, a field still holding the sent words is cleared")
    check(ArisComposerClear.restored(old: "", new: sent + "m", sent: sent) == "m"
          && ArisComposerClear.restored(old: "", new: sent, sent: sent) == ""
          && ArisComposerClear.restored(old: "", new: sent + "한글", sent: sent) == "한글",
          "composer: the sent words written back with the next keystroke are taken out, the keystroke stays (the film's …pdfmake these…)")
    check(ArisComposerClear.restored(old: "", new: "m", sent: sent) == nil
          && ArisComposerClear.restored(old: "mak", new: "make", sent: sent) == nil
          && ArisComposerClear.restored(old: "", new: sent + " and mail it", sent: sent) == nil
          && ArisComposerClear.restored(old: "", new: "m", sent: "") == nil,
          "composer: ordinary typing (and a paste longer than a keystroke) is left as it is")
}
