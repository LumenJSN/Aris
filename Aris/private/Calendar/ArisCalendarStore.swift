//
//  ArisCalendarStore.swift
//  Aris
//
//  Calendar access, the calendars the owner chose, and event queries for the side panel, the brief, the widgets and the
//  AI's context. Prompts for access only from a permission button (requestAccess) or a first question
//  (checkAccess); loading never prompts.
//

import AppKit
import Combine
import EventKit
import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "calendar")

/// Where calendars and events come from: EventKit in the app (ArisEventKitSource), a stand-in in tests.
/// Everything that asks EventKit is `async`: the live source asks it off the main actor (ArisCalendarReader), and
/// the store here keeps what was last read for the views.
@MainActor
protocol ArisCalendarSource: AnyObject {
    func authorization(for type: EKEntityType) -> EKAuthorizationStatus
    func requestFullAccess(to type: EKEntityType) async -> Bool
    func calendars(for type: EKEntityType) async -> [ArisCalendarInfo]
    func events(from: Date, to: Date, calendars: [String]) async -> [ArisCalendarEvent]
    func reminders(from: Date, to: Date, lists: [String]) async -> [ArisCalendarEvent]
}

@MainActor
final class ArisCalendarStore: ObservableObject {
    static let shared = ArisCalendarStore(source: ArisEventKitSource(), defaults: .standard, watchChanges: true)

    @Published private(set) var access: EKAuthorizationStatus
    @Published private(set) var reminderAccess: EKAuthorizationStatus
    @Published private(set) var calendars: [ArisCalendarInfo] = []
    @Published private(set) var selection: ArisCalendarSelection
    /// Bumped whenever the calendars or the selection change; views reload on it.
    @Published private(set) var revision = 0

    private let source: ArisCalendarSource
    private let defaults: UserDefaults
    private var loaded = false
    /// macOS's prompt came back with a yes in this run of the app. The class status this process reads can stay "not
    /// asked yet" after that (the grant went through the reader's own store: the third VM run, B13, where the tab went
    /// back to "Allow" on every reopen until a relaunch), so that read never takes the grant back; a status that says
    /// no always does (ArisCalendarAccess.merged).
    private var grantedByRequest = false
    /// The same for Reminders, whose prompt is answered through ArisReminders' own store: its yes in this run keeps the
    /// due to-dos in the calendar (and the turn's context) while this process still reads "not asked yet".
    private var remindersGrantedByRequest = false
    private var gate = ArisChangeGate()
    private var changes: AnyCancellable?

