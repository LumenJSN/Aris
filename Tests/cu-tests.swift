// Tests for jv-cu: Aris's own computer-use engine made to work in common cases (keyboard layouts and the Korean
// input method, the text ladder and what it learns, the focus rule, off-screen windows, Accessibility timeouts, the
// vision picture's size and its point mapping, dictation never waiting behind computer use, aris-tools keys through
// the engine, one default engine, a stale Screen Recording answer, a click's one recovery). Called from main.swift;
// uses its check(). Nothing here posts an event, reads a real window, takes a picture or changes the input source.
import Carbon
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private let cuRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func cuSource(_ path: String) -> String { (try? String(contentsOf: cuRoot.appendingPathComponent(path), encoding: .utf8)) ?? "" }

func runComputerUseTests() {
    cuLayoutTests()
    cuMethodTests()
    cuLadderTests()
    cuMemoryTests()
    cuFocusGapTests()
    cuWindowMergeTests()
    cuBudgetTests()
    cuVisionScaleTests()
    cuLockTests()
    cuScreenAccessTests()
    cuEngineChoiceTests()
    cuClickRecoveryTests()
    cuKeysRouteTests()
    cuBrowserTests()
    cuWiringTests()
}

// MARK: - Fixture layouts (what UCKeyTranslate gives for each key: plain, shift, option; with ⌘ the plain one)

/// key code: (plain, shift)
private let usKeys: [CGKeyCode: (String, String)] = [
    0: ("a", "A"), 1: ("s", "S"), 2: ("d", "D"), 3: ("f", "F"), 4: ("h", "H"), 5: ("g", "G"), 6: ("z", "Z"), 7: ("x", "X"), 8: ("c", "C"), 9: ("v", "V"),
    10: ("§", "±"), 11: ("b", "B"), 12: ("q", "Q"), 13: ("w", "W"), 14: ("e", "E"), 15: ("r", "R"), 16: ("y", "Y"), 17: ("t", "T"), 18: ("1", "!"),
    19: ("2", "@"), 20: ("3", "#"), 21: ("4", "$"), 22: ("6", "^"), 23: ("5", "%"), 24: ("=", "+"), 25: ("9", "("), 26: ("7", "&"), 27: ("-", "_"),
    28: ("8", "*"), 29: ("0", ")"), 30: ("]", "}"), 31: ("o", "O"), 32: ("u", "U"), 33: ("[", "{"), 34: ("i", "I"), 35: ("p", "P"), 37: ("l", "L"),
    38: ("j", "J"), 39: ("'", "\""), 40: ("k", "K"), 41: (";", ":"), 42: ("\\", "|"), 43: (",", "<"), 44: ("/", "?"), 45: ("n", "N"), 46: ("m", "M"),
    47: (".", ">"), 50: ("`", "~"),
]

private let germanKeys: [CGKeyCode: (String, String)] = [
    0: ("a", "A"), 1: ("s", "S"), 2: ("d", "D"), 3: ("f", "F"), 4: ("h", "H"), 5: ("g", "G"), 6: ("y", "Y"), 7: ("x", "X"), 8: ("c", "C"), 9: ("v", "V"),
    10: ("^", "°"), 11: ("b", "B"), 12: ("q", "Q"), 13: ("w", "W"), 14: ("e", "E"), 15: ("r", "R"), 16: ("z", "Z"), 17: ("t", "T"), 18: ("1", "!"),
    19: ("2", "\""), 20: ("3", "§"), 21: ("4", "$"), 22: ("6", "&"), 23: ("5", "%"), 24: ("´", "`"), 25: ("9", ")"), 26: ("7", "/"), 27: ("ß", "?"),
    28: ("8", "("), 29: ("0", "="), 30: ("+", "*"), 31: ("o", "O"), 32: ("u", "U"), 33: ("ü", "Ü"), 34: ("i", "I"), 35: ("p", "P"), 37: ("l", "L"),
    38: ("j", "J"), 39: ("ä", "Ä"), 40: ("k", "K"), 41: ("ö", "Ö"), 42: ("#", "'"), 43: (",", ";"), 44: ("-", "_"), 45: ("n", "N"), 46: ("m", "M"),
    47: (".", ":"), 50: ("<", ">"),
]
/// German's ⌥ layer for the characters the tests use (@ is ⌥L, € is ⌥E).
private let germanOption: [CGKeyCode: String] = [37: "@", 14: "€"]

private let frenchKeys: [CGKeyCode: (String, String)] = [
    0: ("q", "Q"), 1: ("s", "S"), 2: ("d", "D"), 3: ("f", "F"), 4: ("h", "H"), 5: ("g", "G"), 6: ("w", "W"), 7: ("x", "X"), 8: ("c", "C"), 9: ("v", "V"),
    10: ("@", "#"), 11: ("b", "B"), 12: ("a", "A"), 13: ("z", "Z"), 14: ("e", "E"), 15: ("r", "R"), 16: ("y", "Y"), 17: ("t", "T"), 18: ("&", "1"),
    19: ("é", "2"), 20: ("\"", "3"), 21: ("'", "4"), 22: ("§", "6"), 23: ("(", "5"), 24: ("-", "_"), 25: ("ç", "9"), 26: ("è", "7"), 27: (")", "°"),
    28: ("!", "8"), 29: ("à", "0"), 30: ("$", "*"), 31: ("o", "O"), 32: ("u", "U"), 33: ("^", "¨"), 34: ("i", "I"), 35: ("p", "P"), 37: ("l", "L"),
    38: ("j", "J"), 39: ("ù", "%"), 40: ("k", "K"), 41: ("m", "M"), 42: ("`", "£"), 43: (";", "."), 44: ("=", "+"), 45: ("n", "N"), 46: (",", "?"),
    47: (":", "/"), 50: ("<", ">"),
]

private func cuMap(_ keys: [CGKeyCode: (String, String)], option: [CGKeyCode: String] = [:]) -> ArisKeyMap {
    ArisKeyMap.build { code, layer in
        switch layer {
        case .plain, .command: return keys[code]?.0
        case .shift: return keys[code]?.1
        case .option: return option[code]
        case .shiftOption: return nil
        }
    }
}

