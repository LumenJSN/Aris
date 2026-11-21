//
//  ArisTaskTrail.swift
//  aris-agent
//
//  One background task's journal as it runs (ArisTaskJournal): the runner hands it what happens, on its own queue,
//  and it writes the records. Each step goes in as the gate describes it in actions.log (ArisCodexDriver.what), each
//  status line as the notch showed it, each card with its own title and details and its answer,
//  the brain's session handle when it has one, the taint when it rises, and how it ended. Nothing else: no answer
//  text (a restart is told the steps, never what a model wrote), no images, no context block, no tool output.
//

import Foundation

final class ArisTaskTrail {
    let job: String
    private let home: String
    private let tools: String
    private var session: String?
    private var taint = ArisTaint.none
    private(set) var ended = false
    private var lastStatus: String?

    init(job: String, home: String, tools: String) {
        self.job = job
        self.home = home
        self.tools = tools
    }

    /// The helper is exiting (SIGTERM, SIGINT): nothing more is written, so its tasks stay open for the next one to
    /// take back (their brains end with it and must not be read as failed). Only an answer that came meanwhile is
    /// still written as the task's end (`ended(.answered)`), the helper's own record: that task is done and never
    /// taken back to do its work and report a second time.
    nonisolated(unsafe) static var shuttingDown = false

    private func write(_ record: ArisTaskRecord, evenWhileExiting: Bool = false) {
        guard !ended, evenWhileExiting || !Self.shuttingDown else { return }
        if !ArisTaskJournal.append(record, job: job, home: home) {
            FileHandle.standardError.write(Data("aris-agent: couldn't write the journal of job \(job.prefix(8))\n".utf8))
        }
    }

    func created(title: String, request: String, prompt: String, brain: ArisBrain, model: String, origin: ArisTaskOrigin) {
        write(.created(job: job, title: title, request: request, prompt: prompt, brain: brain.rawValue, model: model, origin: origin))
    }

    func started() { write(.started()) }

    func recovered(_ how: ArisTaskRecord.Recovery) { write(.recovered(how)) }

    /// What the brain did, as the runner read it from its line.
    func saw(_ event: ArisBrainEvent) {
        switch event {
        case .tools(let calls):
            for call in calls {
                let effect = ArisTurnSideEffects.mayChange(call, tools: tools)
                write(.step(Self.described(call), effect: effect))
            }
        case .status(let line):
            guard line != lastStatus else { return }
            lastStatus = line
            write(.status(line))
        case .delta, .send, .stepFailed, .confirm, .audit, .result, .failure, .unavailable, .abort:
            break
        }
    }

    /// The step as actions.log names it.
    static func described(_ call: ArisAgentStream.ToolCall) -> String {
        if let command = call.command { return ArisCodexDriver.what(.shell(command)) }
        return "tool: " + call.name
    }

    /// The brain's session or thread handle, when it has one (written when it changes).
    func session(_ handle: String?) {
        guard let handle, handle != session else { return }
        session = handle
        write(.session(handle))
    }

    /// The taint, when it rose.
    func taint(_ now: ArisTaint) {
        guard now > taint else { return }
        taint = now
        write(.tainted(Self.word(now)))
    }

    func card(_ shown: ArisConfirmation) {
        write(.card(ArisTaskCard(id: shown.id, title: shown.title, detail: shown.detail, full: shown.full)))
    }

    func answer(_ id: String, allow: Bool, how: String? = nil) {
        write(.answer(id, allow: allow, how: how))
    }

    /// It ended, and how (an answer's text is not kept: the app has it from the stream or the inbox; a failure keeps
    /// its short line). Nothing more is written after. True when the end was written.
    @discardableResult
    func ended(_ ending: ArisTaskRecord.Ending, line: String? = nil) -> Bool {
        guard !ended, ending == .answered || !Self.shuttingDown else { return false }
        let kept = ending == .answered ? nil : line.map { ArisTaskLimits.cut($0, ArisTaskLimits.line) }
        write(.ended(ending, line: kept, taint: Self.word(taint)), evenWhileExiting: true)
        ended = true
        return true
    }

    static func word(_ taint: ArisTaint) -> String {
        switch taint {
        case .none: return "none"
        case .screenSeen: return "screenSeen"
        case .outsideText: return "outsideText"
        }
    }

    static func taint(_ word: String) -> ArisTaint {
        switch word {
        case "outsideText": return .outsideText
        case "screenSeen": return .screenSeen
        default: return .none
        }
    }
}
