//
//  ArisNativeKeyLayout.swift
//  aris-agent
//
//  Which physical key types which character on the keyboard the user has selected, for Aris's own engine (ArisNativeInput).
//  The engine runs off the main thread, where the input-source calls (TIS) must not be made, so it used to fall back to
//  the US places for every chord: ⌘A pressed ⌘Q on French AZERTY, ⌘Z was ⌘Y on German QWERTZ. Here the layout is read on
//  the main thread (the agent runs the main run loop), turned into a reverse map with UCKeyTranslate (each key, plain,
//  ⇧, ⌥ and ⇧⌥, and with ⌘ held), cached by the input source's id and built again when the selected source changes.
//
//  What uses what (Apple's TIS and CGEvent documentation):
//  - shortcuts (⌘C, ⌘V, ⌃A) go by the ASCII-capable layout behind the selected source
//    (TISCopyCurrentASCIICapableKeyboardLayoutInputSource): with Korean 2-Set on that is the Latin layout an app reads
//    its key equivalents with, and a ⌘ chord passes through an input method without composing;
//  - text is never typed as key codes: it goes as Unicode strings (CGEventKeyboardSetUnicodeString), or, while an input
//    method is the selected source (Korean 2-Set, Japanese, Chinese: TIS type kTISTypeKeyboardInputMode or not ASCII
//    capable), never as key events at all: an input method reads the key code of such an event and composes from it
//    (keycode 0 is ㅁ in 2-Set), so Hangul came out doubled or as jamo. Then the text goes in through Accessibility (the
//    field's selected text replaced) or the pasteboard (ArisNativeTextLadder), which an input method never touches.
//  - a plain character key pressed alone (no ⌘ or ⌃) while an input method is on would compose: it is pressed with the
//    ASCII-capable source selected for that moment and the previous one selected again after (ArisNativeKeyboardSwitch).
//
//  The maps and the decisions are pure (tested with fixture layouts: US, Korean 2-Set, German, French); only
//  ArisKeyboardLive reads the system.
//

import Carbon
import CoreGraphics
import Foundation

/// One layout read key by key: the stroke (key, ⇧, ⌥) that types each character, and the key that types it with ⌘ held.
struct ArisKeyMap: Equatable {
    struct Stroke: Equatable {
        let key: CGKeyCode
        var shift = false
        var option = false
    }

    /// The layers read, lowest first: a character keeps the first stroke that types it.
    enum Layer: CaseIterable {
        case plain, shift, option, shiftOption, command

        /// UCKeyTranslate's modifier state ((EventModifiers >> 8) & 0xFF).
        var modifierState: UInt32 {
            switch self {
            case .plain: return 0
            case .shift: return UInt32(shiftKey >> 8) & 0xFF
            case .option: return UInt32(optionKey >> 8) & 0xFF
            case .shiftOption: return UInt32((shiftKey | optionKey) >> 8) & 0xFF
            case .command: return UInt32(cmdKey >> 8) & 0xFF
            }
        }
    }

    /// The keys that type characters (the main block; return, tab and space are named keys).
    static let characterKeys: [CGKeyCode] = ArisKeyLayout.characterKeys

    private(set) var strokes: [String: Stroke] = [:]
    /// With ⌘ held (a "Dvorak – QWERTY ⌘" layout types QWERTY then), lowercased.
    private(set) var command: [String: CGKeyCode] = [:]

    /// Built from `typed`: what a key types on a layer (nil for nothing). Pure.
    static func build(keys: [CGKeyCode] = characterKeys, typed: (CGKeyCode, Layer) -> String?) -> ArisKeyMap {
        var map = ArisKeyMap()
        for layer in Layer.allCases where layer != .command {
            for code in keys {
                guard let character = typed(code, layer), !character.isEmpty, character.unicodeScalars.allSatisfy({ $0.value >= 0x20 }),
                      map.strokes[character] == nil else { continue }
                map.strokes[character] = Stroke(key: code, shift: layer == .shift || layer == .shiftOption, option: layer == .option || layer == .shiftOption)
            }
        }
        for code in keys {
            guard let character = typed(code, .command)?.lowercased(), !character.isEmpty, map.command[character] == nil else { continue }
            map.command[character] = code
        }
        return map
    }

    /// The stroke that types `character`, else (a letter) the one that types it in the other case, with ⇧ turned.
    func stroke(for character: String) -> Stroke? {
        if let found = strokes[character] { return found }
        if character.count == 1, character.lowercased() != character.uppercased() {
            let other = character == character.lowercased() ? character.uppercased() : character.lowercased()
            if let found = strokes[other] { return Stroke(key: found.key, shift: !found.shift, option: found.option) }
        }
        return nil
    }

    /// The key a ⌘ (or ⌃) chord on `character` presses: the key that types it with ⌘ held, else the one that types it
    /// on any layer (on AZERTY "1" is ⇧&: ⌘1 is ⌘ on that key, as the user would press it); nil when none does.
    func commandKey(for character: String) -> CGKeyCode? {
        let lowered = character.lowercased()
        return command[lowered] ?? stroke(for: lowered)?.key
    }
}