private let usBoard = ArisKeyboardState(sourceId: "com.apple.keylayout.US", layoutId: "com.apple.keylayout.US", inputMethod: false, map: cuMap(usKeys))
private let germanBoard = ArisKeyboardState(sourceId: "com.apple.keylayout.German", layoutId: "com.apple.keylayout.German", inputMethod: false,
                                            map: cuMap(germanKeys, option: germanOption))
private let frenchBoard = ArisKeyboardState(sourceId: "com.apple.keylayout.French", layoutId: "com.apple.keylayout.French", inputMethod: false, map: cuMap(frenchKeys))
/// Korean 2-Set: an input method; shortcuts go by the ASCII-capable layout behind it (US/ABC).
private let koreanBoard = ArisKeyboardState(sourceId: "com.apple.inputmethod.Korean.2SetKorean", layoutId: "com.apple.keylayout.ABC",
                                            inputMethod: ArisKeyboardState.isInputMethod(type: kTISTypeKeyboardInputMode as String, asciiCapable: false),
                                            map: cuMap(usKeys))

// MARK: - Layouts

private func cuLayoutTests() {
    typealias I = ArisNativeInput
    func key(_ chord: String, _ board: ArisKeyboardState) -> CGKeyCode? { I.chord(chord, keyboard: board)?.key }
    // ⌘A pressed ⌘Q on AZERTY and quit the app; ⌘Z was ⌘Y on QWERTZ (the US places off the main thread).
    check(key("cmd+a", frenchBoard) == 12 && key("cmd+q", frenchBoard) == 0 && key("cmd+z", frenchBoard) == 13 && key("cmd+w", frenchBoard) == 6,
          "layouts: on French AZERTY ⌘A, ⌘Q, ⌘Z and ⌘W press the keys that type those letters")
    check(key("cmd+m", frenchBoard) == 41, "layouts: AZERTY's m is where US has ;")
    check(key("cmd+z", germanBoard) == 16 && key("cmd+y", germanBoard) == 6 && key("cmd+c", germanBoard) == 8, "layouts: on German QWERTZ ⌘Z and ⌘Y swap places, ⌘C stays")
    check(key("cmd+z", usBoard) == 6 && key("cmd+v", usBoard) == 9 && key("ctrl+a", usBoard) == 0, "layouts: US places on a US layout")
    check(key("cmd+1", frenchBoard) == 18 && I.chord("cmd+1", keyboard: frenchBoard)?.flags == .maskCommand,
          "layouts: ⌘1 on AZERTY is ⌘ on the key whose ⇧ types 1 (no ⇧ added to a shortcut)")
    check(key("cmd+a", koreanBoard) == 0 && key("cmd+v", koreanBoard) == 9, "layouts: with Korean 2-Set on, shortcuts go by the ASCII layout behind it")
    for board in [usBoard, germanBoard, frenchBoard, koreanBoard] {
        check(key("return", board) == 36 && key("tab", board) == 48 && key("escape", board) == 53 && key("left", board) == 123, "layouts: named keys are the same on \(board.layoutId)")
    }
    // Characters pressed alone: the stroke that types them there, its ⇧ or ⌥ added.
    let bang = I.chord("!", keyboard: usBoard)
    check(bang?.key == 18 && bang?.flags.contains(.maskShift) == true && bang?.character == true, "layouts: ! alone on US is ⇧1")
    let at = I.chord("@", keyboard: germanBoard)
    check(at?.key == 37 && at?.flags.contains(.maskAlternate) == true && at?.flags.contains(.maskShift) == false, "layouts: @ alone on German is ⌥L")
    let accent = I.chord("é", keyboard: frenchBoard)
    check(accent?.key == 19 && accent?.flags == [], "layouts: é alone on French is its own key, no modifier")
    check(I.chord("A", keyboard: usBoard)?.flags.contains(.maskShift) == true && I.chord("a", keyboard: usBoard)?.flags == [], "layouts: a capital alone is ⇧ on its letter")
    check(key("cmd+a", germanBoard) == 0 && key("q", frenchBoard) == 0, "layouts: a letter in the same place stays there")
    check(I.chord("cmd+a", keyboard: nil)?.key == 0, "layouts: no keyboard read: the US places")
    // The map itself.
    let map = cuMap(usKeys)
    check(map.stroke(for: "a") == ArisKeyMap.Stroke(key: 0) && map.stroke(for: "A") == ArisKeyMap.Stroke(key: 0, shift: true), "layouts: the map's strokes")
    check(map.stroke(for: "가") == nil && map.commandKey(for: "가") == nil, "layouts: a character no key types has no stroke")
    check(ArisKeyMap.Layer.shift.modifierState == 2 && ArisKeyMap.Layer.option.modifierState == 8 && ArisKeyMap.Layer.command.modifierState == 1,
          "layouts: UCKeyTranslate's modifier states for ⇧, ⌥ and ⌘")
}

// MARK: - Text by the keyboard in use

private func cuMethodTests() {
    check(ArisKeyboardState.isInputMethod(type: kTISTypeKeyboardInputMode as String, asciiCapable: false) && !ArisKeyboardState.isInputMethod(type: kTISTypeKeyboardLayout as String, asciiCapable: true),
          "IME: Korean 2-Set (an input mode, not ASCII-capable) is an input method; a layout is not")
    check(ArisKeyMethod.unicodeEventsTypeText(usBoard) && ArisKeyMethod.unicodeEventsTypeText(frenchBoard) && !ArisKeyMethod.unicodeEventsTypeText(koreanBoard),
          "IME: text goes as Unicode key events on a layout, never while an input method composes")
    check(ArisKeyMethod.needsASCIISource(character: true, flags: [], keyboard: koreanBoard) && !ArisKeyMethod.needsASCIISource(character: true, flags: .maskCommand, keyboard: koreanBoard)
          && !ArisKeyMethod.needsASCIISource(character: false, flags: [], keyboard: koreanBoard) && !ArisKeyMethod.needsASCIISource(character: true, flags: [], keyboard: usBoard),
          "IME: only a character key pressed alone needs the ASCII source for that moment")
    let hangul = ArisNativeInput.pieces("안녕하세요")
    let plan = ArisNativeLadder.plan(hangul, profile: ArisNativeLadder.Profile(bundle: "com.apple.TextEdit", inputMethod: true), learned: [])
    check(plan == [.axInsert, .paste, .front], "IME: Hangul with 2-Set on: Accessibility, then the pasteboard, then the front; never key events")
}

// MARK: - The text ladder over fakes

