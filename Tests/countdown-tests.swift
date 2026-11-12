// Tests for a dictated message's countdown in the confirm card (the owner's pick C, mockups/countdown-card): the ring's
// progress (sweeping, and by whole seconds under Reduce Motion), the end states in the session (cancelled and sent,
// kept through the answer and the AI's work, gone with what comes next), and the card's words in Korean and English.
// Called from main.swift; uses its check().
import Foundation

func runCountdownTests() {
    countdownRingTests()
    countdownEndTests()
    countdownCopyTests()
}

private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

private func countdownRingTests() {
    check(ArisConfirmReply.countdownSeconds == 3, "countdown ring: three seconds")
    check(ArisCountdown.remaining(elapsed: nil, stepped: false) == 1 && ArisCountdown.remaining(elapsed: nil, stepped: true) == 1,
          "countdown ring: full while Aris still says the message")
    check(ArisCountdown.remaining(elapsed: 0, stepped: false) == 1 && ArisCountdown.remaining(elapsed: -0.2, stepped: false) == 1,
          "countdown ring: full at the start (and never more than full)")
    check(near(ArisCountdown.remaining(elapsed: 0.4, stepped: false), 1 - 0.4 / 3)
          && near(ArisCountdown.remaining(elapsed: 1.4, stepped: false), 1 - 1.4 / 3)
          && near(ArisCountdown.remaining(elapsed: 2.4, stepped: false), 0.2),
          "countdown ring: empties linearly with the clock (t = 0.4, 1.4, 2.4 s)")
    check(ArisCountdown.remaining(elapsed: 3, stepped: false) == 0 && ArisCountdown.remaining(elapsed: 7, stepped: false) == 0,
          "countdown ring: empty when it ran out, and stays empty")
    check(ArisCountdown.remaining(elapsed: 0.4, stepped: true) == 1 && ArisCountdown.remaining(elapsed: 0.99, stepped: true) == 1,
          "countdown ring, Reduce Motion: no sweep within the first second")
    check(near(ArisCountdown.remaining(elapsed: 1, stepped: true), 2.0 / 3) && near(ArisCountdown.remaining(elapsed: 1.4, stepped: true), 2.0 / 3)
          && near(ArisCountdown.remaining(elapsed: 2.4, stepped: true), 1.0 / 3) && ArisCountdown.remaining(elapsed: 3, stepped: true) == 0,
          "countdown ring, Reduce Motion: a third drops at each whole second")
    var last = 1.0, falls = true
    for step in 0...300 {
        let left = ArisCountdown.remaining(elapsed: Double(step) / 100, stepped: false)
        falls = falls && left <= last && left >= 0 && left <= 1
        last = left
    }
    check(falls, "countdown ring: never grows back, always within 0 and 1")
}

private func countdownEndTests() {
    let ask = ArisConfirmation(id: "c1", title: "엄마", detail: "곧 갈게", countdown: true, spoken: "엄마한테 ‘곧 갈게’ 보낼게요")
    let asking = ArisSession().listening().hearing("엄마한테 곧 간다고 문자 보내줘").thinking().working("메시지 보내는 중").asking(ask)
    check(asking.countdownEnd == nil, "countdown end: none while it counts")

    let sent = asking.counted(sent: true)
    check(sent.countdownEnd == ArisCountdownEnd(to: "엄마", message: "곧 갈게", sent: true) && sent.question == ask && sent.phase == .speaking,
          "countdown end, sent: the card says so while it's still up")
    let cancelled = asking.counted(sent: false)
    check(cancelled.countdownEnd?.sent == false && cancelled.question == ask, "countdown end, cancelled: the card says so")
    check(cancelled.counted(sent: true).countdownEnd?.sent == true, "countdown end: the final outcome replaces an early one")

    let after = sent.answered()
    check(after.phase == .thinking && after.question == nil && after.countdownEnd == sent.countdownEnd,
          "countdown end: kept through the answer to it")
    check(sent.answered(delivered: false).countdownEnd == nil && sent.answered(delivered: false).question == nil,
          "countdown end: dropped when the agent didn't get the answer")
    let working = after.working("메시지 보내는 중")
    check(working.countdownEnd == sent.countdownEnd && working.phase == .thinking, "countdown end: kept while the AI works after it")
    check(after.answering("보냈어요").countdownEnd == nil, "countdown end: gone with the AI's answer")
    check(after.failing("안 됐어요").countdownEnd == nil && after.done().countdownEnd == nil && after.listening().countdownEnd == nil,
          "countdown end: gone with a failure, the end of the turn or a new one")

    let plain = ArisConfirmation(id: "c2", title: "메시지 보내기", detail: "받는 사람: 엄마")
    let question = ArisSession().listening().hearing("엄마한테 보내").thinking().asking(plain)
    check(question.counted(sent: true) == question, "countdown end: only a countdown card has one")
    check(ArisSession().counted(sent: true) == ArisSession(), "countdown end: nothing to end without a card")
    check(question.answered().countdownEnd == nil, "countdown end: an ordinary card's answer has none")
}

