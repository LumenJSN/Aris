//
//  ArisCardDesk.swift
//  Aris
//
//  The questions waiting off screen (ArisWaitingList), for the open notch's 확인 대기 chips, and the scheduled jobs'
//  questions being asked right now (so a second fetch of the inbox doesn't ask the same one twice).
//

import Foundation

@MainActor
final class ArisCardDesk: ObservableObject {
    static let shared = ArisCardDesk()

    @Published private(set) var waiting = ArisWaitingList()
    /// The inbox items whose question has a task of its own asking it.
    private var inboxAsking: Set<String> = []

    private init() {}

    func park(_ card: ArisWaitingCard) { waiting = waiting.parking(card) }
    func remove(_ id: String) { waiting = waiting.removing(id) }
    /// A click on a chip: that card comes back as soon as Aris is free.
    func open(_ id: String) { waiting = waiting.opening(id) }
    func isOpened(_ id: String) -> Bool { waiting.isOpened(id) }

    /// False when that item's question is already being asked.
    func beginInbox(_ id: String) -> Bool { inboxAsking.insert(id).inserted }
    func endInbox(_ id: String) { inboxAsking.remove(id) }
}