private final class CuField: ArisNativeTextIO {
    var value: String?
    var focused = true
    var secure = false
    var insertable = true
    /// What each rung does to the field.
    var takesInsert = true
    var insertRefused = false
    var takesBackground = true
    var takesPaste = true
    var front: ArisNativeFrontResult = .sent
    var takesFront = true
    var otherChange: String?
    var calls: [String] = []
    var settles = 0

    init(_ value: String?) { self.value = value }

    func read() -> ArisNativeFieldRead {
        if !focused { return .notFocused }
        if secure { return .secure }
        return value.map(ArisNativeFieldRead.value) ?? .unreadable
    }
    private func put(_ text: String) {
        if let otherChange { value = otherChange; return }
        value = (value ?? "") + text
    }
    func insertSelected(_ text: String) -> Bool {
        calls.append("insert")
        if insertRefused { return false }
        if takesInsert { put(text) }
        return true
    }
    func postBackground(_ pieces: [ArisNativeInput.Piece]) {
        calls.append("background")
        if takesBackground { put(ArisNativeLadder.wanted(pieces) ?? "") }
    }
    func paste(_ text: String) -> Bool {
        calls.append("paste")
        if takesPaste { put(text) }
        return takesPaste
    }
    func front(_ pieces: [ArisNativeInput.Piece], paste: String?) -> ArisNativeFrontResult {
        calls.append(paste == nil ? "front-keys" : "front-paste")
        if front == .sent, takesFront { put(paste ?? ArisNativeLadder.wanted(pieces) ?? "") }
        return front
    }
    func settle() { settles += 1 }
}

private func cuRun(_ text: String, _ field: CuField, profile: ArisNativeLadder.Profile = ArisNativeLadder.Profile(bundle: "dev.cu.app"),
                   memory: ArisNativeInputMemory = ArisNativeInputMemory(file: nil)) -> ArisNativeLadder.Outcome {
    let pieces = ArisNativeInput.pieces(text)
    let rungs = ArisNativeLadder.plan(pieces, profile: profile, learned: memory.failed(profile.bundle))
    return ArisNativeLadder.run(pieces, rungs: rungs, io: field, memory: memory, bundle: profile.bundle, profile: profile)
}

private func cuLadderTests() {
    typealias L = ArisNativeLadder
    // A native field takes the Accessibility insert: done at once, read back.
    let native = CuField("Hello ")
    let first = cuRun("world", native)
    check(first.state == .verified && first.delivery == .axInsert && native.value == "Hello world" && native.calls == ["insert"], "ladder: a field that takes the insert is done by it, verified")
    // The insert reports success but the app never shows it: background keys next, and the app learns it.
    let memory = ArisNativeInputMemory(file: nil)
    let stubborn = CuField("")
    stubborn.takesInsert = false
    let second = cuRun("hi", stubborn, memory: memory)
    check(second.state == .verified && second.delivery == .background && second.learned == [.axInsert] && stubborn.calls == ["insert", "background"],
          "ladder: an insert the field ignored goes on to background keys, and is remembered")
    check(memory.failed("dev.cu.app") == [.axInsert] && L.plan(ArisNativeInput.pieces("x"), profile: L.Profile(bundle: "dev.cu.app"), learned: memory.failed("dev.cu.app")) == [.background, .paste, .front],
          "ladder: next time that app starts at background keys")
    // An app that drops background keys (not known before): it is learned, the pasteboard takes it.
    let dropper = CuField("")
    dropper.insertable = false
    dropper.takesBackground = false
    let dropMemory = ArisNativeInputMemory(file: nil)
    let third = cuRun("note", dropper, profile: L.Profile(bundle: "dev.cu.electron"), memory: dropMemory)
    check(third.state == .verified && third.delivery == .paste && third.learned == [.background] && dropper.calls == ["background", "paste"],
          "ladder: background keys the app dropped (the field exactly as it was) go on to the pasteboard")
    check(dropMemory.failed("dev.cu.electron").contains(.background) && !ArisNativeInput.takesBackgroundKeys(bundle: "dev.cu.electron", bundleURL: nil, memory: dropMemory),
          "ladder: learnForeground is wired: that app no longer takes background keys")
    let again = CuField("")
    again.insertable = false
    let fourth = cuRun("more", again, profile: L.Profile(bundle: "dev.cu.electron"), memory: dropMemory)
    check(fourth.delivery == .paste && again.calls == ["paste"], "ladder: and next time it goes straight to the rung that worked")
    // A known foreground-only app (Electron): Accessibility, then the front in a gap.
    let electron = CuField("")
    electron.insertRefused = true
    let fifth = cuRun("hey", electron, profile: L.Profile(bundle: "com.tinyspeck.x", dropsBackgroundKeys: true))
    check(fifth.state == .verified && fifth.delivery == .front && electron.calls == ["insert", "front-keys"], "ladder: an Electron field: the insert, else a brief turn in front")
    // A field that changes some other way: stopped there, never typed twice.
    let odd = CuField("abc")
    odd.otherChange = "zzz"
    let sixth = cuRun("x", odd)
    check(sixth.state == .changedOther && odd.calls == ["insert"], "ladder: a field that changed but not by the text stops the ladder")
    // A sending app never gets the insert; keys in the text skip the insert and the paste.
    check(L.plan(ArisNativeInput.pieces("hi"), profile: L.Profile(bundle: "b", sending: true), learned: []) == [.background, .paste, .front], "ladder: no Accessibility insert in a messaging app")
    check(L.plan(ArisNativeInput.pieces("line\\nnext"), profile: L.Profile(bundle: "b"), learned: []) == [.background, .front], "ladder: text with keys (Return) goes as keys only")
    // A password field: nothing at all.
    let secret = CuField("")
    secret.secure = true
    let seventh = cuRun("pw", secret)
    check(seventh.state == .nothing(code: "SECURE_FIELD", message: "a password field has the focus") && secret.calls.isEmpty, "ladder: never into a password field")
    // Focus in another window: only the front; the user typing the whole time: nothing sent, safe to retry.
    let elsewhere = CuField("")
    elsewhere.front = .busy(waited: 8)
    let eighth = cuRun("x", elsewhere, profile: L.Profile(bundle: "b", focusElsewhere: true))
    check(L.plan(ArisNativeInput.pieces("x"), profile: L.Profile(bundle: "b", focusElsewhere: true), learned: []) == [.front], "ladder: focus in another window: only the brief turn in front")
    let reply = ArisDesktopEnvelope.parse(L.reply(eighth, window: 3, pid: 4).json())
    check(eighth.state == .nothing(code: ArisNativeFocusGap.busyCode, message: ArisNativeFocusGap.busyLine(waited: 8)) && reply?.safeToRepeat == true && reply?.code == "USER_ACTIVE",
          "ladder: no gap in the user's input: nothing sent, and the controller may try again")
    // A field that can't be read: sent once, unverified (the controller reads the window back), never a second rung.
    let blind = CuField(nil)
    let ninth = cuRun("x", blind)
    check(ninth.state == .unverified && ninth.delivery == .background && blind.calls == ["background"], "ladder: a field with no value gets one rung, unverified")
    let verified = ArisDesktopEnvelope.parse(L.reply(first, window: 1, pid: 2).json())
    check(verified?.dispatched == true && verified?.safeToRepeat == false && verified?.data["delivery"] as? String == "ax-insert" && verified?.data["verified"] as? Bool == true,
          "ladder: a verified rung reads as dispatched, never repeated, with its delivery")
    check(L.landing("b", before: "a", after: "ab") == .landed && L.landing("b", before: "ab", after: "ab") == .unchanged && L.landing("b", before: "ab", after: "x") == .other
          && L.landing("한글", before: "", after: "한글".decomposedStringWithCanonicalMapping) == .landed, "ladder: landing, composed forms alike")
}

