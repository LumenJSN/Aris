//
//  ArisVoiceIDLive.swift
//  Aris
//
//  Settings › 부르기 › 내 목소리's state (F1): what ArisVoiceIDRows shows, read off the main thread (loading the model
//  to see that it opens takes a moment), the switch, and 지우기 asked twice. Refreshed when the print changes
//  (ArisVoiceID.changed).
//

import Foundation

@MainActor
final class ArisVoiceIDLive: ObservableObject {
    static let shared = ArisVoiceIDLive()

    @Published private(set) var summary = ArisVoiceIDSummary()
    private var observer: NSObjectProtocol?

    private init() {
        summary.on = ArisVoiceID.shared.isOn
        observer = NotificationCenter.default.addObserver(forName: ArisVoiceID.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        let confirming = summary.confirmingForget
        Task.detached(priority: .utility) {
            let status = ArisVoiceID.shared.status
            await MainActor.run {
                self.summary = ArisVoiceIDSummary(on: status.on, enrolled: status.enrolled, samples: status.samples, available: status.available,
                                                  confirmingForget: confirming && status.samples > 0)
            }
        }
    }

    func setOn(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: ArisVoiceID.key)
        summary.on = on
        if on { ArisVoiceEmbedder.shared.warm() }
        ArisVoiceID.shared.switched()
    }

    /// 지우기: the first press asks, the second deletes. True when it was deleted.
    func forgetPressed() async -> Bool {
        guard summary.confirmingForget else {
            summary.confirmingForget = true
            return false
        }
        summary.confirmingForget = false
        let gone = await Task.detached(priority: .userInitiated) { ArisVoiceID.shared.forget() }.value
        refresh()
        return gone
    }

    func cancelForget() { summary.confirmingForget = false }
}
