//
//  ArisFixModel.swift
//  Aris
//
//  The live half of the button under a failure (its rules are ArisFixDesk's, pure): it takes the fix aris-agent sends
//  on a conversation's stream, follows the controller's turn, does what a press means (System Settings on the right
//  list, Aris's Settings on the right row, the AI's login in Terminal, the same request again, a command on the
//  clipboard), and after a press watches for the fix to show, then asks the same thing again (ArisFixReturn).
//  The buttons are there whether Aris speaks or not: nothing here depends on the voice.
//

import AppKit
import AVFoundation
import Combine
import Defaults
import EventKit
import os
import SwiftUI

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "fix")

@MainActor
final class ArisFixModel: ObservableObject {
    static let shared = ArisFixModel()

    /// How long "복사했어요" stays on the button.
    private static let feedbackStays: Duration = .seconds(3)

    @Published private(set) var desk = ArisFixDesk()
    /// Said on the button for a moment after a press that copied something.
    @Published private(set) var feedback: String?

    private var watches: Set<AnyCancellable> = []
    /// The turn as last seen, to tell a new turn (or a stop) from the turn going on.
    private var last = ArisFixMoment()
    private var returning: Task<Void, Never>?
    private var feedbackClear: Task<Void, Never>?
    /// A question lost to a helper that was not there, until the helper answers again (ArisHelperWatch).
    private var helper = ArisHelperWatch()
    private var helperLooks: Task<Void, Never>?

    /// The turn the notch holds now.
    private var moment: ArisFixMoment { Self.moment(ArisController.shared.session) }

    /// What shows under `session`'s reply.
    func offer(for session: ArisSession) -> ArisFixOffer? { desk.offer(Self.moment(session)) }

    // MARK: - From the stream and the turn

    /// A conversation's stream carried a fix (ArisAgentClient), just before its last line.
    nonisolated static func arrived(_ fix: ArisFix) async {
        await MainActor.run { shared.take(fix) }
    }

    /// The app's own route answered a tool with something the user can fix (aris-tools' to-do call without Reminders access).
    /// Only while a turn is at work: the same call from a background job is not this turn's failure.
    func noted(_ fix: ArisFix) {
        guard moment.phase == .thinking else { return }
        take(fix)
    }

    private func take(_ fix: ArisFix) {
        watch()
        desk = desk.arriving(fix)
        log.notice("fix for this turn: \(fix.kind.rawValue, privacy: .public) \(fix.kind == .copy ? "" : fix.target, privacy: .public)")
        // A permission that is already on (the brain got there another way, or it was turned on meanwhile) gets no button.
        guard fix.kind == .pane, let check = ArisFixReturn.check(for: fix) else { return }
        Task { if await Self.read(check) == true { desk = desk.foundOn(fix) } }
    }

    /// Follows the controller's turn from the first time it is needed (never while the controller is being made).
    func watch() {
        guard watches.isEmpty else { return }
        let aris = ArisController.shared
        last = Self.moment(aris.session)
        aris.$session.receive(on: DispatchQueue.main).sink { [weak self] session in
            MainActor.assumeIsolated { self?.moved(to: Self.moment(session)) }
        }.store(in: &watches)
    }

    private func moved(to next: ArisFixMoment) {
        guard next != last else { return }
        let after = desk.moving(from: last, to: next)
        // A turn heard without the key is never asked again by Aris itself (ArisHelperWatch.Lost.handsFree).
        let watched = helper.moving(from: last, to: next, now: Date(), handsFree: ArisController.shared.turnHandsFree)
        last = next
        if after != desk { desk = after }
        let lostNow = watched.lost != nil && watched.lost != helper.lost
        helper = watched
        if lostNow { lookForHelper() } else if helper.lost == nil { helperLooks?.cancel() }
    }

    /// A turn with circled shots can't be asked again from its words alone, so it offers no "again".
    static func moment(_ session: ArisSession) -> ArisFixMoment {
        let phase: ArisFixMoment.Phase
        switch session.phase {
        case .idle: phase = .idle
        case .listening: phase = .listening
        case .thinking: phase = .thinking
        case .speaking: phase = .speaking
        case .failed: phase = .failed
        }
        let words = ArisGestureMarkers.badges(in: session.heard).isEmpty ? session.heard : ""
        return ArisFixMoment(phase: phase, heard: words, reply: session.reply, asking: session.question != nil,
                             worked: !session.steps.isEmpty || session.question != nil)
    }

    // MARK: - A press