private func cuMemoryTests() {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cu-memory-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("input-ladder.json")
    ArisNativeInputMemory(file: file).noteFailed("dev.cu.kept", .background)
    let read = ArisNativeInputMemory(file: file)
    check(read.failed("dev.cu.kept") == [.background], "memory: what an app ignored is kept on disk")
    check(read.failed("dev.cu.kept", now: Date().addingTimeInterval(31 * 24 * 3600)).isEmpty, "memory: and forgotten after a month (an update may change it)")
    read.noteWorked("dev.cu.kept", .background)
    check(ArisNativeInputMemory(file: file).failed("dev.cu.kept").isEmpty && ArisNativeInputMemory(file: file).worked("dev.cu.kept") == .background,
          "memory: a rung that worked again clears its failure")
    read.noteFailed("dev.cu.kept", .front)
    check(!read.failed("dev.cu.kept").contains(.front), "memory: the last rung is never skipped")
}

// MARK: - The focus rule over synthetic activity timelines

/// A fake clock and the user's input as times (seconds) on it.
private final class CuTimeline {
    var now: Double = 0
    let inputs: [Double]
    var urgentUntil: Double = -1
    init(_ inputs: [Double]) { self.inputs = inputs }
    func sinceInput() -> Double { inputs.filter { $0 <= now }.map { now - $0 }.min() ?? .infinity }
    func urgent() -> Bool { now < urgentUntil }
    func sleep(_ seconds: Double) { now += seconds }
}

private func cuFocusGapTests() {
    typealias G = ArisNativeFocusGap
    check(G.decide(sinceInput: 5, urgent: false, waited: 0, limit: 8) == .go, "focus: an idle Mac: the front at once")
    check(G.decide(sinceInput: 0.2, urgent: false, waited: 0, limit: 8) != .go && G.decide(sinceInput: 0.2, urgent: false, waited: 8, limit: 8) == .giveUp,
          "focus: the user just typed: wait, and give up at the limit")
    // Typing for 3 s, then stopping: the front comes about a second after the last key.
    let burst = CuTimeline(Array(stride(from: 0.0, through: 3.0, by: 0.2)))
    let went = G.await(limit: G.limit, sinceInput: burst.sinceInput, urgent: burst.urgent, sleep: burst.sleep)
    check(went && burst.now >= 4.0 && burst.now < 4.6, "focus: typing stops at 3 s: the front is taken at about 4 s (\(burst.now))")
    // Typing without a pause: no front, nothing sent, after the conversation's limit.
    let steady = CuTimeline(Array(stride(from: 0.0, through: 20.0, by: 0.3)))
    check(!G.await(limit: G.limit, sinceInput: steady.sinceInput, urgent: steady.urgent, sleep: steady.sleep) && abs(steady.now - G.limit) < 0.3,
          "focus: the user types the whole time: refused at the limit (\(steady.now))")
    // A job waits longer: typing for 30 s, then it goes.
    let long = CuTimeline(Array(stride(from: 0.0, through: 30.0, by: 0.4)))
    check(G.await(limit: G.jobLimit, sinceInput: long.sinceInput, urgent: long.urgent, sleep: long.sleep) && long.now > 30 && long.now < 32,
          "focus: a background job waits for the gap instead of failing on the first refusal")
    // A dictation going in holds it too.
    let dictating = CuTimeline([])
    dictating.urgentUntil = 1.0
    check(G.await(limit: G.limit, sinceInput: dictating.sinceInput, urgent: dictating.urgent, sleep: dictating.sleep) && dictating.now >= 1.0,
          "focus: never while a dictation goes in")
    check(G.inputDuringRaise(sinceInput: 0.1, raisedFor: 0.3) && !G.inputDuringRaise(sinceInput: 2, raisedFor: 0.3), "focus: input during the raise stops the keys")
}

// MARK: - Window merge

private func cuWindow(_ number: Int, pid: Int32, _ frame: CGRect, onScreen: Bool, layer: Int = 0, alpha: Double = 1, title: String? = nil) -> [String: Any] {
    var info: [String: Any] = [kCGWindowNumber as String: number, kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: layer,
                               kCGWindowAlpha as String: alpha, kCGWindowBounds as String: frame.dictionaryRepresentation as NSDictionary]
    if onScreen { info[kCGWindowIsOnscreen as String] = true }
    if let title { info[kCGWindowName as String] = title }
    return info
}

