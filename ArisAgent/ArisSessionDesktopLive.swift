//
//  ArisSessionDesktopLive.swift
//  aris-agent
//
//  A Claude Code session that lives in the Claude app's Code tab (no terminal: the app runs `claude --input-format
//  stream-json` itself). The app keeps each of its Code sessions in a small file of its own (claude-code-sessions/
//  …/local_<id>.json, read only: its id, the CLI session id it runs, its folder, whether it is archived); the session
//  is opened by the app's own link (claude://code/continue?session=local_<id>), proven by the address its window shows
//  (the web area's AXURL names that id), then its composer gets the text and Return, with the app in front for that
//  moment; the session the window showed before and the app the user had in front come back after. The send is proven by
//  the session's own UserPromptSubmit hook, as everywhere.
//

import AppKit
import ApplicationServices
import Foundation

enum ArisSessionDesktopLive {
    static let bundle = "com.anthropic.claudefordesktop"

    /// The app's own record of its Code sessions (only these fields are read).
    static var recordsFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
    }

    /// The app's local id for a CLI session id: exactly one unarchived record that runs it. Pure in its part (`read`).
    static func localId(for cli: String, records: [(file: String, data: Data)]) -> String? {
        let found = records.compactMap { record -> String? in
            guard let object = (try? JSONSerialization.jsonObject(with: record.data)) as? [String: Any], object["cliSessionId"] as? String == cli,
                  object["isArchived"] as? Bool != true, let id = object["sessionId"] as? String, isLocalId(id) else { return nil }
            return id
        }
        return Set(found).count == 1 ? found[0] : nil
    }

    static func isLocalId(_ id: String) -> Bool { id.range(of: "^local_[A-Za-z0-9-]{1,64}$", options: .regularExpression) != nil }

    /// The link that opens a session in the app (its own handler: claude://code/continue).
    static func link(_ local: String) -> URL? {
        guard isLocalId(local) else { return nil }
        return URL(string: "claude://code/continue?session=\(local)&source=aris")
    }

    /// The local id an address names (its last part), when it names one.
    static func shown(in address: String?) -> String? {
        guard let address else { return nil }
        return address.components(separatedBy: CharacterSet(charactersIn: "/?#&=")).first(where: isLocalId)
    }

    static func records() -> [(file: String, data: Data)] {
        let manager = FileManager.default
        guard let walker = manager.enumerator(at: recordsFolder, includingPropertiesForKeys: nil) else { return [] }
        var found: [(String, Data)] = []
        for case let url as URL in walker where url.lastPathComponent.hasPrefix("local_") && url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count < 4 * 1_024 * 1_024 { found.append((url.path, data)) }
            if found.count > 2_000 { break }
        }
        return found
    }

    /// The address the app's window shows (its web area's AXURL).
    static func address(_ window: AXUIElement) -> String? {
        var queue = [window]
        var index = 0
        while index < queue.count, index < 300 {
            let element = queue[index]
            index += 1
            if ArisAX.role(element) == "AXWebArea" {
                if let url = ArisAX.value(element, "AXURL") as? URL { return url.absoluteString }
                if let text = ArisAX.string(element, "AXURL") { return text }
            }
            queue += ArisAX.children(element)
        }
        return nil
    }

    /// The composer: the one editable text area of the window (its value Claude Code's draft).
    static func composers(_ window: AXUIElement) -> [AXUIElement] {
        var queue = [window], found: [AXUIElement] = []
        var index = 0
        while index < queue.count, index < 5_000 {
            let element = queue[index]
            index += 1
            if ArisAX.role(element) == kAXTextAreaRole as String, ArisAX.settable(element, kAXValueAttribute as String) || ArisAX.settable(element, kAXFocusedAttribute as String) {
                found.append(element)
            }
            queue += ArisAX.children(element)
        }
        return found
    }

    static func reach(process: ArisSessionProcess, session: ArisLiveSession) -> Result<ArisSessionReach, ArisSessionStop> {
        guard AXIsProcessTrusted() else { return .failure(.noAccessibility) }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first, let local = localId(for: session.id, records: records()),
              let open = link(local) else { return .failure(.hostNotProven("Claude")) }
        let pid = app.processIdentifier
        if ArisAX.enableWebTree(pid: pid, bundleURL: app.bundleURL) { Thread.sleep(forTimeInterval: 1.0) }
        guard let window = ArisAX.element(ArisAX.app(pid), kAXMainWindowAttribute as String) ?? ArisSessionWindowsLive.windows(pid).first else {
            return .failure(.hostNotProven("Claude"))
        }
        let before = shown(in: address(window))
        guard case .success(let turn) = ArisNativeForeground.take(pid: pid, window: window, clock: ArisNativeOwnerClock(), job: false) else { return .failure(.notInFront) }
        func putBack() {
            if let before, before != local, let back = link(before) {
                NSWorkspace.shared.open(back)
                Thread.sleep(forTimeInterval: 0.6)
            }
            turn.restore()
        }
        if before != local {
            NSWorkspace.shared.open(open)
            let deadline = Date().addingTimeInterval(4)
            while Date() < deadline, shown(in: address(window)) != local { Thread.sleep(forTimeInterval: 0.1) }
        }
        // The window shows that session, and has exactly one composer: else nothing is typed.
        let fields = composers(window)
        guard shown(in: address(window)) == local, fields.count == 1, let composer = fields.first else {
            putBack()
            return .failure(.hostNotProven("Claude"))
        }
        let ready = { ArisFrontLive.frontPid() == pid && shown(in: address(window)) == local }
        let reach = ArisSessionReach(host: .claudeDesktop, tty: "", pid: process.pid)
        reach.look = {
            guard ready() else { return .focusMoved }
            let draft = (ArisAX.string(composer, kAXValueAttribute as String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return draft.isEmpty ? nil : .draftInInput
        }
        reach.type = { text in
            guard ready() else { return .focusMoved }
            AXUIElementSetAttributeValue(composer, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            Thread.sleep(forTimeInterval: 0.15)
            ArisNativeInput.type(ArisPeekabooCommands.literal(text), route: .front)
            Thread.sleep(forTimeInterval: 0.2)
            // The composer holds exactly the text now (nothing else was in it).
            let now = (ArisAX.string(composer, kAXValueAttribute as String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard now == text.precomposedStringWithCanonicalMapping else {
                // Not exactly the text: what was typed is taken out again (the composer was empty before).
                if ready() {
                    ArisNativeInput.press(0, flags: .maskCommand, route: .front)
                    ArisNativeInput.press(51, route: .front)
                }
                return .typingFailed
            }
            return nil
        }
        reach.submit = {
            guard ready() else { return .focusMoved }
            ArisNativeInput.press(36, route: .front)
            return nil
        }
        reach.escape = {
            guard ready() else { return .focusMoved }
            ArisNativeInput.press(53, route: .front)
            return nil
        }
        reach.finish = putBack
        return .success(reach)
    }
}
