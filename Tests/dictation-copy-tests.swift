// Tests for dictation with nowhere to type (mockups/dictation-copy, the owner's pick B with the 3-line fold): which insert
// outcomes count as "nowhere" (aris-agent's paste read by no app, or refused), that only those are copied, the fold,
// and the catalog's dictation.copy.* strings in Korean and English. Called from main.swift; uses its check().
import AppKit
import Foundation

func runDictationCopyTests() {
    dictationLandingTests()
    dictationFoldTests()
    dictationCopyStringTests()
}

private func dictationLandingTests() {
    check(ArisDictationCopy.landing(.typed(confirmed: true)) == .inserted,
          "dictation copy: a paste the app read is in place")
    check(ArisDictationCopy.landing(.typed(confirmed: false)) == .nowhere,
          "dictation copy: ⌘V pressed but no app read it -> nowhere to type")
    for problem in ["a password field has the keyboard", "aris-agent didn't answer", "won't type into Passwords",
                    "aris-agent needs Accessibility (System Settings → Privacy & Security)", "couldn't type it"] {
        check(ArisDictationCopy.landing(.failed(problem)) == .nowhere, "dictation copy: a failed insert (\(problem)) -> nowhere")
    }
    check(!ArisDictationCopy.copies(.typed(confirmed: true)), "dictation copy: never copied when it was inserted")
    check(ArisDictationCopy.copies(.typed(confirmed: false)) && ArisDictationCopy.copies(.failed("x")),
          "dictation copy: copied whenever it wasn't inserted")
    // The notch opens for the copied card (a dictation otherwise keeps it shut: its words are already in place).
    check(ArisNotchDecisions.turnNeedsPanel(training: false, dictating: true, phase: .speaking, dictationCopied: true),
          "dictation copy: the copied card opens the notch")
    check(!ArisNotchDecisions.turnNeedsPanel(training: false, dictating: true, phase: .speaking)
          && !ArisNotchDecisions.turnNeedsPanel(training: false, dictating: true, phase: .thinking),
          "dictation copy: typed or still being typed, the notch stays shut")
    let snapshot = ArisNotchSnapshot(session: ArisSession(), isTraining: false, isDictating: true, hasUnfinishedTask: false,
                                     taskJustFinished: false, dictationCopied: true)
    check(snapshot.dictationCopied && !ArisNotchSnapshot(session: ArisSession(), isTraining: false, isDictating: true,
                                                         hasUnfinishedTask: false, taskJustFinished: false).dictationCopied,
          "dictation copy: the notch's snapshot carries it")
    check(ArisDictationCopy.feedback == .milliseconds(1500), "dictation copy: 복사했어요 ✓ shows 1.5 s (A's feedback)")
    check(ArisDictationCopy.linger > ArisDictationCopy.feedback, "dictation copy: the card stays longer than the feedback")
}

/// The 3-line fold: short words show whole with no toggle; long words fold to 3 lines with 더 보기, open with 접기.
private func dictationFoldTests() {
    check(ArisDictationCopy.lineLimit == 3, "dictation fold: three lines")
    let short = ArisDictationCopy.Fold(overflows: false, open: false)
    check(short.lineLimit == nil && short.toggle == nil, "dictation fold: words that fit show whole, no 더 보기")
    let folded = ArisDictationCopy.Fold(overflows: true, open: false)
    check(folded.lineLimit == 3 && folded.toggle == .more, "dictation fold: long words fold to 3 lines with 더 보기")
    let opened = folded.toggled()
    check(opened.lineLimit == nil && opened.toggle == .less && opened.open, "dictation fold: 더 보기 opens it, then 접기")
    check(opened.toggled() == folded, "dictation fold: 접기 folds it again")
    check(short.toggled() == short, "dictation fold: nothing to toggle when it fits")
}

/// The catalog's dictation.copy.* strings as Xcode compiles them, into <dir>/<lang>.lproj/Localizable.strings.
private func dictationCopyCatalog() -> (strings: [String: [String: String]], bundle: Bundle)? {
    let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let catalog = tests.appendingPathComponent("../Aris/Localizable.xcstrings")
    guard let data = try? Data(contentsOf: catalog),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let all = json["strings"] as? [String: [String: Any]] else { return nil }
    var strings: [String: [String: String]] = [:]
    for (key, entry) in all where key.hasPrefix("dictation.copy.") {
        let localizations = entry["localizations"] as? [String: [String: [String: String]]] ?? [:]
        strings[key] = localizations.compactMapValues { $0["stringUnit"]?["value"] }
    }
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aris-dictcopy-\(UUID().uuidString)")
    for language in ["ko", "en"] {
        let lproj = dir.appendingPathComponent("\(language).lproj")
        try? FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
        let table = strings.compactMapValues { $0[language] }
        guard let plist = try? PropertyListSerialization.data(fromPropertyList: table, format: .binary, options: 0),
              (try? plist.write(to: lproj.appendingPathComponent("Localizable.strings"))) != nil else { return nil }
    }
    return Bundle(path: dir.path).map { (strings, $0) }
}

private func dictationCopyStringTests() {
    let (language, bundle) = (ArisDictationCopy.language, ArisDictationCopy.bundle)
    defer { (ArisDictationCopy.language, ArisDictationCopy.bundle) = (language, bundle) }

    guard let (strings, catalog) = dictationCopyCatalog() else { return check(false, "dictation copy words: the catalog reads") }
    let used = ["dictation.copy.tag", "dictation.copy.again", "dictation.copy.done", "dictation.copy.more", "dictation.copy.less"]
    check(Set(strings.keys) == Set(used), "dictation copy words: every key the card uses is in the catalog, and no other")
    check(used.allSatisfy { strings[$0]?["ko"]?.isEmpty == false && strings[$0]?["en"]?.isEmpty == false },
          "dictation copy words: each one in Korean and English")

    ArisDictationCopy.use("ko", in: catalog)
    check(ArisDictationCopy.tag == "입력할 곳이 없어서 복사해 뒀어요 · ⌘V로 붙여 넣으세요",
          "dictation copy words, Korean: the mockup's tag")
    check(ArisDictationCopy.again == "다시 복사" && ArisDictationCopy.done == "복사했어요",
          "dictation copy words, Korean: 다시 복사, then 복사했어요")
    check(ArisDictationCopy.more == "더 보기" && ArisDictationCopy.less == "접기", "dictation copy words, Korean: 더 보기 / 접기")
    check(ArisDictationCopy.label(.more) == "더 보기" && ArisDictationCopy.label(.less) == "접기",
          "dictation copy words, Korean: the fold's toggle says them")

    ArisDictationCopy.use("en", in: catalog)
    check(ArisDictationCopy.tag == "Nowhere to type, so it's copied · Paste with ⌘V" && ArisDictationCopy.again == "Copy again"
          && ArisDictationCopy.done == "Copied" && ArisDictationCopy.more == "Show more" && ArisDictationCopy.less == "Show less",
          "dictation copy words, English: from the catalog")
}