private func cuWindowMergeTests() {
    typealias M = ArisDesktopWindowMerge
    let big = CGRect(x: 0, y: 0, width: 800, height: 600)
    let list = [cuWindow(1, pid: 9, big, onScreen: true, title: "Front"), cuWindow(2, pid: 7, big, onScreen: true), cuWindow(3, pid: 9, big, onScreen: false),
                cuWindow(4, pid: 9, big, onScreen: false), cuWindow(5, pid: 9, CGRect(x: 0, y: 0, width: 20, height: 20), onScreen: true),
                cuWindow(6, pid: 9, big, onScreen: true, layer: 3), cuWindow(8, pid: 9, CGRect(x: 0, y: 0, width: 500, height: 400), onScreen: true)]
    let ax = [M.AXWindow(id: 3, frame: big, title: "Minimized note", minimized: true), M.AXWindow(id: 1, frame: big, title: "Front"),
              M.AXWindow(id: 11, frame: big, title: "Other Space")]
    let merged = M.merge(list: list, pid: 9, ax: ax)
    check(merged.map(\.id) == [1, 8, 3, 11], "windows: on screen first (front to back), then the off-screen ones Accessibility knows: \(merged.map(\.id))")
    check(merged[0].onScreen && merged[0].title == "Front" && !merged[2].onScreen && merged[2].minimized && merged[2].title == "Minimized note" && !merged[3].onScreen && !merged[3].minimized,
          "windows: each marked on screen, minimized, or elsewhere, with its title")
    check(!merged.contains { $0.id == 4 } && !merged.contains { $0.id == 5 } && !merged.contains { $0.id == 6 } && !merged.contains { $0.id == 2 },
          "windows: an off-screen buffer nobody lists, a tiny window, another level and another app's window are left out")
    check(M.note(merged[2]) == "minimized" && M.note(merged[3])?.contains("another Space") == true && M.note(merged[0]) == nil, "windows: how a list names those")
    check(M.merge(list: [cuWindow(1, pid: 9, big, onScreen: true, alpha: 0)], pid: 9, ax: []).isEmpty, "windows: an invisible window is no window")
    let token = ArisAXRemote.token(pid: 0x01020304, id: 7)
    check(token.count == 20 && token[0] == 0x04 && token[8] == 0x6f && token[11] == 0x63 && token[12] == 7, "windows: an element's remote token (pid, 0, coco, id)")
}

// MARK: - Accessibility budget

private func cuBudgetTests() {
    var clock = Date(timeIntervalSince1970: 0)
    let budget = ArisAXBudget(limit: 5, now: { clock })
    budget.record(.cannotComplete)
    budget.record(.cannotComplete)
    budget.record(.success)
    check(!budget.unresponsive && budget.timeoutsInARow == 0 && !budget.exhausted, "budget: an answer between timeouts resets the count")
    budget.record(.attributeUnsupported)
    for _ in 0..<ArisAXBudget.giveUpAfter { budget.record(.cannotComplete) }
    check(budget.unresponsive && budget.exhausted, "budget: timeouts in a row: the app is not responding, the walk ends")
    let timed = ArisAXBudget(limit: 5, now: { clock })
    clock = clock.addingTimeInterval(6)
    check(timed.exhausted && !timed.unresponsive, "budget: a look stops at its limit (cut short, not 'not responding')")
    let failure = ArisDesktopEnvelope.parse(ArisNativeReply.failure(ArisAXBudget.notRespondingCode, ArisAXBudget.notRespondingLine, retrySafe: true).json())
    check(failure?.code == "APP_NOT_RESPONDING" && failure?.message?.contains("not responding") == true && failure?.safeToRepeat == true, "budget: the brain gets 'the app is not responding'")
    check(ArisAXBudget.perCall <= 1.5 && ArisAXBudget.lookLimit < ArisDesktopEngine.runTimeout, "budget: each element and the look are bounded below the call's limit")
    let ax = cuSource("ArisAgent/ArisNativeAX.swift")
    check(ax.contains("static func children(_ element: AXUIElement) -> [AXUIElement] { (value(element, kAXChildrenAttribute as String) as? [AXUIElement] ?? []).map(timed) }")
          && ax.contains("if asked.error == .cannotComplete { continue }"), "budget: every child element is timed; a timed-out element is skipped with its subtree")
}

// MARK: - The vision picture

private func cuVisionScaleTests() {
    let window = CGRect(x: 100, y: 50, width: 1440, height: 900)
    let retina = ArisDesktopVisionFrame(full: CGSize(width: 2880, height: 1800), window: window)
    check(retina.scaled && max(retina.sent.width, retina.sent.height) <= ArisDesktopVisionFrame.maxSide && retina.sent.width * retina.sent.height <= ArisDesktopVisionFrame.maxPixels,
          "vision: a Retina window's shot is scaled to the model's size (\(retina.sent))")
    check(abs(retina.sent.width / retina.sent.height - 1.6) < 0.01, "vision: its shape kept")
    check(retina.windowPoint(sent: .zero) == window.origin && retina.windowPoint(sent: CGPoint(x: retina.sent.width, y: retina.sent.height)) == CGPoint(x: window.maxX, y: window.maxY),
          "vision: the sent picture's corners are the window's corners exactly")
    let centre = retina.windowPoint(sent: CGPoint(x: retina.sent.width / 2, y: retina.sent.height / 2))
    check(abs(centre.x - window.midX) < 0.001 && abs(centre.y - window.midY) < 0.001, "vision: its centre is the window's centre")
    let full = retina.fullPixel(CGPoint(x: 10, y: 20))
    check(abs(retina.windowPoint(full: full).x - retina.windowPoint(sent: CGPoint(x: 10, y: 20)).x) < 0.0001 && full.x > 10, "vision: sent → full → window agrees with sent → window")
    let small = ArisDesktopVisionFrame(full: CGSize(width: 800, height: 500), window: CGRect(x: 0, y: 0, width: 800, height: 500))
    check(!small.scaled && small.sent == small.full && small.windowPoint(sent: CGPoint(x: 400, y: 250)) == CGPoint(x: 400, y: 250), "vision: a small picture goes as it is, never enlarged")
    let tall = ArisDesktopVisionFrame.sentSize(CGSize(width: 1000, height: 4000))
    check(tall.height <= 1568 && tall.width * tall.height <= ArisDesktopVisionFrame.maxPixels, "vision: a tall picture's long side fits too")
    // A real PNG scaled to the size.
    let width = 400, height = 250
    if let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let image = context.makeImage() {
        let out = NSMutableData()
        if let destination = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, nil)
            _ = CGImageDestinationFinalize(destination)
        }
        let scaled = ArisDesktopVisionFrame.scaled(out as Data, to: CGSize(width: 200, height: 125)).flatMap(ArisDesktopSession.pixelSize)
        check(scaled.map { $0.width == 200 && $0.height == 125 } == true, "vision: the picture sent is that size")
    } else {
        check(false, "vision: a test picture could be made")
    }
    let look = cuSource("ArisAgent/ArisDesktopLook.swift")
    check(look.contains("let first = sentPNG == nil ? sentFirst : shot.fullPixel(sentFirst)") && look.contains("png: sentPNG ?? png, width: Int(sent.width)"),
          "vision: the brain gets the scaled picture and its point is mapped back before the zoom and the click")
}

