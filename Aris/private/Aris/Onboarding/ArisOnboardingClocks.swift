//
//  ArisOnboardingClocks.swift
//  Aris
//
//  Every delayed beat of the first-run guide (the intro's copy, the handoff, a step's fade, the yield delay) runs
//  through here, so closing the guide (Esc, 나중에 할게요, 확인, quitting) or skipping the intro cancels them all at once and nothing fires
//  afterwards. Pure enough to test without a screen.
//

import Foundation

@MainActor
final class ArisOnboardingClocks {
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var named: [String: UUID] = [:]

    /// Beats still waiting.
    var pending: Int { tasks.count }

    /// Runs `work` after `seconds` unless cancelled first. A `name` replaces the beat of that name still waiting.
    func after(_ seconds: Double, name: String? = nil, _ work: @escaping @MainActor () -> Void) {
        if let name, let old = named[name] { cancel(old) }
        let id = UUID()
        if let name { named[name] = id }
        tasks[id] = Task { @MainActor [weak self] in
            if seconds > 0 { try? await Task.sleep(for: .seconds(seconds)) }
            guard !Task.isCancelled, let self, self.tasks[id] != nil else { return }
            self.finished(id)
            work()
        }
    }

    func cancel(name: String) {
        if let id = named[name] { cancel(id) }
    }

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        named = [:]
    }

    private func cancel(_ id: UUID) {
        tasks.removeValue(forKey: id)?.cancel()
        named = named.filter { $0.value != id }
    }

    private func finished(_ id: UUID) {
        tasks.removeValue(forKey: id)
        named = named.filter { $0.value != id }
    }
}
