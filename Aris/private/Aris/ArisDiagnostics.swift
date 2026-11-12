//
//  ArisDiagnostics.swift
//  Aris
//
//  진단 내보내기: a zip the user can send when something goes wrong. In it: info.txt (versions, the Mac, each permission on
//  or off, whether the agent answered), app.log (this process's own log lines from the last two hours) and the ends of
//  the agent's logs (from POST /data, redacted there). Everything passes ArisRedaction again here, with the token and
//  the saved keys as known secrets. Never in it: ~/.config/aris's token, keys or config contents, conversations,
//  clipboard, or any image (only the text written below goes in).
//

import AppKit
import OSLog

@MainActor
enum ArisDiagnostics {
    /// The toast to show, or nil when the user cancelled.
    static func export() async -> String? {
        let now = Date()
        let name = ArisAppData.fileName("Aris 진단", ext: "zip", now: now)
        guard let destination = ArisDataModel.Actions.saveZip(name: name) else { return nil }
        let agentLogs = await ArisAgentClient.diagnosticLogs()
        let secrets = ([ClaudeHookToken.load()] + ArisKeyFile.names.map(ArisKeyFile.load)).compactMap { $0 }
        let home = UserHome.path
        var files: [(String, String)] = [("info.txt", info(agentAnswered: agentLogs != nil, now: now)), ("app.log", appLog(since: now.addingTimeInterval(-7_200)))]
        files += (agentLogs ?? []).map { ("agent-\($0.name)", $0.text) }
        let redacted = files.map { ($0.0, ArisRedaction.redact($0.1, secrets: secrets, home: home)) }
        do {
            try await Task.detached(priority: .userInitiated) { try zip(redacted, folderName: name.replacingOccurrences(of: ".zip", with: ""), to: destination) }.value
        } catch {
            return "진단 파일을 만들지 못했어요: \(error.localizedDescription)"
        }
        return "“\(destination.lastPathComponent)”을 만들었어요" + (agentLogs == nil ? ". 에이전트가 꺼져 있어서 앱 기록만 담았어요" : "")
    }

    private static func info(agentAnswered: Bool, now: Date) -> String {
        let bundle = Bundle.main
        var model = [CChar](repeating: 0, count: 64)
        var size = model.count
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let permissions = ArisOnboardingStep.allCases.filter { $0.way != .consent }.map { step -> String in
            let grant = ArisOnboardingSystem.grant(step)
            return "  \(step.title): \(grant == .granted ? "켜짐" : grant == .denied ? "거부됨" : "꺼짐")"
        }
        return """
        Aris \(bundle.releaseVersionNumber ?? "?") (\(bundle.buildVersionNumber ?? "?"))
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        Mac \(String(cString: model))
        만든 때 \(ISO8601DateFormatter().string(from: now))
        에이전트 \(agentAnswered ? "응답함" : "응답 없음")
        로그인 시 실행 \(ArisLoginItem.isEnabled ? "켜짐" : "꺼짐")
        권한
        \(permissions.joined(separator: "\n"))

        """
    }

    /// This process's own unified-log lines since `since` (private values stay "<private>" as macOS writes them).
    private static func appLog(since: Date) -> String {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier),
              let entries = try? store.getEntries(at: store.position(date: since)) else { return "(앱 기록을 읽지 못했어요)\n" }
        let stamp = ISO8601DateFormatter()
        var lines: [String] = []
        for case let entry as OSLogEntryLog in entries where entry.subsystem.hasPrefix("com.lumenjsn.aris") || entry.level.rawValue >= OSLogEntryLog.Level.error.rawValue {
            lines.append("\(stamp.string(from: entry.date)) [\(entry.category)] \(entry.composedMessage)")
            if lines.count >= 5_000 { lines.removeFirst(1_000) }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The files in a folder named `folderName`, zipped (NSFileCoordinator's .forUploading makes the zip), at `destination`.
    nonisolated private static func zip(_ files: [(String, String)], folderName: String, to destination: URL) throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("aris-diagnostics-\(UUID().uuidString)", isDirectory: true)
        let folder = work.appendingPathComponent(folderName, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        for (name, text) in files {
            try Data(text.utf8).write(to: folder.appendingPathComponent(name), options: .atomic)
        }
        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinatorError) { zipped in
            do {
                if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                try fm.copyItem(at: zipped, to: destination)
            } catch {
                copyError = error
            }
        }
        if let error = coordinatorError ?? copyError { throw error }
    }
}