// MARK: - The lock yields to dictation

private func cuLockTests() {
    let lock = ArisDesktopLock(waitLimit: 5, idleHold: 45, poll: 0.01)
    let turn = ArisDesktopLock.Owner(id: "turn:a", live: { true })
    check(lock.acquire(turn) == .acquired, "lock: a turn takes it")
    lock.done("turn:a")
    // The turn only keeps it between its steps: dictation goes in at once.
    var started = Date()
    check(lock.acquireUrgent("insert:1", wait: 1) == .acquired && Date().timeIntervalSince(started) < 0.2, "lock: dictation never waits behind a turn between its steps")
    check(lock.urgent, "lock: while it goes in, a step about to take the front waits")
    // The turn's next step waits for the dictation, even under its own hold.
    let box = CuFlag()
    DispatchQueue.global().async {
        _ = lock.acquire(turn)
        box.set()
    }
    Thread.sleep(forTimeInterval: 0.15)
    check(!box.isSet, "lock: the turn's next step doesn't go while the dictation goes in")
    lock.release("insert:1")
    let deadline = Date().addingTimeInterval(2)
    while !box.isSet, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
    check(box.isSet && !lock.urgent, "lock: and goes once it is in")
    // A step under way: the dictation waits at most its moment, then goes in.
    started = Date()
    check(lock.acquireUrgent("insert:2", wait: 0.3) == .acquired, "lock: dictation is never refused")
    let waited = Date().timeIntervalSince(started)
    check(waited >= 0.25 && waited < 1.0, "lock: behind a step under way it waits only a moment (\(waited) s), never the 90 s limit")
    lock.release("insert:2")
    lock.done("turn:a")
    lock.release("turn:a")
    // Paused on a sign-in window: dictation isn't held up by it.
    _ = lock.acquire(turn)
    lock.pause("turn:a", true)
    started = Date()
    check(lock.acquireUrgent("insert:3", wait: 2) == .acquired && Date().timeIntervalSince(started) < 0.2, "lock: a paused step never holds a dictation")
    lock.release("insert:3")
    lock.release("turn:a")
    check(ArisDesktopLock.dictationWait <= 2, "lock: the dictation's moment is short")
    check(lock.takeUrgent("insert:4") == nil, "lock: /insert and /paste take it this way (never refused)")
    lock.release("insert:4")
}

private final class CuFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var isSet: Bool { lock.withLock { flag } }
    func set() { lock.withLock { flag = true } }
}

// MARK: - Screen Recording asked again

private func cuScreenAccessTests() {
    typealias S = ArisScreenAccess
    check(S.known(preflight: true, seenOn: false, revoked: false) && S.known(preflight: false, seenOn: true, revoked: false), "screen: known on by the process or a fresh check")
    check(!S.known(preflight: true, seenOn: true, revoked: true), "screen: after a failed capture and a fresh off, the process's own (stale) on no longer counts")
    S.note(failureAnswer: false)
    check(S.remembered == (false, true), "screen: a failed capture checked again as off is kept as taken back")
    S.note(failureAnswer: true)
    check(S.remembered == (true, false), "screen: granted again, on")
    S.note(failureAnswer: false)
    S.note(failureAnswer: nil)
    check(S.remembered.revoked, "screen: an unanswered check changes nothing")
    S.note(failureAnswer: true)
    let windows = cuSource("ArisAgent/ArisSessionWindowsLive.swift"), controller = cuSource("ArisAgent/ArisDesktopController.swift")
    check(!windows.contains("guard CGPreflightScreenCaptureAccess() else") && windows.contains("guard ArisScreenAccess.nowAsAgent() else { return .noScreenRecording }")
          && windows.contains("ArisScreenAccess.afterFailureAsAgent()"), "screen: the session look asks as of now, and again when a capture fails")
    check(controller.contains("envelope?.code == ArisNativeShot.failedCode, !engine.access.captureFailed()"), "screen: a look whose picture failed asks macOS again")
}

// MARK: - One default engine

private func cuEngineChoiceTests() {
    check(ArisComputerEngine.standard == .aris && ArisComputerEngine.named(nil) == .standard, "engine: one default, Aris's own")
    let choice = cuSource("ArisAgent/ArisComputerEngineChoice.swift"), engine = cuSource("ArisAgent/ArisDesktopEngine.swift"), keys = cuSource("Aris/private/Aris/ArisPreferenceKeys.swift")
    check(choice.contains("private static var picked = ArisComputerEngine.standard") && !choice.contains("= ArisComputerEngine.peekaboo"),
          "engine: the helper starts on Aris's own engine before the app says one")
    check(engine.contains("computerEngine: @escaping () -> ArisComputerEngine = { .standard }") && keys.contains("default: ArisComputerEngine.standard.rawValue"),
          "engine: the engine's default and the app's stored default are the same source")
}

// MARK: - A click's one recovery

private func cuClickRecoveryTests() {
    typealias S = ArisDesktopSession
    check(S.recoverable(delivery: "ax-press", label: "Soccer Club") && S.recoverable(delivery: "ax-select", label: "Row 3"), "click: a press or select that changed nothing is clicked once more")
    check(!S.recoverable(delivery: "ax-press", label: "Delete") && !S.recoverable(delivery: "ax-press", label: "삭제") && !S.recoverable(delivery: "ax-press", label: "Send")
          && !S.recoverable(delivery: "ax-press", label: "Quit"), "click: never a control that deletes, sends or quits")
    check(!S.recoverable(delivery: "ax-press", label: "  ") && !S.recoverable(delivery: "posted-click", label: "OK") && !S.recoverable(delivery: "ax-focus", label: "Name"),
          "click: never an unnamed control, a click already posted, or a field's focus")
    let call = ArisNativeCall(ArisPeekabooCommands.postedClick("elem_4", snapshot: "ps1_x"))
    check(call.value("--input-strategy") == ArisPeekabooCommands.postedStrategy && call.value("--on") == "elem_4", "click: the posted click's call")
    let actions = cuSource("ArisAgent/ArisDesktopActions.swift")
    check(actions.contains("guard plain, engine.usesNative, !target.sending, !element.isSecure") && actions.contains("if basis.perApp {\n            guard case .success(let sent) = wholeMac(posted)"),
          "click: only on Aris's own engine, never in a messaging app, holding the whole Mac when the step held only its app")
}

