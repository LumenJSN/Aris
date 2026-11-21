// Offscreen draws of confirm cards through the real ArisConfirmCard and ArisEditableRows, read back from the drawn
// view's accessibility tree (never the screen; the window is never ordered on screen). Every line a card was built
// with must be drawn: seventh VM run, item 1 (aris-vmcheck cap7/J1-card1.jpg, J4-valuecard.jpg), the values card of a
// lesson whose text goes on a new line said "It goes on a new line (↵)" in its text, and the card drew only its title
// and its field. Each card here is built by the code that builds it for real (ArisTeachCopy, ArisAskPlan) and shaped
// into the app's ArisConfirmation the way ArisMCPCards.put shapes it.
import AppKit
import SwiftUI
import Vision

/// Stand-ins for what the card calls in the app (not built here).
@MainActor final class ArisController {
    static let shared = ArisController()
    var session = ArisSession()
    func answerQuestion(_ allow: Bool) {}
}

@MainActor enum KeyboardFocus {
    static func arm(_ armed: Bool) {}
}

/// A settings page named in an answer (ArisSession.answering), as is.
enum ArisSettingsPath {
    static func shown(_ text: String, english: Bool = false) -> String { text }
}

/// ArisGlass's opening curve and the settings' press style, as the card uses them.
enum ArisGlass {
    static let opening = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.28)
}

struct ArisPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

struct ArisDarkGlassButton: View {
    var body: some View { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.15)) }
}

/// A card as aris-agent streams it: ArisMCPCards.put makes each field's label its key.
func shaped(id: String, _ card: ArisTeachCopy.Card, fields: [(key: String, value: String)] = []) -> ArisConfirmation {
    ArisConfirmation(id: id, title: card.title, detail: card.detail, full: card.full,
                     fields: fields.map { ArisCardField(key: $0.key, label: $0.key, role: .text, value: $0.value) })
}

/// The card drawn offscreen (at 2x, so the text reads cleanly) and read back with Vision's text recognition: what is
/// really in its pixels, nothing the view merely holds.
@MainActor func bitmap(_ question: ArisConfirmation, wait: Double = ArisCardHold.hold + 0.5, before: () -> Void = {}) -> NSBitmapImageRep? {
    ArisCardEditor.shared.start(question)
    let card = ArisConfirmCard(question: question, budget: 2_000).frame(width: 432).background(Color.black).environment(\.colorScheme, .dark)
    let host = NSHostingView(rootView: card)
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 432, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = host
    host.frame = CGRect(origin: .zero, size: CGSize(width: 432, height: max(host.fittingSize.height, 100)))
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.4))
    host.frame = CGRect(origin: .zero, size: CGSize(width: 432, height: max(host.fittingSize.height, 100)))
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.4))
    before()
    // Past the click hold (ArisCardHold.hold) and the button's ease into full strength.
    RunLoop.main.run(until: Date().addingTimeInterval(wait))
    defer { window.contentView = nil }
    let scale: CGFloat = 2
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * scale), pixelsHigh: Int(host.bounds.height * scale),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { return nil }
    rep.size = host.bounds.size
    host.cacheDisplay(in: host.bounds, to: rep)
    if let dir = ProcessInfo.processInfo.environment["CARD_TEXT_PNG"], let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(question.id + ".png"))
    }
    return rep
}

/// The card drawn offscreen (at 2x, so the text reads cleanly) and read back with Vision's text recognition: what is
/// really in its pixels, nothing the view merely holds.
@MainActor func drawnText(_ question: ArisConfirmation) -> [String] {
    guard let image = bitmap(question)?.cgImage else { return [] }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["ko-KR", "en-US"]
    request.usesLanguageCorrection = false
    try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
    return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
}

/// How bright the yes button's corner of a drawn card is (its footer's right end, where 허용 sits): the mean of the
/// pixels' brightest channel.
func allowBrightness(_ rep: NSBitmapImageRep) -> Double {
    let width = rep.pixelsWide, height = rep.pixelsHigh
    var sum = 0.0, count = 0
    for y in (height - 2 * 50)..<(height - 2 * 14) {
        for x in (width - 2 * 110)..<(width - 2 * 20) {
            guard let color = rep.colorAt(x: x, y: y) else { continue }
            sum += Double(max(color.redComponent, color.greenComponent, color.blueComponent))
            count += 1
        }
    }
    return count == 0 ? 0 : sum / Double(count)
}

/// A line's words as compared: letters, digits and Hangul only, lowercased (the recognizer's punctuation and spacing
/// vary; the words don't).
func words(_ text: String) -> [String] {
    text.lowercased().split { !($0.isLetter || $0.isNumber) }.map(String.init).filter { $0.count >= 2 || $0.unicodeScalars.contains { $0.value >= 0xAC00 } }
}

