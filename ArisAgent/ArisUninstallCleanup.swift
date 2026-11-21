//
//  ArisUninstallCleanup.swift
//  aris-agent
//
//  Uninstall's tidy-up outside ~/.config/aris: only what Aris's installers added, matched by what marks it as Aris's.
//  ~/.claude/settings.json: hooks posting to the notch (http://127.0.0.1:23350/hook, install-claude-hooks.py), the
//  command hooks running aris-claude-hook.sh inside Aris.app (Settings › Claude Code 연결, ClaudeHookSettings), and the
//  status line script in Aris's folder or inside Aris.app. ~/.codex/hooks.json and ~/.gemini/settings.json: hooks running Aris's
//  agent-hook.sh (install-agent-hooks.py). ~/.gemini/antigravity-cli/settings.json: the rules install-aris-agent.sh
//  added (any naming Aris's folder, and its generic ones unless they were already there before Aris; deny rules that
//  were there before Aris come back). ~/.codex/config.toml: codex_hooks = true goes back to how it was, only when the
//  installer's oldest backup (config.toml.bak-<time>) shows it wasn't on. Everything else in those files stays. Each
//  changed file is copied to <name>.aris-uninstall-<stamp> (0600 from the start) first; a file that is a link is left
//  alone. The helper's own Keychain items (the API brains' keys and their list's signing key, the MCP servers'
//  secrets) are deleted by service, never read.
//

import Foundation
import Security

enum ArisUninstallCleanup {
    static let hookURL = "http://127.0.0.1:23350/hook"
    /// The script the app's command hooks run, and its status line script (ClaudeHookSettings.hookScript, statusScript).
    static let hookScript = "aris-claude-hook.sh"
    static let statusScript = "aris-claude-statusline.sh"
    /// Aris's Keychain services: the helper's (ArisAPISecrets.service, .signingService; ArisMCPSecrets.service) and the
    /// app's (ArisKeychain.service: the ElevenLabs and TypeSafe keys; ArisVoiceIDStore.service: the owner's voice).
    /// The app deletes its own keys by name as well; by service here nothing of Aris's is left when it can't.
    static let keychainServices = ["com.lumenjsn.aris.brains", "com.lumenjsn.aris.brains.signing", "com.lumenjsn.aris.mcp",
                                   "com.lumenjsn.aris.keys", "com.lumenjsn.aris.voiceid"]

    /// What macOS kept for the helper programs under ~/Library (VM run 2026-11-18, D3: left after an uninstall): the
    /// old loose helper's defaults, and the caches and HTTP storage of aris-agent and aris-tools, under their program
    /// names and under the ids ArisHelperListing gives them. Never the app's own (com.lumenjsn.aris).
    static func helperLibraryItems(home: URL) -> [URL] {
        let library = home.appendingPathComponent("Library", isDirectory: true)
        let names = ["aris-agent", "aris-tools", "com.lumenjsn.aris.agent", "com.lumenjsn.aris.tools"]
        return [library.appendingPathComponent("Preferences/aris-agent.plist"), library.appendingPathComponent("Preferences/aris-tools.plist")]
            + names.map { library.appendingPathComponent("Caches/\($0)") }
            + names.flatMap { [library.appendingPathComponent("HTTPStorages/\($0)"), library.appendingPathComponent("HTTPStorages/\($0).binarycookies")] }
    }

    /// What else Aris keeps under ~/Library outside its sandbox (VM run 2026-11-19: left after an uninstall):
    /// Application Support/Aris (the engine's input ladder, runtimes; its Skills folder stays when `keepSkills`, the
    /// records being kept), and the caches and HTTP storage of the helper and aris-tools under the app's own id (both
    /// run from inside the app, so macOS files them under com.lumenjsn.aris). Never the sandbox container.
    static func appLibraryItems(home: URL, keepSkills: Bool) -> [URL] {
        let library = home.appendingPathComponent("Library", isDirectory: true)
        let support = library.appendingPathComponent("Application Support/Aris", isDirectory: true)
        let inSupport: [URL] = keepSkills
            ? ArisNoFollow.contents(support).filter { $0 != "Skills" }.sorted().map { support.appendingPathComponent($0) }
            : [support]
        return inSupport + [library.appendingPathComponent("Caches/\(appId)"), library.appendingPathComponent("HTTPStorages/\(appId)"),
                            library.appendingPathComponent("HTTPStorages/\(appId).binarycookies")]
    }