// MARK: - aris-tools keys through the engine

private func cuKeysRouteTests() {
    let background = ArisDesktopEnvelope.parse(ArisNativeReply.done(window: 1, pid: 2, extra: ["delivery": "background"]).json())
    let front = ArisDesktopEnvelope.parse(ArisNativeReply.done(window: 1, pid: 2, extra: ["delivery": "foreground"]).json())
    let busy = ArisDesktopEnvelope.parse(ArisNativeReply.failure("USER_ACTIVE", "the user kept typing", retrySafe: true).json())
    let sent = ArisDesktopKeysWords.line("cmd+t", times: 2, app: "Safari", reply: background)
    check(sent.ok && sent.line.contains("cmd+t ×2 to Safari, in the background"), "keys: the engine's background press, said")
    check(ArisDesktopKeysWords.line("cmd+t", times: 1, app: "Code", reply: front).line.contains("brought forward a moment, then the front app back"), "keys: a brief turn in front, said")
    let refused = ArisDesktopKeysWords.line("return", times: 1, app: "Notes", reply: busy)
    check(!refused.ok && refused.line.hasPrefix(ArisTypeReadback.notSentLead) && refused.line.contains("USER_ACTIVE"), "keys: not sent, said so (and why)")
    check(ArisTypeReadbackWords.notSentLead == ArisTypeReadback.notSentLead, "keys: the agent's lead is aris-tools' own")
    // Which way keys go, by the app they'd reach (security review: keys into a terminal would run there).
    typealias P = ArisDesktopKeysPolicy
    check(P.route(bundle: "com.apple.Terminal", names: ["Terminal"], keys: ["return"], held: nil) == .gate
          && P.route(bundle: "com.mitchellh.ghostty", names: ["Ghostty"], keys: ["l"], held: nil) == .gate,
          "keys: a named terminal's keys go through the desktop gate (its card), never straight in")
    check(P.route(bundle: "com.microsoft.VSCode", names: ["Visual Studio Code", "Code"], keys: ["return"], held: nil) == .gate, "keys: a code runner's too")
    // The focused app (no app named) is resolved first and checked the same way.
    check(P.route(bundle: "dev.warp.Warp-Stable", names: ["Warp"], keys: ["cmd+v"], held: nil) == .gate, "keys: a focused terminal gets the same check")
    check(P.route(bundle: "com.apple.Safari", names: ["Safari"], keys: ["cmd+t"], held: nil) == .send
          && P.route(bundle: "com.apple.TextEdit", names: ["TextEdit"], keys: ["cmd+s"], held: nil) == .send, "keys: an ordinary app is unchanged")
    check(P.route(bundle: nil, names: [], keys: ["return"], held: nil) == .refuse(P.unknownAppLine), "keys: an app that can't be told gets nothing")
    // The agent's own held work: only its own keys, never into a code runner (no card to ask on).
    check(P.route(bundle: "com.apple.TextEdit", names: ["TextEdit"], keys: ["cmd+n"], held: ["cmd+n"]) == .send, "keys: an arrangement's ⌘N goes")
    check(P.route(bundle: "com.apple.TextEdit", names: ["TextEdit"], keys: ["cmd+w"], held: ["cmd+n"]) == .refuse(P.heldOtherKeysLine)
          && P.route(bundle: "com.apple.TextEdit", names: ["TextEdit"], keys: ["return"], held: []) == .refuse(P.heldOtherKeysLine),
          "keys: held work sends only the keys of its own shortcut")
    if case .refuse(let why) = P.route(bundle: "com.apple.Terminal", names: ["Terminal"], keys: ["cmd+n"], held: ["cmd+n"]) {
        check(why.contains("runs what is typed into it"), "keys: held work never sends into a terminal")
    } else {
        check(false, "keys: held work never sends into a terminal")
    }
    check(P.keys(in: ["/t/aris-tools keys cmd+T --app Safari", "/t/aris-tools volume 30", "open -a \"Notes\""], tools: "/t/aris-tools") == ["cmd+t"],
          "keys: a shortcut may send only the keys its own commands press")
    // A flag-shaped key never reaches the engine's words, on either path (it could aim the press at another window).
    for bad in ["--window-id", "--pid=42", "--app", "-x", "cmd+a=b", "a b", "", "nosuchkey"] {
        check(!P.isKey(bad), "keys: “\(bad)” is no key")
        check(P.route(bundle: "com.apple.TextEdit", names: ["TextEdit"], keys: ["cmd+a", bad], held: nil) == .refuse(P.badKeyLine),
              "keys: “\(bad)” is refused before routing on a turn")
        check(P.route(bundle: "com.apple.TextEdit", names: ["TextEdit"], keys: [bad], held: ["cmd+n", bad.lowercased()]) == .refuse(P.badKeyLine),
              "keys: “\(bad)” is refused before routing on held work, even when registered")
    }
    check(["cmd+shift+t", "return", "f5", "ctrl+opt+space", "a", "pagedown"].allSatisfy(P.isKey), "keys: real keys pass")
    let split = ArisNativeCall(["press", "--window-id", "7", "--json", "--", "cmd+a", "--window-id", "99", "--pid=3"])
    check(split.int("--window-id") == 7 && split.positional == ["cmd+a", "--window-id", "99", "--pid=3"], "keys: after `--` nothing is a flag")
    let routeSource = cuSource("ArisAgent/ArisDesktopKeysRoute.swift")
    check(routeSource.contains("keys.allSatisfy(ArisDesktopKeysPolicy.isKey)") && routeSource.contains("[\"press\", \"--window-id\", String(window), \"--json\", \"--\"]"),
          "keys: the route checks every key first, and puts its own window id before `--`")
    let heldLock = ArisDesktopLock(waitLimit: 1, idleHold: 5, poll: 0.01)
    check(heldLock.allowedKeys("arrange:\(UUID().uuidString)") == ["cmd+n"] && heldLock.allowedKeys("shortcut:\(UUID().uuidString)").isEmpty, "keys: what held work may send by default")
    heldLock.allowKeys("shortcut:x", ["CMD+T"])
    check(heldLock.allowedKeys("shortcut:x") == ["cmd+t"], "keys: a replay's own keys are registered")
    heldLock.release("shortcut:x")
    check(heldLock.allowedKeys("shortcut:x").isEmpty, "keys: and dropped with its hold")
    let route = cuSource("ArisAgent/ArisDesktopKeysRoute.swift")
    check(route.components(separatedBy: "ArisDesktopKeysPolicy.route(bundle: found.bundle, names: found.names, keys: keys").count - 1 == 2
          && route.contains("held: lock.allowedKeys(held)") && route.contains("ArisDesktopEngine.shared.handle(words, text: nil, turn: turn)"),
          "keys: both paths check the target; a code runner's keys go to the one gate")
    check(cuSource("ArisAgent/main.swift").contains("ArisDesktopLock.shared.allowKeys(owner, ArisDesktopKeysPolicy.keys(in: learned.commands, tools: ArisAgentRunner.toolsPath))"),
          "keys: a replay registers its shortcut's keys")
    let windows = cuSource("ArisTools/ArisWindows.swift"), keysClient = cuSource("ArisTools/ArisEngineKeys.swift"), hold = cuSource("ArisTools/ArisDesktopHold.swift")
    check(windows.contains("let sent = engineKeys(call.chords, times: times, bundle: bundle)") && !windows.contains("event?.post(tap: .cghidEventTap)") && !windows.contains("func typingTarget("),
          "keys: aris-tools keys goes through the engine and posts nothing to whatever is in front")
    check(windows.contains("let sent = engineKeys([\"cmd+n\"], times: 1, bundle: app.bundleIdentifier)"), "keys: new's ⌘N goes through the engine too")
    check(windows.components(separatedBy: "desktopHold()").count - 1 >= 2 && hold.contains("func desktopHold(gap: Bool = true)") && hold.contains("if gap { asked[\"gap\"] = true }"),
          "keys: tile and new take the turn's hold, in a gap in the user's input")
    check(keysClient.contains("http://127.0.0.1:23351/desktop-keys") && cuSource("ArisAgent/main.swift").contains("case \"/desktop-keys\":"), "keys: the agent's route is wired")
}