    func press(_ fix: ArisFix) {
        watch()
        let now = moment
        let request = now.heard
        log.notice("fix pressed: \(fix.kind.rawValue, privacy: .public)")
        switch fix.kind {
        case .retry, .otherBrain:
            return askAgain(request)
        case .pane:
            if let pane = fix.pane {
                open(pane)
                // macOS's list (or its own question) is what he looks at now: the notch steps out of its way.
                ArisStepAside.openedElsewhere()
            }
        case .settings:
            if let row = fix.row { open(row) }
        case .login:
            Task {
                guard await ArisAgentClient.loginBrain(fix.target) else {
                    // Terminal couldn't be opened for him: the command itself, to paste there.
                    if let command = ArisFixWords.loginCommand(fix.target) { copy(command) }
                    return say(ArisFixWords.loginCopied(english: ArisUIWords.english))
                }
            }
        case .copy:
            copy(fix.target)
            say(ArisFixWords.copied(english: ArisUIWords.english))
        case .acceptProgram:
            // The owner's yes to an AI program that changed: only this app's own request reaches the helper.
            Task { _ = await ArisAgentClient.acceptProgram(fix.target) }
        case .showApp:
            // Only ever this app's own bundle: nothing from the fix names a file.
            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
            ArisStepAside.openedElsewhere()
        }
        desk = desk.pressing(fix, under: now.reply)
        arm(request, fix)
    }

    /// The permission card's own button opened that list (ArisWidgetModel): the same wait for it to turn on.
    func openedElsewhere(_ fix: ArisFix) {
        watch()
        arm(moment.heard, fix)
    }

    /// The quiet "다시 해보기", and "다시 해보기" as the button itself.
    func askAgain() { askAgain(moment.heard) }

    /// His press on "다시 해보기" asks the words again through the composer's path: the press is his own act at this Mac,
    /// on words he can read above the button. A turn first heard without the key (the wake word, a follow-up) has
    /// limits because such words may not be his: Aris never puts them in again by itself (ArisHelperWatch.Lost.handsFree,
    /// ArisFixReturn.watches; security review 6, M1), and when he presses they are asked as they were heard, still
    /// hands-free (submitTyped's `again`), so the hands-free limits hold and the automatic check never counts them as
    /// his own words (auto L7). The hands-free rules win over auto mode.
    private func askAgain(_ request: String) {
        returning?.cancel()
        guard !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        ArisController.shared.submitTyped(request, again: true)
    }

    private func open(_ pane: ArisFix.Pane) {
        switch pane {
        // The app's own access: macOS asks when it never has, and its list opens when it was refused.
        case .reminders: Task { await ArisReminders.shared.requestAccess() }
        case .calendars: Task { await ArisCalendarStore.shared.requestAccess() }
        case .microphone:
            // The line asks for the microphone and speech recognition: the list of the one still off, the microphone first.
            let list: ArisFix.Pane = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized ? .speech : .microphone
            if let url = URL(string: list.link) { NSWorkspace.shared.open(url) }
        default:
            if let url = URL(string: pane.link) { NSWorkspace.shared.open(url) }
        }
    }

