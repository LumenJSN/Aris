//
//  TerminalFocus.swift
//  Aris
//
//  "Go to the terminal": carries out TerminalJump's steps for a session, most exact first (its tab by Warp's focus
//  link or iTerm2's session id, its app, another terminal, its folder in Terminal), and says in one line, on the notice
//  pill, when it landed short of the session's own tab.
//  Every step first hands macOS's activation over (the user's report 2026-11-19: Open terminal did nothing): a click in the
//  notch leaves Aris inactive (its panel never activates it), and since macOS 14 an inactive app asking another to
//  come forward, or opening a link in it, is ignored. The click is the user's, so Aris takes the front for it and yields
//  it to the terminal at once (ArisActivationHandoff does the same for a card about another app's window).
//

import AppKit

enum TerminalFocus {
    /// Brings the session's own terminal forward, as far as it can, and says what it couldn't do.
    @MainActor
    static func focus(_ session: ClaudeSession?, cwd: String) {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        var isDirectory: ObjCBool = false
        let folder = !cwd.isEmpty && FileManager.default.fileExists(atPath: cwd, isDirectory: &isDirectory) && isDirectory.boolValue
        let steps = TerminalJump.steps(for: session?.terminal, running: running, cwd: cwd, folderExists: folder)
        Task { @MainActor in
            var reached: TerminalJump.Step?
            var refused = false
            for step in steps {
                switch await run(step) {
                case .done: reached = step
                case .refused: refused = true
                case .failed: break
                }
                if reached != nil { break }
            }
            let english = ArisUIWords.english
            if let line = TerminalJump.note(reached: reached, wanted: session?.terminal, refused: refused, english: english, name: name) {
                NSLog("[Claude] terminal jump: %@", line)
                _ = await ArisController.shared.notify(ArisNoticeRoute.problem(line: line, title: ArisUIWords.text("터미널", "Terminal", english: english),
                                                                               english: english))
            }
        }
    }

    private enum Outcome { case done, refused, failed }

    @MainActor
    private static func run(_ step: TerminalJump.Step) async -> Outcome {
        if let bundle = step.bundle { handOff(to: bundle) } else { handOff(to: TerminalJump.terminalApp) }
        switch step {
        case .warp(let url, _):
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            do {
                _ = try await NSWorkspace.shared.open(url, configuration: configuration)
                return .done
            } catch {
                NSLog("[Claude] Warp focus link failed: %@", error.localizedDescription)
                return .failed
            }
        case .iterm(let id):
            return await selectITermSession(id)
        case .app(let bundle), .otherTerminal(let bundle):
            return await bringForward(bundle) ? .done : .failed
        case .folder(let cwd):
            guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: TerminalJump.terminalApp) else { return .failed }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            do {
                _ = try await NSWorkspace.shared.open([URL(fileURLWithPath: cwd)], withApplicationAt: terminal, configuration: configuration)
                return .done
            } catch {
                return .failed
            }
        }
    }

    /// Aris takes the front for the user's click (only if it hasn't it already), and hands it to `bundle` (macOS 14's
    /// cooperative activation: only the active app can let another come forward).
    @MainActor
    private static func handOff(to bundle: String) {
        if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
        NSApp.yieldActivation(toApplicationWithBundleIdentifier: bundle)
    }

    /// The app forward with a window to show: opened again as the Dock does (a minimised window comes back, a window on
    /// another Space is switched to), else just activated.
    @MainActor
    private static func bringForward(_ bundle: String) async -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else { return false }
        if let url = app.bundleURL {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            if (try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)) != nil { return true }
        }
        return app.activate()
    }

    @MainActor
    private static func name(_ bundle: String) -> String {
        TerminalJump.knownName(bundle)
            ?? NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.localizedName
            ?? bundle.split(separator: ".").last.map(String.init) ?? bundle
    }

    /// `id` is a validated UUID (TerminalRef), so it is safe to put in the script. Run out of process (QA BUG-37); the
    /// first time, macOS asks the user for Automation of iTerm2 itself (their click is the foreground action that asks).
    private static func selectITermSession(_ id: String) async -> Outcome {
        let source = """
        tell application id "com.googlecode.iterm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if unique id of s is "\(id)" then
                            select w
                            tell t to select
                            tell s to select
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return false
        """
        do {
            return try await ArisAppleScript.run(source, timeout: 5) == "true" ? .done : .failed
        } catch let error as ArisAppleScriptError where error.number == -1743 {
            NSLog("[Claude] iTerm focus refused: Automation for iTerm2 is off")
            return .refused
        } catch {
            NSLog("[Claude] iTerm focus failed: %@", error.localizedDescription)
            return .failed
        }
    }
}