/// The catalog's countdown.* strings as Xcode compiles them, into <dir>/<lang>.lproj/Localizable.strings.
private func countdownCatalog() -> (strings: [String: [String: String]], bundle: Bundle)? {
    let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let catalog = tests.appendingPathComponent("../Aris/Localizable.xcstrings")
    guard let data = try? Data(contentsOf: catalog),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let all = json["strings"] as? [String: [String: Any]] else { return nil }
    var strings: [String: [String: String]] = [:]
    for (key, entry) in all where key.hasPrefix("countdown.") {
        let localizations = entry["localizations"] as? [String: [String: [String: String]]] ?? [:]
        strings[key] = localizations.compactMapValues { $0["stringUnit"]?["value"] }
    }
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aris-countdown-\(UUID().uuidString)")
    for language in ["ko", "en"] {
        let lproj = dir.appendingPathComponent("\(language).lproj")
        try? FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
        let table = strings.compactMapValues { $0[language] }
        guard let plist = try? PropertyListSerialization.data(fromPropertyList: table, format: .binary, options: 0),
              (try? plist.write(to: lproj.appendingPathComponent("Localizable.strings"))) != nil else { return nil }
    }
    return Bundle(path: dir.path).map { (strings, $0) }
}

private func countdownCopyTests() {
    check(ArisCountdownCopy.objectParticle(after: "곧 갈게") == "를" && ArisCountdownCopy.objectParticle(after: "집에 왔음") == "을"
          && ArisCountdownCopy.objectParticle(after: "곧 갈게!") == "를" && ArisCountdownCopy.objectParticle(after: "먼저 먹어 밥!!") == "을",
          "countdown words: 을 after a final consonant, 를 after a vowel, trailing marks skipped")
    check(ArisCountdownCopy.objectParticle(after: "ok") == "를" && ArisCountdownCopy.objectParticle(after: "") == "를",
          "countdown words: anything not Hangul takes 를")

    let (language, bundle) = (ArisCountdownCopy.language, ArisCountdownCopy.bundle)
    defer { (ArisCountdownCopy.language, ArisCountdownCopy.bundle) = (language, bundle) }
    ArisCountdownCopy.use("en", in: Bundle(path: NSTemporaryDirectory())!)
    check(ArisCountdownCopy.sent(to: "Mom", message: "on my way") == "Sent ‘on my way’ to Mom",
          "countdown words: the English default has no particle")

    guard let (strings, catalog) = countdownCatalog() else { return check(false, "countdown words: the catalog reads") }
    let used = ["countdown.title", "countdown.to", "countdown.message", "countdown.hint", "countdown.cancel", "countdown.send",
                "countdown.notsent", "countdown.cancelled", "countdown.sent", "countdown.sending"]
    check(Set(strings.keys) == Set(used), "countdown words: every key the card uses is in the catalog, and no other")
    check(used.allSatisfy { strings[$0]?["ko"]?.isEmpty == false && strings[$0]?["en"]?.isEmpty == false },
          "countdown words: each one in Korean and English")
    let arguments = { (text: String) in text.components(separatedBy: "$@").count - 1 }
    check(arguments(strings["countdown.sent"]?["ko"] ?? "") == 3 && arguments(strings["countdown.sent"]?["en"] ?? "") == 3,
          "countdown words: the sent line takes the same three arguments in both languages")

    ArisCountdownCopy.use("ko", in: catalog)
    check(ArisCountdownCopy.hint == "“취소”라고 하면 멈춰요" && ArisCountdownCopy.title == "메시지 보내기"
          && ArisCountdownCopy.cancel == "취소" && ArisCountdownCopy.send == "보내기",
          "countdown words, Korean: the mockup's title, hint and buttons")
    check(ArisCountdownCopy.sent(to: "엄마", message: "곧 갈게") == "엄마에게 ‘곧 갈게’를 보냈어요"
          && ArisCountdownCopy.sent(to: "아빠", message: "다 왔음") == "아빠에게 ‘다 왔음’을 보냈어요",
          "countdown words, Korean: sent, with the right particle")
    check(ArisCountdownCopy.notSent == "보내지 않았어요" && ArisCountdownCopy.cancelled == "취소했어요",
          "countdown words, Korean: cancelled as the mockup says it")
    ArisCountdownCopy.use("en", in: catalog)
    check(ArisCountdownCopy.sent(to: "Mom", message: "on my way") == "Sent ‘on my way’ to Mom" && ArisCountdownCopy.hint == "Say “cancel” to stop"
          && ArisCountdownCopy.notSent == "Not sent",
          "countdown words, English: from the catalog, no particle")
}