/// The keyboard as the engine needs it: the selected source, whether it is an input method, and the ASCII-capable
/// layout's maps (the one shortcuts go by).
struct ArisKeyboardState: Equatable {
    /// The selected input source's id (com.apple.keylayout.US, com.apple.inputmethod.Korean.2SetKorean…).
    let sourceId: String
    /// The ASCII-capable layout behind it (com.apple.keylayout.ABC, …French, …German).
    let layoutId: String
    /// The selected source is an input method or one of its modes (it composes from key codes).
    let inputMethod: Bool
    let map: ArisKeyMap

    /// An input method is on by its TIS properties: its type is an input mode (or method), or it can't type ASCII.
    static func isInputMethod(type: String?, asciiCapable: Bool?) -> Bool {
        if asciiCapable == false { return true }
        guard let type else { return false }
        return type == (kTISTypeKeyboardInputMode as String) || type == (kTISTypeKeyboardInputMethodWithoutModes as String)
            || type == (kTISTypeKeyboardInputMethodModeEnabled as String)
    }
}

/// How the engine sends text and keys on a given keyboard. Pure.
enum ArisKeyMethod {
    /// Typed text may go as Unicode key events (else only Accessibility or the pasteboard put it in).
    static func unicodeEventsTypeText(_ keyboard: ArisKeyboardState?) -> Bool { keyboard?.inputMethod != true }

    /// A key pressed alone that an input method would compose (a character, no ⌘ or ⌃): it needs the ASCII-capable
    /// source selected while it goes.
    static func needsASCIISource(character: Bool, flags: CGEventFlags, keyboard: ArisKeyboardState?) -> Bool {
        guard keyboard?.inputMethod == true, character else { return false }
        return !flags.contains(.maskCommand) && !flags.contains(.maskControl)
    }
}

/// The live keyboard: read on the main thread, cached by the selected source and its layout, read again when either
/// changes.
enum ArisKeyboardLive {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: ArisKeyboardState?

    /// How long the engine waits for the main thread to read the keyboard (a paste may hold it a moment).
    static let mainWait: TimeInterval = 0.6

    /// The keyboard now; the last one read when the main thread can't answer in time; nil when it was never read.
    static func state() -> ArisKeyboardState? {
        let last = lock.withLock { cached }
        guard let asked = ArisMainThread.run(timeout: mainWait, currentIds), let ids = asked else { return last }
        if let last, last.sourceId == ids.source, last.layoutId == ids.layout { return last }
        guard let read = ArisMainThread.run(timeout: mainWait, read), let made = read else { return last }
        lock.withLock { cached = made }
        return made
    }

    /// The selected source's id and its ASCII-capable layout's id. Main thread only.
    private static func currentIds() -> (source: String, layout: String)? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let layout = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
        return (string(source, kTISPropertyInputSourceID) ?? "?", string(layout, kTISPropertyInputSourceID) ?? "?")
    }

    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    private static func bool(_ source: TISInputSource, _ key: CFString) -> Bool? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(raw).takeUnretainedValue())
    }

    /// The whole state. Main thread only.
    private static func read() -> ArisKeyboardState? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let layout = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(layout, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        let keyboard = UInt32(LMGetKbdType())
        let map = data.withUnsafeBytes { raw -> ArisKeyMap in
            guard let pointer = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return ArisKeyMap() }
            return ArisKeyMap.build { code, layer in
                var dead: UInt32 = 0
                var length = 0
                var characters = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(pointer, code, UInt16(kUCKeyActionDown), layer.modifierState, keyboard,
                                            OptionBits(kUCKeyTranslateNoDeadKeysMask), &dead, characters.count, &length, &characters)
                guard status == noErr, length > 0 else { return nil }
                return String(utf16CodeUnits: characters, count: length)
            }
        }
        return ArisKeyboardState(sourceId: string(source, kTISPropertyInputSourceID) ?? "?", layoutId: string(layout, kTISPropertyInputSourceID) ?? "?",
                                 inputMethod: ArisKeyboardState.isInputMethod(type: string(source, kTISPropertyInputSourceType),
                                                                              asciiCapable: bool(source, kTISPropertyInputSourceIsASCIICapable)),
                                 map: map)
    }
}

/// A plain key pressed while an input method is on: the ASCII-capable source for that moment, then the one the user had.
enum ArisNativeKeyboardSwitch {
    /// Runs `work` with the ASCII-capable layout selected (when an input method is), the previous source back after.
    static func withASCII(_ work: () -> Void) {
        let previous = ArisMainThread.run(timeout: ArisKeyboardLive.mainWait) { () -> TISInputSource? in
            guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
                  let ascii = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
            return TISSelectInputSource(ascii) == noErr ? current : nil
        } ?? nil
        usleep(40_000)
        work()
        guard let previous else { return }
        usleep(40_000)
        _ = ArisMainThread.run(timeout: ArisKeyboardLive.mainWait) { TISSelectInputSource(previous) }
    }
}

/// Work that must run on the main thread (the input-source calls), from any thread, waited for at most `timeout`.
enum ArisMainThread {
    static func run<T>(timeout: TimeInterval, _ work: @escaping () -> T) -> T? {
        if Thread.isMainThread { return work() }
        let box = ArisMainBox<T>()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            box.value = work()
            done.signal()
        }
        return done.wait(timeout: .now() + timeout) == .success ? box.value : nil
    }
}

private final class ArisMainBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T?
    var value: T? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