    /// The app's id: its rows in Privacy & Security and its folders under ~/Library carry it.
    static let appId = "com.lumenjsn.aris"

    /// The sandbox's scripts folder macOS makes for the app (its container itself is never touched here).
    static func sandboxScripts(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Scripts/\(appId)", isDirectory: true)
    }

    /// Every Privacy & Security service Aris asks for, by tccutil's names.
    static let permissionServices = ["Microphone", "SpeechRecognition", "Calendar", "Reminders", "AddressBook", "AppleEvents", "Accessibility",
                                     "ScreenCapture", "ListenEvent", "SystemPolicyAllFiles", "SystemPolicyDesktopFolder",
                                     "SystemPolicyDocumentsFolder", "SystemPolicyDownloadsFolder"]

    /// Aris's own rows reset service by service (`reset` is tccutil for com.lumenjsn.aris, a recorder in the tests);
    /// the services whose reset failed.
    static func resetPermissions(_ reset: (String) -> Bool) -> [String] {
        permissionServices.filter { !reset($0) }
    }

    /// `tccutil reset <service> com.lumenjsn.aris`: the product's own uninstall, acting on its own bundle id at the
    /// user's request. True when tccutil exited 0.
    static func resetPermission(service: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", service, appId]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? ArisChildren.run(process)) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// The last remover: a shell started in a session of its own, so it outlives this helper's bootout. It waits for
    /// this helper to be gone (at most `waitLimit`), then removes `paths` (each one, never following a link: rm -rf
    /// takes a link itself). What the uninstall already removed is not there any more; this is only for what was
    /// written in the helper's last moment.
    static func sweepAfterExit(_ paths: [URL]) {
        guard !paths.isEmpty else { return }
        let script = "a=$1; shift; n=0; while kill -0 \"$a\" 2>/dev/null && [ $n -lt \(Int(waitLimit * 10)) ]; do sleep 0.1; n=$((n+1)); done; " +
            "sleep 0.5; for f in \"$@\"; do /bin/rm -rf -- \"$f\"; done"
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        for fd: Int32 in 0...2 { posix_spawn_file_actions_addopen(&actions, fd, "/dev/null", fd == 0 ? O_RDONLY : O_WRONLY, 0) }
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSID))
        let words: [String] = ["/bin/sh", "-c", script, "aris-uninstall-sweep", String(getpid())] + paths.map(\.path)
        let environment: [String] = ["PATH=/usr/bin:/bin"]
        let argv: [UnsafeMutablePointer<CChar>?] = words.map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup($0) } + [nil]
        defer { (argv + envp).forEach { free($0) } }
        var pid: pid_t = 0
        _ = ArisChildren.spawn(&pid, "/bin/sh", &actions, &attributes, argv, envp)
    }

    /// How long the last remover waits for the helper to be gone before it removes anyway.
    static let waitLimit: TimeInterval = 30

    /// One of Aris's Claude Code hooks: the script's http hook, or the app's command hook.
    static func isClaudeHook(_ hook: [String: Any]) -> Bool {
        hook["url"] as? String == hookURL || (hook["command"] as? String)?.contains(hookScript) == true
    }

    /// Aris's status line: the installer's copy in Aris's folder, or the script inside Aris.app.
    static func isClaudeStatusLine(_ command: String, arisFolders: [String]) -> Bool {
        command.contains(statusScript) || (mentions(command, arisFolders) && command.hasSuffix("statusline.sh"))
    }

    struct Result: Equatable, CustomStringConvertible {
        let file: String
        let ok: Bool
        /// "unchanged", "cleaned", "missing", "link", or what went wrong.
        let note: String
        var description: String { "\(file): \(note)" }
    }

    /// The rules install-aris-agent.sh adds that don't name Aris's folder.
    static let antigravityGeneric: Set<String> = [
        "read_url(*)", "command(rm)", "command(sudo)", "command(su)", "command(diskutil)", "command(dd)", "command(launchctl)",
        "command(csrutil)", "command(chown)", "command(tccutil)", "command(security)", "command(git push)", "command(defaults delete)",
        #"command((\S*/)?peekaboo(\s.*)?)"#, #"command(.*[;&|(]\s*(\S*/)?peekaboo(\s.*)?)"#, #"command(.*/peekaboo['"]?(\s.*)?)"#,
        #"command(.*computer-runtime.*)"#,
    ]

    private static func mentions(_ text: String, _ folders: [String]) -> Bool { folders.contains { text.contains($0) } }

    /// `hooks` ({event: [{hooks: [...]}]}) without the hooks `isOurs` matches; groups left empty go, events left empty go.
    private static func pruned(_ hooks: [String: Any], isOurs: ([String: Any]) -> Bool) -> (hooks: [String: Any], changed: Bool) {
        var out = hooks
        var changed = false
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            var kept: [[String: Any]] = []
            for group in groups {
                guard let list = group["hooks"] as? [[String: Any]] else { kept.append(group); continue }
                let left = list.filter { !isOurs($0) }
                if left.count == list.count { kept.append(group); continue }
                changed = true
                if !left.isEmpty { var copy = group; copy["hooks"] = left; kept.append(copy) }
            }
            if kept.isEmpty { out[event] = nil } else { out[event] = kept }
        }
        return (out, changed)
    }

    /// ~/.claude/settings.json without Aris's hooks and status line; nil when nothing of Aris's is in it.
    static func claude(_ settings: [String: Any], arisFolders: [String]) -> [String: Any]? {
        var out = settings
        var changed = false
        if let hooks = settings["hooks"] as? [String: Any] {
            let result = pruned(hooks, isOurs: isClaudeHook)
            out["hooks"] = result.hooks
            changed = result.changed
        }
        if let line = settings["statusLine"] as? [String: Any], let command = line["command"] as? String,
           isClaudeStatusLine(command, arisFolders: arisFolders) {
            out["statusLine"] = nil
            changed = true
        }
        return changed ? out : nil
    }

    /// ~/.codex/hooks.json or ~/.gemini/settings.json without the hooks running Aris's agent-hook.sh; nil when none.
    static func agentHooks(_ settings: [String: Any], arisFolders: [String]) -> [String: Any]? {
        guard let hooks = settings["hooks"] as? [String: Any] else { return nil }
        let result = pruned(hooks) { hook in
            guard let command = hook["command"] as? String else { return false }
            return mentions(command, arisFolders) && command.contains("agent-hook.sh")
        }
        guard result.changed else { return nil }
        var out = settings
        out["hooks"] = result.hooks
        return out
    }

    /// Antigravity's settings without Aris's rules: any naming Aris's folder, and the generic ones Aris adds unless
    /// `before` (the .before-aris copy) already had them. Nil when nothing changes.
    static func antigravity(_ settings: [String: Any], before: [String: Any]?, arisFolders: [String]) -> [String: Any]? {
        guard var permissions = settings["permissions"] as? [String: Any] else { return nil }
        let earlier = before?["permissions"] as? [String: Any]
        var changed = false
        for key in ["allow", "deny"] {
            let rules = permissions[key] as? [String] ?? []
            let had = Set(earlier?[key] as? [String] ?? [])
            let kept = rules.filter { rule in
                if mentions(rule, arisFolders) { return false }
                if before != nil, antigravityGeneric.contains(rule), !had.contains(rule) { return false }
                return true
            }
            var restored = kept
            // Deny rules the user had before Aris come back (allow rules are never added: that would widen access).
            if key == "deny" { restored += (earlier?[key] as? [String] ?? []).filter { !kept.contains($0) && !mentions($0, arisFolders) } }
            if restored != rules { permissions[key] = restored; changed = true }
        }
        guard changed else { return nil }
        var out = settings
        out["permissions"] = permissions
        return out
    }

    /// Codex's config.toml with codex_hooks back to how it was before Aris's installer (`before`: its oldest backup);
    /// nil when it was already on then, when there's no backup to tell, or when it isn't on now.
    static func codexConfig(_ current: String, before: String?) -> String? {
        guard let before else { return nil }
        let on = #"(?m)^codex_hooks\s*=\s*true\s*\n?"#
        guard current.range(of: on, options: .regularExpression) != nil,
              before.range(of: on, options: .regularExpression) == nil else { return nil }
        if before.range(of: #"(?m)^codex_hooks\s*="#, options: .regularExpression) != nil {
            return current.replacingOccurrences(of: #"(?m)^codex_hooks\s*=\s*true"#, with: "codex_hooks = false", options: .regularExpression)
        }
        var out = current.replacingOccurrences(of: on, with: "", options: .regularExpression)
        // The installer's own section ("\n[features]\n" at the end) goes with it when nothing else is in it.
        if !before.contains("[features]") {
            out = out.replacingOccurrences(of: #"\n*\[features\]\s*$"#, with: "\n", options: .regularExpression)
        }
        return out == current ? nil : out
    }

    // MARK: - Keychain

    /// Deletes every generic password under `service`, by service alone: nothing is read (no data, no attributes are
    /// asked for). True when none is left.
    static func deleteKeychainItems(service: String) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        // One call deletes every match; a few more in case the keychain deletes one at a time.
        for _ in 0..<64 {
            switch SecItemDelete(query as CFDictionary) {
            case errSecSuccess: continue
            case errSecItemNotFound: return true
            default: return false
            }
        }
        return false
    }

    /// The helper's Keychain items, by service (`delete` is the live deletion, a recorder in the tests). One line per
    /// service that could not be emptied; empty when all went.
    static func removeKeychain(_ delete: (String) -> Bool) -> [String] {
        keychainServices.filter { !delete($0) }
    }

    // MARK: - On disk

    /// Cleans the five files under `home`; one result per file, Antigravity's last.
    static func run(home: URL, stamp: String) -> [Result] {
        let folders = [".config/aris", ".config/boring-notch", ".peekaboo", "Library/Application Support/Aris/computer-runtime"]
            .map { home.appendingPathComponent($0).path }
        let agy = home.appendingPathComponent(".gemini/antigravity-cli/settings.json")
        let before = ArisNoFollow.read(agy.appendingPathExtension("before-aris"))
            .flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        let codexFolder = home.appendingPathComponent(".codex")
        let codexBackup = ArisNoFollow.contents(codexFolder).filter { $0.range(of: #"^config\.toml\.bak-\d+$"#, options: .regularExpression) != nil }
            .min { Int($0.dropFirst("config.toml.bak-".count)) ?? 0 < Int($1.dropFirst("config.toml.bak-".count)) ?? 0 }
        let codexBefore = codexBackup.flatMap { ArisNoFollow.text(codexFolder.appendingPathComponent($0)) }
        return [
            clean(home.appendingPathComponent(".claude/settings.json"), stamp: stamp) { claude($0, arisFolders: folders) },
            clean(home.appendingPathComponent(".codex/hooks.json"), stamp: stamp) { agentHooks($0, arisFolders: folders) },
            clean(home.appendingPathComponent(".gemini/settings.json"), stamp: stamp) { agentHooks($0, arisFolders: folders) },
            cleanText(codexFolder.appendingPathComponent("config.toml"), stamp: stamp) { codexConfig($0, before: codexBefore) },
            clean(agy, stamp: stamp) { antigravity($0, before: before, arisFolders: folders) },
        ]
    }

    private static func clean(_ file: URL, stamp: String, _ change: ([String: Any]) -> [String: Any]?) -> Result {
        rewrite(file, stamp: stamp) { data in
            guard let settings = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
            guard let cleaned = change(settings) else { return nil }
            return try JSONSerialization.data(withJSONObject: cleaned, options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]) + Data("\n".utf8)
        }
    }

    private static func cleanText(_ file: URL, stamp: String, _ change: (String) -> String?) -> Result {
        rewrite(file, stamp: stamp) { data in change(String(decoding: data, as: UTF8.self)).map { Data($0.utf8) } }
    }

    /// Reads a regular file, asks `change` for its new bytes (nil: leave it), backs it up 0600 and replaces it.
    private static func rewrite(_ file: URL, stamp: String, _ change: (Data) throws -> Data?) -> Result {
        let name = file.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
        guard FileManager.default.fileExists(atPath: file.path) || ArisNoFollow.isFile(file) else {
            // Nothing there, or a dangling link: nothing to clean.
            return Result(file: name, ok: true, note: "missing")
        }
        guard ArisNoFollow.isFile(file) else { return Result(file: name, ok: true, note: "link") }
        guard let data = ArisNoFollow.read(file) else { return Result(file: name, ok: false, note: "not readable") }
        do {
            guard let out = try change(data) else { return Result(file: name, ok: true, note: "unchanged") }
            let backup = file.deletingLastPathComponent().appendingPathComponent("\(file.lastPathComponent).aris-uninstall-\(stamp)")
            try ArisNoFollow.createPrivate(backup, data)
            try ArisNoFollow.replace(file, with: out)
            return Result(file: name, ok: true, note: "cleaned")
        } catch {
            return Result(file: name, ok: false, note: error.localizedDescription)
        }
    }
}