/// Whether a built line is in the drawn text: most of its words are (a line that isn't drawn has none of them).
func drawn(_ line: String, in blob: String) -> Bool {
    let wanted = words(line)
    guard !wanted.isEmpty else { return true }
    let found = wanted.filter { blob.contains($0) }.count
    return Double(found) / Double(wanted.count) >= 0.6
}

/// The text a card was built with that isn't drawn: each line of its details (a "label: value" row as its two parts,
/// a field's line as its label and its value), and its title.
@MainActor func missing(_ question: ArisConfirmation) -> [String] {
    let blob = words(drawnText(question).joined(separator: " ")).joined(separator: " ")
    var wanted = [question.title]
    for line in question.detail.split(separator: "\n").map(String.init) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
        let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 2, parts[0].count <= 14, !parts[0].contains("/") { wanted += parts.filter { !$0.isEmpty } } else { wanted.append(line.trimmingCharacters(in: .whitespaces)) }
    }
    return wanted.filter { !drawn($0, in: blob) }
}

var failures = 0
@MainActor func expect(_ ok: Bool, _ what: String) {
    print((ok ? "ok   " : "FAIL ") + what)
    if !ok { failures += 1 }
}

@MainActor func run() {
    _ = NSApplication.shared
    // "줄 추가", taught in an empty document: its text begins a line (J-taught.json).
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    var typed = ArisTeachStep(action: .type, app: "TextEdit", bundle: "com.apple.TextEdit")
    typed.label = ArisTeachGeneralise.bodyLabel
    typed.parameter = "p1"
    typed.place = .end
    typed.role = "textArea"
    typed.startsLine = true
    typed.fromApp = false
    let lesson = ArisTeachProcedure(name: "줄 추가", steps: [ArisTeachStep(action: .open, app: "TextEdit", bundle: "com.apple.TextEdit"), typed],
                                    parameters: [ArisTeachParameter(key: "p1", label: ArisTeachGeneralise.bodyLabel, example: "Added line", app: "TextEdit", fromApp: false)],
                                    created: start)
    let missingValues = ArisTeachReplay.missing(lesson, given: [:])
    for english in [true, false] {
        let asked = ArisTeachCopy.valuesCard(lesson, missing: missingValues, english: english)
        let card = shaped(id: "values-\(english)", asked.card, fields: asked.fields)
        let gone = missing(card)
        expect(gone.isEmpty, "the values card (\(english ? "English" : "Korean")) draws all of its text\(gone.isEmpty ? "" : ": not drawn \(gone)")")
        let note = asked.card.detail.split(separator: "\n").map(String.init).first { $0.contains("↵") } ?? ""
        let blob = words(drawnText(card).joined(separator: " ")).joined(separator: " ")
        expect(!note.isEmpty && drawn(note, in: blob), "the values card (\(english ? "English" : "Korean")) shows its line saying the text goes on a new line (↵)")
    }
    // The go-on card, the save card, the delete card: plain details, every row drawn.
    let goOn = ArisTeachCopy.goOnCard(lesson, failedAt: 0, why: "no app on this Mac is called ‘TextEdit’", english: false)
    let save = ArisTeachCopy.saveCard(lesson, replacing: false, english: false)
    let delete = ArisTeachCopy.deleteCard(lesson, english: false)
    for (name, built) in [("go-on", goOn), ("save", save), ("delete", delete)] {
        let gone = missing(shaped(id: name, built))
        expect(gone.isEmpty, "the \(name) card draws all of its text\(gone.isEmpty ? "" : ": not drawn \(gone)")")
    }
    // An editable card whose text has a reason above its fields (a connected service's card: ArisMCPPolicy.detail).
    let service = ArisTeachCopy.Card(title: "Slack · send_message", detail: "읽은 글 때문에 다시 물어요\nchannel: #general\ntext: hello", full: nil)
    let serviceCard = shaped(id: "service", service, fields: [("channel", "#general"), ("text", "hello")])
    let goneService = missing(serviceCard)
    expect(goneService.isEmpty, "a service card draws its reason and its fields\(goneService.isEmpty ? "" : ": not drawn \(goneService)")")
    // Any editable card's text that doesn't end with its fields' own lines is still drawn whole (nothing built is dropped).
    let odd = ArisTeachCopy.Card(title: "확인", detail: "이 줄은 필드 줄로 끝나지 않아요", full: nil)
    let goneOdd = missing(shaped(id: "odd", odd, fields: [("text", "hello")]))
    expect(goneOdd.isEmpty, "an editable card whose text doesn't end with its fields still draws that text\(goneOdd.isEmpty ? "" : ": not drawn \(goneOdd)")")
    // Seventh VM run, item 3: the yes button in its short click hold is drawn unlike a disabled one (brighter, with its
    // line), and at full strength once the hold is over.
    let plain = ArisConfirmation(id: "hold", title: "확인", detail: "할 일 추가: 우유")
    // The card has been read to its end (it fits: ArisCardRead), so only the hold or a value that doesn't read dims it.
    func readToEnd(_ id: String) {
        ArisCardReadLive.shared.shown(id)
        ArisCardReadLive.shared.scrolled(card: id, offset: 0, visible: 200, content: 200)
    }
    let heldCard = ArisConfirmation(id: "held", title: plain.title, detail: plain.detail)
    let held = bitmap(heldCard) { readToEnd("held"); ArisCardStill.shared.shown("someone-else") }.map(allowBrightness) ?? 0
    let ready = bitmap(plain) { readToEnd("hold"); ArisCardStill.shared.shown("hold") }.map(allowBrightness) ?? 0
    let badTime = [ArisCardField(key: "at", label: "때", role: .time, value: "내일 3시")]
    let disabledCard = ArisConfirmation(id: "disabled", title: "미리 알림", detail: ArisCardEdit.shown(badTime, ArisCardEdit.values(badTime)), fields: badTime)
    let disabled = bitmap(disabledCard) { readToEnd("disabled"); ArisCardStill.shared.shown("disabled") }.map(allowBrightness) ?? 0
    // Eighth VM run, item 2 (cap8/T1-pair.jpg): a held button read as a ready one. It is clearly dimmer than a ready one now.
    expect(ready > held * 1.15 && abs(held - disabled) > 0.002, "the held yes button is clearly not a ready one, and unlike a disabled one (disabled \(disabled), held \(held), ready \(ready))")
    // A click on yes during the hold: the card says it wasn't taken.
    let noteCard = ArisConfirmation(id: "note", title: plain.title, detail: plain.detail)
    var noteText: [String] = []
    if let image = bitmap(noteCard, wait: 0.6, before: { readToEnd("note"); ArisCardStill.shared.shown("note"); ArisCardStill.shared.refusedClick(card: "note") })?.cgImage {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        noteText = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }
    let noteBlob = words(noteText.joined(separator: " ")).joined(separator: " ")
    expect(drawn(ArisConfirmWords.notYet(english: true), in: noteBlob) || drawn(ArisConfirmWords.notYet(english: false), in: noteBlob),
           "a click on yes during the hold draws the not-taken note (\(noteText))")
    // jv-voiceyes: a card that waits for a click only says it does not hear, and one that listens says so, beside
    // its buttons, which stay drawn (the user said "응" to a card with no microphone).
    for (hearing, english) in [(ArisCardHearing.clickOnly, false), (.listening, false), (.clickOnly, true), (.listening, true)] {
        let id = "ear-\(hearing)-\(english)"
        let earCard = ArisConfirmation(id: id, title: english ? "Run the script" : "확인", detail: english ? "Command: ls" : "할 일 추가: 우유")
        var earText: [String] = []
        if let image = bitmap(earCard, before: { readToEnd(id); ArisCardStill.shared.shown(id); ArisCardEar.shared.set(hearing, card: id) })?.cgImage {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ko-KR", "en-US"]
            request.usesLanguageCorrection = false
            try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            earText = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        }
        let earBlob = words(earText.joined(separator: " ")).joined(separator: " ")
        expect(drawn(ArisCardHearing.words(hearing, english: english), in: earBlob)
               && drawn(ArisConfirmWords.cancel(english: english), in: earBlob) && drawn(ArisConfirmWords.allow(nil, sends: false, english: english), in: earBlob),
               "the card draws its \(hearing) line with both buttons (\(english ? "English" : "Korean"): \(earText))")
        ArisCardEar.shared.clear(card: id)
    }
    // Another card's sign is never drawn on this one.
    let deaf = ArisConfirmation(id: "ear-other", title: plain.title, detail: plain.detail)
    var deafText: [String] = []
    if let image = bitmap(deaf, before: { readToEnd("ear-other"); ArisCardStill.shared.shown("ear-other"); ArisCardEar.shared.set(.listening, card: "someone-else") })?.cgImage {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        deafText = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }
    expect(!deafText.isEmpty && !drawn(ArisCardHearing.words(.listening, english: false), in: words(deafText.joined(separator: " ")).joined(separator: " ")),
           "a card shows no listening line that belongs to another card (\(deafText))")
    if failures > 0 {
        print("CARD TEXT: \(failures) card(s) leave built text undrawn")
        exit(1)
    }
    print("CARD TEXT OK")
}

@main
struct Main {
    static func main() {
        MainActor.assumeIsolated { run() }
        exit(0)
    }
}
