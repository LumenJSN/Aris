//
//  ArisAgentClient+Teammate.swift
//  Aris
//
//  Opening a Claude Code teammate through aris-agent (POST /teammate): the sandboxed app can neither write its prompt
//  file in ~/.config/aris nor script Terminal. The replies come as they happen: a status (waiting for the user, whose card
//  comes through the inbox, never this stream), then `.launched` once the window is open. The stream then stays open
//  while the session works; ending it (the job is done or cancelled) lets the agent delete the prompt file and free
//  the slot.
//

import Defaults
import Foundation

extension ArisAgentClient {
    private static let teammateURL = URL(string: "http://127.0.0.1:23351/teammate")!

    /// `turn`: the id the agent gave the turn that dispatched this job (it vouches for it); nil asks the user first.
    /// `request`: the user's words for the turn, which the agent also checks for outbound steps.
    /// `title`: the job's, for the name of its terminal window ("Aris · <job>").
    static func teammate(job: UUID, teammate: String, prompt: String, cwd: String, turn: String?, request: String?,
                         title: String? = nil) -> AsyncStream<ArisAgentReply> {
        AsyncStream { continuation in
            let work = Task {
                await streamTeammate(job: job, teammate: teammate, prompt: prompt, cwd: cwd, turn: turn, request: request, title: title) { continuation.yield($0) }
                continuation.finish()
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    private static func streamTeammate(job: UUID, teammate: String, prompt: String, cwd: String, turn: String?, request userRequest: String?, title: String?,
                                       yield: (ArisAgentReply) -> Void) async {
        guard let token = ClaudeHookToken.load() else { return yield(.failure(notSetUp)) }
        var request = URLRequest(url: teammateURL, timeoutInterval: ArisParkedCard.streamTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        var body: [String: Any] = ["job": job.uuidString, "teammate": teammate, "prompt": prompt, "cwd": cwd,
                                   "pid": Int(ProcessInfo.processInfo.processIdentifier)]
        if let turn { body["turn"] = turn }
        if let userRequest { body["request"] = userRequest }
        if let title { body["title"] = title }
        // The user's terminal, as far as the app knows it: the one pinned in Settings and the one they last ran Claude Code
        // in (the agent picks from these and from what is installed and running: ArisTerminalChoice).
        if let pinned = ArisTerminalMemory.pinned(Defaults[.arisTeammateTerminal]) { body["terminal"] = pinned }
        if let used = ArisTerminal(rawValue: Defaults[.arisClaudeTerminal]) { body["terminalUsed"] = used.rawValue }
        if let started { body["started"] = started }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (bytes, response) = try await taskSession.bytes(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return yield(.failure(refused)) }
            for try await line in bytes.lines {
                guard let reply = ArisAgentReply.parse(line) else { continue }
                yield(reply)
                if reply.isLast { return }
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            yield(.failure(failure(describing: error)))
        }
    }
}