// MARK: - Browsers

private func cuBrowserTests() {
    // The engine has no browser rule of its own: a browser's window is worked like any app's once the gate lets it.
    for file in ["ArisNativeRunner", "ArisNativeInput", "ArisNativeApps", "ArisNativeAX", "ArisNativeTextLadder", "ArisNativeTextLive", "ArisDesktopActions", "ArisDesktopTextLadder"] {
        let code = cuSource("ArisAgent/\(file).swift").components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") && !$0.contains("///") }.joined()
        check(!code.contains("browser"), "browsers: \(file) has no browser rule of its own")
    }
    check(ArisAX.isWebShell(bundleURL: nil) == false, "browsers: a Chromium browser's tree is switched on as any web shell's (by its framework)")
    // The owner's decision 2 (2026-11-18): a browser's reads run; every action asks on their card each time.
    let chrome = ArisDesktopTarget(name: "Google Chrome", bundle: "com.google.Chrome", pid: 5, known: true, never: false, browser: true, sending: false)
    var see = ArisDesktopRequest(verb: .see)
    see.app = "Google Chrome"
    check(ArisDesktopGate.decide(see, target: chrome, context: ArisDesktopContext(), remembered: true, secureInput: false) == .run,
          "browsers: the gate lets a browser's read run (decision 2)")
    check(ArisDesktopGate.decide(ArisDesktopRequest(verb: .click, ref: ArisDesktopRef(snapshot: "s1", element: 1)), target: chrome, context: ArisDesktopContext(),
                                 remembered: true, secureInput: false) == .ask(remember: false),
          "browsers: and asks for every action, never kept (decision 2)")
}

// MARK: - Wiring

private func cuWiringTests() {
    let runner = cuSource("ArisAgent/ArisNativeRunner.swift"), input = cuSource("ArisAgent/ArisNativeInput.swift"), controller = cuSource("ArisAgent/ArisDesktopController.swift")
    check(!input.contains("Thread.isMainThread ? ArisKeyLayout.current(command: command) : [:]") && input.contains("chord(text, keyboard: ArisKeyboardLive.state())"),
          "wiring: chords read the layout in use (on the main thread), never the US places off it")
    check(runner.contains("ArisNativeLadder.run(pieces, rungs: rungs, io: io, memory: memory") && runner.contains("ArisNativeKeyboardSwitch.withASCII(keys)"),
          "wiring: typing goes by the ladder, a lone character key under an input method by the ASCII source")
    check(!runner.contains("ArisNativeForeground.borrow(") && input.contains("guard clock.awaitGap(job: job) else"), "wiring: every turn in front goes through the gap rule")
    check(runner.contains("if let pid = Self.pid(of: call), ArisAX.unresponsive(pid: pid)") && runner.contains("ArisNativeTree.read(window: window, pid: pid, budget: budget)"),
          "wiring: an app that doesn't answer is said so, a look has a budget")
    check(controller.contains("owner: turn.desktopOwner, began: started, sending: target.sending"), "wiring: each engine call knows its turn (own input), its start and a messaging app")
    check(cuSource("ArisAgent/ArisDesktopLive.swift").contains("ArisDesktopWindowMerge.merge(list: list, pid: pid, ax: ax)")
          && cuSource("ArisAgent/ArisNativeAX.swift").contains("?? ArisAXRemote.window(pid: pid, id: id)"), "wiring: the engine's windows include off-screen ones, and can be read")
    let main = cuSource("ArisAgent/main.swift")
    check(main.contains("ArisDesktopLock.shared.takeUrgent(pasteOwner)") && main.contains("ArisDesktopLock.shared.takeUrgent(insertOwner)"), "wiring: /paste and /insert take the dictation's way")
    for file in ["ArisAgent/ArisSessionWindowsLive.swift", "ArisAgent/ArisSessionDesktopLive.swift"] {
        check(!cuSource(file).contains("ArisNativeForeground.borrow("), "wiring: \(file) takes the front only in a gap")
    }
}
