//
//  ArisTeammateLauncher.swift
//  aris-agent
//
//  Opens the Claude Code teammate: its prompt goes into a private file (~/.config/aris/aris/launch/cc-<uuid>.txt, 0600 in
//  a 0700 folder, a new file that can't be a link), then a window is opened in the terminal the user uses
//  (ArisTerminalOpener: Terminal, iTerm2, Ghostty, Warp, kitty, WezTerm or Alacritty) running ArisClaudeLaunch.command. The agent does this because the sandboxed app can neither write there
//  nor script Terminal. The first time, macOS asks the user whether aris-agent may control the terminal (Automation);
//  a refusal fails the job with a sentence that says where to turn it on.
//

import AppKit
import Foundation

struct ArisTeammateLaunchError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum ArisTeammateLauncher {
    /// Prompt files older than this are deleted when the agent starts (a session that outlived it read its file long ago).
    static let fileLifetime: TimeInterval = 86_400
    /// osascript may wait on the Automation question the first time.
    static let scriptTimeout: TimeInterval = 120

    static func workFolder(home: String) -> URL {
        ArisPrivateFile.folder(home: home).appendingPathComponent("work")
    }

    /// Where a launch's files go: the prompt, the launch script and its marks. Beside the work folder, not in it:
    /// `work` is the one place an AI may write with no card, and a file a terminal is about to run, or a brief the user
    /// said yes to, must not be reachable that way (security review 7, M1). Everything else under ~/.config/aris
    /// asks or refuses (ArisRiskPolicy), and reading here asks too.
    static func launchFolder(home: String) -> URL {
        ArisPrivateFile.folder(home: home).appendingPathComponent("launch")
    }

    /// The fixed first line of every prompt file: `claude`'s argument never starts with something it could read as an
    /// option or an input shortcut, whatever the brief starts with.
    static let header = "Aris가 맡긴 작업:\n\n"

    /// What `claude` gets as its one argument (the prompt file's whole text): the fixed line, then the brief exactly as
    /// it was written. Whatever the brief starts with ("-p", "!cmd", "/x", "#1", "@file"), the argument starts with
    /// the header (ArisTeammateGate.isSafePrompt is asked about this, not about the brief alone).
    static func argument(for brief: String) -> String { header + brief }

    /// Writes `argument(for: text)` to a new cc-<id>.txt in `folder` (made 0700): 0600, never over a file or link already there.
    static func writePrompt(_ text: String, in folder: URL, id: UUID) throws -> URL {
        guard ArisPrivateFile.prepareFolder(folder) else { throw ArisTeammateLaunchError(message: "작업 폴더를 쓸 수 없어요.") }
        let file = folder.appendingPathComponent(ArisClaudeLaunch.promptFileName(id))
        let descriptor = open(file.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else {
            throw ArisTeammateLaunchError(message: "프롬프트 파일을 만들지 못했어요: \(String(cString: strerror(errno)))")
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: Data(argument(for: text).utf8))
            try handle.close()
        } catch {
            unlink(file.path)
            throw ArisTeammateLaunchError(message: "프롬프트 파일을 쓰지 못했어요: \(error.localizedDescription)")
        }
        return file
    }

    /// Deletes one prompt file (a regular file only, never through a link).
    static func remove(_ file: URL) {
        var info = stat()
        guard lstat(file.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return }
        unlink(file.path)
    }

    /// Deletes prompt files older than a day.
    static func sweep(_ folder: URL, now: Date) {
        guard ArisPrivateFile.isRealFolder(folder), let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        // The prompt files, and a launch script its terminal never ran (one that ran deleted itself).
        for name in names where name.range(of: #"^cc-[0-9a-f-]{36}\.(txt|sh)$"#, options: .regularExpression) != nil {
            let file = folder.appendingPathComponent(name)
            var info = stat()
            guard lstat(file.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { continue }
            if now.timeIntervalSince1970 - Double(info.st_mtimespec.tv_sec) > fileLifetime { unlink(file.path) }
        }
        // A quiet launch's files (its script, its process id, its window, a close request) left by a session that
        // never ended in Aris's sight.
        for name in names where name.range(of: ArisQuietLaunch.filePattern, options: .regularExpression) != nil {
            let file = folder.appendingPathComponent(name)
            var info = stat()
            guard lstat(file.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { continue }
            if now.timeIntervalSince1970 - Double(info.st_mtimespec.tv_sec) > fileLifetime { unlink(file.path) }
        }
    }

    /// What osascript's failure means, as a sentence for the user.
    static func failure(status: Int32, error: String) -> String {
        if error.contains("-1743") || error.localizedCaseInsensitiveContains("not authorized") {
            return "터미널을 열 권한이 없어요. 시스템 설정 › 개인정보 보호 및 보안 › 자동화에서 Aris가 터미널을 제어하도록 켜 주세요."
        }
        let line = error.split(whereSeparator: \.isNewline).first.map(String.init) ?? "osascript \(status)"
        return "터미널을 열지 못했어요: \(line.prefix(150))"
    }

    /// Opens the window running `command` in the terminal the user uses (ArisTerminalChoice; `wish`: what the app knows
    /// of it). The terminal's pid, its front window once it shows (nil when it didn't show in time: the app looks it
    /// up then), which terminal it is, and one that was passed over for it.
    static func launch(command: String, wish: ArisTerminalWish = ArisTerminalWish(),
                       home: String = FileManager.default.homeDirectoryForCurrentUser.path) throws -> ArisTerminalOpener.Opened {
        try ArisTerminalOpener.open(command: command, wish: wish, home: home)
    }

    /// The teammate's window, opened without coming to the front (ArisQuietOpener). `title`: the job's, for the
    /// window's name; `say`: a line for the job's row before macOS may ask about controlling a terminal.
    static func launchQuietly(command: String, title: String?, wish: ArisTerminalWish = ArisTerminalWish(), english: Bool = false,
                              home: String = FileManager.default.homeDirectoryForCurrentUser.path,
                              say: @escaping (String) -> Void = { _ in }) throws -> ArisQuietOpener.Opened {
        try ArisQuietOpener.open(command: command, title: title, wish: wish, english: english, home: home, say: say)
    }

    /// Said when the terminal that was asked to open is then not among the running apps.
    static let terminalNotFound = "터미널을 찾지 못했어요."

    /// The script goes in on stdin: it never shows in the process list.
    static func runScript(_ script: String) throws {
        let process = ArisExactProcess(), input = Pipe(), errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-"]
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        let ended = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in ended.signal() }
        do {
            try ArisChildren.run(process)
        } catch {
            throw ArisTeammateLaunchError(message: "터미널을 열지 못했어요: \(error.localizedDescription)")
        }
        try? input.fileHandleForWriting.write(contentsOf: Data(script.utf8))
        try? input.fileHandleForWriting.close()
        guard ended.wait(timeout: .now() + scriptTimeout) == .success else {
            ArisProcessEnd.end(process)
            throw ArisTeammateLaunchError(message: "터미널이 답하지 않아요. 자동화 권한 질문이 떠 있는지 확인해 주세요.")
        }
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw ArisTeammateLaunchError(message: failure(status: process.terminationStatus, error: message))
        }
    }
}