    private func open(_ row: ArisFix.Row) {
        // The helper isn't running: its restart, as the star beside the camera does it. Asked first whether it answers
        // now: when it had already come back the button says so (a press that did nothing looked broken), and
        // "다시 해보기" beside it asks again.
        if row == .helper {
            // The watch for its return begins again with the press (a minute of "Restarting the helper…").
            helper = helper.pressed(under: moment, now: Date(), handsFree: ArisController.shared.turnHandsFree)
            lookForHelper()
            Task {
                let answering = await ArisAgentClient.probe() == .answered
                if !answering { ArisAgentMonitor.shared.restart(asked: true) }
                say(ArisFixWords.helperPress(answering: answering, english: ArisUIWords.english))
                // It had come back before the press: the question is asked again now, not left under a stale line.
                if answering { _ = helperLooked(answering: true) }
                if !answering { await showRestarting() }
            }
            return
        }
        ArisSettingsNav.shared.go(ArisSettingsPage.named(row.page) ?? .ai, anchor: row.anchor)
        ArisStepAside.showSettings()
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func say(_ words: String) {
        feedback = words
        feedbackClear?.cancel()
        feedbackClear = Task { [weak self] in
            try? await Task.sleep(for: Self.feedbackStays)
            guard !Task.isCancelled else { return }
            self?.feedback = nil
        }
    }

    /// The helper's button keeps saying "Restarting the helper…" until the helper answers or the limit is up
    /// (ArisFixWords.stillRestarting), then says it is back (or is the button again).
    private func showRestarting() async {
        let began = Date()
        var answering = false
        while ArisFixWords.stillRestarting(answering: answering, waited: Date().timeIntervalSince(began)) {
            feedbackClear?.cancel()
            feedback = ArisFixWords.helperRestarting(english: ArisUIWords.english)
            try? await Task.sleep(for: .seconds(ArisFixWords.restartLook))
            answering = await ArisAgentClient.probe() == .answered
        }
        if answering { say(ArisFixWords.helperBack(english: ArisUIWords.english)) } else { feedback = nil }
        if answering { _ = helperLooked(answering: true) }
    }

    // MARK: - The helper's return

    /// Asks the helper every ArisHelperWatch.every whether it answers, from the failure on (no press needed), until
    /// the watch says it is over.
    private func lookForHelper() {
        helperLooks?.cancel()
        guard helper.lost != nil else { return }
        helperLooks = Task { [weak self] in
            while !Task.isCancelled {
                let answering = await ArisAgentClient.probe() == .answered
                guard let self, !Task.isCancelled, self.helperLooked(answering: answering) else { return }
                try? await Task.sleep(for: .seconds(ArisHelperWatch.every))
            }
        }
    }

    /// One look at the helper, and what the watch makes of it; false once the watch is over.
    private func helperLooked(answering: Bool) -> Bool {
        let (next, step) = helper.looked(answering: answering, moment: moment, now: Date())
        helper = next
        switch step {
        case .wait:
            return true
        case .drop:
            return false
        case .askAgain(let request):
            log.notice("the helper answers again: asking the same thing again")
            clearFeedback()
            ArisController.shared.submitTyped(request)
            return false
        case .back:
            log.notice("the helper answers again: the question is left to them (the lost turn had worked, or was asked again once)")
            clearFeedback()
            ArisController.shared.helperCameBack()
            return false
        }
    }

    private func clearFeedback() {
        feedbackClear?.cancel()
        feedback = nil
    }

    // MARK: - After the press

    /// Watches the fix for ArisFixReturn.window; when it turns on, the same request is asked again.
    private func arm(_ request: String, _ fix: ArisFix) {
        returning?.cancel()
        // Nothing is watched for the helper (its own watch), nor for a turn heard without the key (ArisFixReturn.watches).
        guard let check = ArisFixReturn.watches(fix, request: request, handsFree: ArisController.shared.turnHandsFree) else { return }
        returning = Task { [weak self] in
            var armed = ArisFixReturn.Armed(request: request, fix: fix, at: Date())
            while !Task.isCancelled {
                let fixed = await Self.read(check)
                guard let self, !Task.isCancelled else { return }
                let now = self.moment
                let busy = now.phase == .listening || now.phase == .thinking || now.asking
                switch ArisFixReturn.next(armed, fixed: fixed, heard: now.heard, busy: busy, now: Date()) {
                case .wait(let still): armed = still
                case .drop: return
                case .askAgain:
                    log.notice("the fix is on: asking the same thing again")
                    return ArisController.shared.submitTyped(request, again: true)
                }
                try? await Task.sleep(for: .seconds(ArisFixReturn.every))
            }
        }
    }

    /// What is so now; nil when it couldn't be read.
    private static func read(_ check: ArisFixReturn.Check) async -> Bool? {
        switch check {
        case .agentDisk: return await ArisAgentClient.agentHasDiskAccess()
        case .agentScreen: return await ArisAgentClient.agentHasScreenAccess()
        // Read from macOS at each look, with a new store once access is on (ArisRemindersAccess).
        case .reminders: return ArisReminders.shared.accessNow()
        case .calendars: return EKEventStore.authorizationStatus(for: .event) == .fullAccess
        case .helper: return await ArisAgentClient.probe() == .answered
        case .brain:
            guard await ArisBrainSetup.shared.refresh() else { return nil }
            return ArisBrainSetup.shared.ready?[ArisBrain.named(Defaults[.arisBrain])]
        }
    }
}

/// The live row under the reply: the offer's buttons, doing what the model does.
struct ArisFixButtons: View {
    let offer: ArisFixOffer
    @ObservedObject private var model = ArisFixModel.shared

    var body: some View {
        ArisFixButtonRow(offer: offer, feedback: model.feedback, english: ArisUIWords.english,
                         press: { model.press(offer.fix) }, again: { model.askAgain() })
    }
}