    init(source: ArisCalendarSource, defaults: UserDefaults, watchChanges: Bool) {
        self.source = source
        self.defaults = defaults
        access = source.authorization(for: .event)
        reminderAccess = source.authorization(for: .reminder)
        selection = ArisCalendarSelection.load(from: defaults)
        if watchChanges {
            changes = NotificationCenter.default.publisher(for: .EKEventStoreChanged)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in MainActor.assumeIsolated { self?.storeChanged() } }
        }
    }

    var eventCalendars: [ArisCalendarInfo] { calendars.filter { !$0.isReminderList } }
    var reminderLists: [ArisCalendarInfo] { calendars.filter(\.isReminderList) }

    var selectedCalendarIDs: Set<String> {
        Set(calendars.map(\.id).filter(selection.contains))
    }

    // MARK: Access

    /// Reads the status; when undecided, asks for full access (the system prompt) and loads on a yes.
    func checkAccess() async {
        refreshAccess()
        if access == .notDetermined {
            let granted = await source.requestFullAccess(to: .event)
            if granted { grantedByRequest = true }
            setAccess(granted ? .fullAccess : .denied)
            log.notice("calendar access asked: \(granted, privacy: .public)")
        }
        refreshAccess(events: false)
        if access == .fullAccess { await reload() }
    }

    /// From a permission button: send a refusal to System Settings, ask a write-only grant for full access, otherwise
    /// check (which prompts when undecided).
    func requestAccess() async {
        switch read(.event) {
        case .denied, .restricted:
            if let pane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                NSWorkspace.shared.open(pane)
            }
        case .writeOnly:
            let granted = await source.requestFullAccess(to: .event)
            if granted { grantedByRequest = true }
            setAccess(granted ? .fullAccess : read(.event))
        default:
            await checkAccess()
        }
        await loadIfAuthorized()
    }

    /// Reloads the calendars when access is already granted. Never prompts.
    func loadIfAuthorized() async {
        refreshAccess()
        if access == .fullAccess { await reload() }
    }

    /// Re-reads the statuses; the published values change (and views redraw) only when a status really changed.
    private func refreshAccess(events: Bool = true) {
        if events { setAccess(read(.event)) }
        let reminders = read(.reminder)
        if reminders != reminderAccess { reminderAccess = reminders }
    }

    /// The class status for events, with this run's grant kept (ArisCalendarAccess.merged).
    private func read(_ type: EKEntityType) -> EKAuthorizationStatus {
        let status = source.authorization(for: type)
        let lapsed = status != .notDetermined && status != .fullAccess
        switch type {
        case .event:
            if lapsed { grantedByRequest = false }
            return ArisCalendarAccess.merged(read: status, grantedByRequest: grantedByRequest)
        case .reminder:
            if lapsed { remindersGrantedByRequest = false }
            return ArisCalendarAccess.merged(read: status, grantedByRequest: remindersGrantedByRequest)
        @unknown default:
            return status
        }
    }

    /// Reminders' prompt came back with a yes in this run (ArisReminders): the due to-dos are read from now on.
    func remindersGranted() async {
        remindersGrantedByRequest = true
        refreshAccess(events: false)
        await loadIfAuthorized()
    }

    private func setAccess(_ status: EKAuthorizationStatus) {
        if status != access { access = status }
    }

    // MARK: Selection

    func isSelected(_ calendar: ArisCalendarInfo) -> Bool { selection.contains(calendar.id) }

    func setSelected(_ calendar: ArisCalendarInfo, _ on: Bool) async {
        selection = selection.setting(calendar.id, on: on, among: Set(calendars.map(\.id)))
        selection.save(to: defaults)
        revision += 1
    }

    // MARK: Events

    /// From the start of today to `days` days later.
    func upcomingEvents(days: Int) async -> [ArisCalendarEvent] {
        let start = Calendar.current.startOfDay(for: Date())
        guard let end = Calendar.current.date(byAdding: .day, value: days, to: start) else { return [] }
        return await events(from: start, to: end)
    }

    /// The selected calendars' events and the selected lists' due reminders, earliest first.
    func events(from start: Date, to end: Date) async -> [ArisCalendarEvent] {
        refreshAccess()
        guard access == .fullAccess else { return [] }
        if !loaded { await reload() }
        let selected = selectedCalendarIDs
        let eventIDs = eventCalendars.map(\.id).filter(selected.contains)
        let listIDs = reminderLists.map(\.id).filter(selected.contains)
        let events = eventIDs.isEmpty ? [] : await source.events(from: start, to: end, calendars: eventIDs)
        let reminders = listIDs.isEmpty || reminderAccess != .fullAccess ? [] : await source.reminders(from: start, to: end, lists: listIDs)
        return ArisCalendarEvent.merged(events, reminders)
    }

    // MARK: Loading

    /// The calendars and lists as they are now, read off the main actor; the views keep the last ones meanwhile.
    private func reload() async {
        var all = access == .fullAccess ? await source.calendars(for: .event) : []
        if reminderAccess == .fullAccess { all += await source.calendars(for: .reminder) }
        calendars = all
        loaded = true
        revision += 1
    }

    private func storeChanged() {
        guard gate.changed() else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: ArisChangeGate.delay)
            guard let self else { return }
            self.gate.reloaded()
            await self.loadIfAuthorized()
        }
    }
}

/// The one answer for calendar access in this run (pure, tested).
enum ArisCalendarAccess {
    /// What the class status reads, except that a yes from macOS's prompt in this run stands while the read still says
    /// "not asked yet": any other status (a no, or access cut to adding only) is taken as it reads.
    static func merged(read: EKAuthorizationStatus, grantedByRequest: Bool) -> EKAuthorizationStatus {
        grantedByRequest && read == .notDetermined ? .fullAccess : read
    }
}
