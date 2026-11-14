//
//  ArisTimerModel.swift
//  Aris
//
//  The running timer (ArisTimerState): "타이머 25분", "25분 집중", "뽀모도로" (focus and breaks in turn). Pause,
//  resume, add time and cancel by voice or from the timer's menu (the closed notch's ears, the open notch's pill).
//  At the end a chime rings three times and Aris says so in the notch; a pomodoro moves on to its next phase. It's
//  saved, so a running timer survives the app restarting.
//

import AppKit
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "timer")

@MainActor
final class ArisTimerModel: ObservableObject {
    static let shared = ArisTimerModel()

    @Published private(set) var state: ArisTimerState? {
        didSet { save() }
    }
    private var ending: Task<Void, Never>?

    private static let savedKey = "arisTimer"
    private static let chimes = 3
    private static let chimeGap: Duration = .milliseconds(900)

    var isRunning: Bool { state != nil }

    init() {
        guard let data = UserDefaults.standard.data(forKey: Self.savedKey),
              let saved = try? JSONDecoder().decode(ArisTimerState.self, from: data) else { return }
        state = saved
        schedule()
    }

    func start(seconds: Int, focus: Bool) {
        set(.start(seconds: seconds, phase: focus ? .focus : .plain, at: .now))
    }

    func startPomodoro() {
        set(.start(seconds: ArisTimerState.focusSeconds, phase: .focus, at: .now, round: 1, cycle: true))
    }

    /// `aris-tools timer …` (the AI setting the timer): aris/timer.json, nudged by com.lumenjsn.aris.timer.
    func watchRequests() {
        DistributedNotificationCenter.default().addObserver(forName: .init("com.lumenjsn.aris.timer"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ArisTimerModel.shared.takeRequest() }
        }
    }

    private func takeRequest() {
        let file = URL(fileURLWithPath: ArisKeyFile.folder + "aris/timer.json")
        guard let data = try? Data(contentsOf: file),
              let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        try? FileManager.default.removeItem(at: file)
        switch request["action"] as? String {
        case "stop": cancel()
        case "pomodoro": startPomodoro()
        case "start":
            guard let seconds = request["seconds"] as? Int, seconds > 0 else { return }
            start(seconds: seconds, focus: request["focus"] as? Bool ?? false)
        default: break
        }
    }

    func cancel() { set(nil) }
    func pause() { state.map { set($0.paused(at: .now)) } }
    func resume() { state.map { set($0.resumed(at: .now)) } }
    func togglePause() { state?.isPaused == true ? resume() : pause() }
    func add(_ seconds: Int) { state.map { set($0.adding(seconds, at: .now)) } }

    /// "12분 30초 남았어요", for "얼마나 남았어".
    func leftLine(korean: Bool) -> String {
        guard let state else { return ArisLocalReply.noTimer(korean: korean) }
        let left = ArisIntent.duration(state.left(at: .now))
        let paused = state.isPaused ? (korean ? " 지금은 멈춰 있어요." : " It's paused.") : ""
        return korean ? "\(left) 남았어요.\(paused)" : "\(left) left.\(paused)"
    }

    private func set(_ new: ArisTimerState?) {
        state = new
        schedule()
    }

    /// One task waits for the end of the running phase (none while paused).
    private func schedule() {
        ending?.cancel()
        guard let state, !state.isPaused, let endsAt = state.endsAt else { return }
        ending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, endsAt.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.finish(state)
        }
    }

    private func finish(_ ended: ArisTimerState) {
        log.notice("timer: \(ended.phase.rawValue, privacy: .public) ended")
        set(ended.next(at: .now))
        Task {
            // A timer the user set rings in quiet time too; only a muted Aris keeps it to the notch (ArisQuiet).
            guard ArisQuietGate.maySound(.userTimer) else { return }
            for index in 0..<Self.chimes {
                if index > 0 { try? await Task.sleep(for: Self.chimeGap) }
                NSSound(named: "Glass")?.play()
            }
        }
        let (title, text) = ArisTimerWords.ended(ended.phase, cycle: ended.cycle, round: ended.round, total: ended.total, nextTotal: state?.total ?? 0, nextRound: state?.round ?? 1)
        ArisController.shared.announce(title: title, text: text, kind: .reminder)
    }

    private func save() {
        if let state, let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.savedKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.savedKey)
        }
    }
}
