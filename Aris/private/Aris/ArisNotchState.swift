//
//  ArisNotchState.swift
//  Aris
//
//  The root notch view's window onto ArisController: a deduplicated ArisNotchSnapshot, published only when one of its
//  few facts changes, so the view of every display isn't re-evaluated for each streamed token, job tick or thumbnail.
//

import Combine
import Foundation

@MainActor
final class ArisNotchState: ObservableObject {
    static let shared = ArisNotchState()

    @Published private(set) var current: ArisNotchSnapshot
    private var watching: [AnyCancellable] = []

    var isActive: Bool { current.isActive }
    var phase: ArisSession.Phase { current.phase }
    var hasReply: Bool { current.hasReply }
    var isTraining: Bool { current.isTraining }
    var isDictating: Bool { current.isDictating }
    var dictationCopied: Bool { current.dictationCopied }
    var hasUnfinishedTask: Bool { current.hasUnfinishedTask }
    var taskJustFinished: Bool { current.taskJustFinished }
    var holdsNotch: Bool { current.holdsNotch }
    /// A card (a confirm, a question, the new-teammate card) waits for the user's answer.
    var cardWaiting: Bool { current.hasQuestion }
    var conversing: Bool { current.conversing }
    var listeningPaused: Bool { current.listeningPaused }

    private init() {
        let aris = ArisController.shared
        current = Self.snapshot(of: aris)
        // @Published emits on willSet, before the controller's property holds the new value: receive(on: main) defers
        // the sink to the next main-queue turn, after the didSet, so the snapshot is rebuilt from the value that is
        // now stored. It's kept only when it differs.
        let changes: [AnyPublisher<Void, Never>] = [
            aris.$session.map { _ in () }.eraseToAnyPublisher(),
            aris.$training.map { _ in () }.eraseToAnyPublisher(),
            aris.$dictation.map { _ in () }.eraseToAnyPublisher(),
            aris.$jobs.map { _ in () }.eraseToAnyPublisher(),
            aris.$taskJustFinished.map { _ in () }.eraseToAnyPublisher(),
            aris.$inConversation.map { _ in () }.eraseToAnyPublisher(),
            aris.$pausedForOtherAudio.map { _ in () }.eraseToAnyPublisher(),
            ArisTeamModel.shared.$made.map { _ in () }.eraseToAnyPublisher(),
        ]
        watching = changes.map { publisher in
            publisher.receive(on: DispatchQueue.main).sink { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let next = Self.snapshot(of: ArisController.shared)
                    if next != self.current { self.current = next }
                }
            }
        }
    }

    private static func snapshot(of aris: ArisController) -> ArisNotchSnapshot {
        ArisNotchSnapshot(session: aris.session, isTraining: aris.training != nil, isDictating: aris.dictation != nil,
                          hasUnfinishedTask: aris.tasks.contains { !$0.isFinished }, taskJustFinished: aris.taskJustFinished,
                          inConversation: aris.inConversation, pausedForOtherAudio: aris.pausedForOtherAudio,
                          dictationCopied: aris.dictation == .typed && ArisDictationState.shared.copied,
                          cardWaiting: ArisTeamModel.shared.made != nil)
    }
}
