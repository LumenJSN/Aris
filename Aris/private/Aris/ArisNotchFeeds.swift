//
//  ArisNotchFeeds.swift
//  Aris
//
//  Two more of the root notch view's windows onto the app, deduplicated like ArisNotchState: what the root reads of
//  Claude Code's store, and the preferences it reads. Observing ClaudeStore itself re-evaluated every display's root
//  body on each hook event (a session's last-event time changes with every tool call), and each evaluation read a dozen
//  preferences from UserDefaults through @Default. Now the body is evaluated again only when something it draws from
//  changed: whether Claude Code claims the closed notch, whether any session is open, the approvals, or a preference.
//  The Claude views under it (ClaudeLiveActivity, ClaudeTabView) observe the store themselves, as before.
//

import Combine
import Defaults
import Foundation

/// What the root notch view draws from ClaudeStore.
struct ArisNotchClaude: Equatable {
    var isLive = false
    var hasSessions = false
    var approvals: [ClaudeApproval] = []
}

@MainActor
final class ArisNotchClaudeState: ObservableObject {
    static let shared = ArisNotchClaudeState()

    @Published private(set) var current: ArisNotchClaude
    private var watching: [AnyCancellable] = []

    private init() {
        let store = ClaudeStore.shared
        current = Self.snapshot(of: store)
        // @Published emits on willSet: the sink runs on the next main-queue turn and reads the values now stored.
        let changes: [AnyPublisher<Void, Never>] = [
            store.$sessions.map { _ in () }.eraseToAnyPublisher(),
            store.$approvals.map { _ in () }.eraseToAnyPublisher(),
        ]
        watching = changes.map { publisher in
            publisher.receive(on: DispatchQueue.main).sink { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let next = Self.snapshot(of: ClaudeStore.shared)
                    if next != self.current { self.current = next }
                }
            }
        }
    }

    private static func snapshot(of store: ClaudeStore) -> ArisNotchClaude {
        ArisNotchClaude(isLive: store.isLive, hasSessions: store.hasSessions, approvals: store.approvals)
    }
}

/// The preferences the root notch view reads, read once per change instead of once per evaluation.
struct ArisNotchPrefs: Equatable {
    var gesturesOn: Bool
    var closeGestureOn: Bool
    var mediaGesturesOn: Bool
    var sensitivity: CGFloat
    var hapticsOn: Bool
    var openOnHover: Bool
    var hoverDelay: TimeInterval
    var shelfOn: Bool
    var peekStyle: SneakPeekStyle
    var cornerScaling: Bool
    var muted: Bool
    var restStarShown: Bool
    /// The hidden arisClosedRest (ArisVNotchRest), read raw.
    var closedRest: String?

    static func read() -> ArisNotchPrefs {
        ArisNotchPrefs(gesturesOn: Defaults[.enableGestures], closeGestureOn: Defaults[.closeGestureEnabled],
                       mediaGesturesOn: Defaults[.enableHorizontalMediaGestures], sensitivity: Defaults[.gestureSensitivity],
                       hapticsOn: Defaults[.enableHaptics], openOnHover: Defaults[.openNotchOnHover], hoverDelay: Defaults[.minimumHoverDuration],
                       shelfOn: Defaults[.shelfEnabled], peekStyle: Defaults[.sneakPeekStyles], cornerScaling: Defaults[.cornerRadiusScaling],
                       muted: Defaults[.arisMuted], restStarShown: Defaults[.arisRestStar], closedRest: Defaults[.arisClosedRestRaw])
    }
}

extension Defaults.Keys {
    /// ArisVNotchRest.preferenceKey as a key, so it is watched like the others (it has no default: nil is the out-of-sight rest).
    static let arisClosedRestRaw = Key<String?>(ArisVNotchRest.preferenceKey)
}

@MainActor
final class ArisNotchPrefsState: ObservableObject {
    static let shared = ArisNotchPrefsState()

    @Published private(set) var current = ArisNotchPrefs.read()
    private var watching: [AnyCancellable] = []

    private init() {
        // Defaults.publisher observes each key (KVO, a change made anywhere, even outside the app), as @Default did.
        let keys: [AnyPublisher<Void, Never>] = [
            Defaults.publisher(.enableGestures, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.closeGestureEnabled, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.enableHorizontalMediaGestures, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.gestureSensitivity, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.enableHaptics, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.openNotchOnHover, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.minimumHoverDuration, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.shelfEnabled, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.sneakPeekStyles, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.cornerRadiusScaling, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.arisMuted, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.arisRestStar, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.arisClosedRestRaw, options: []).map { _ in () }.eraseToAnyPublisher(),
        ]
        watching = keys.map { publisher in
            publisher.receive(on: DispatchQueue.main).sink { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let next = ArisNotchPrefs.read()
                    if next != self.current { self.current = next }
                }
            }
        }
    }
}
