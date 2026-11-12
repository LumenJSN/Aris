//
//  ArisWidgetModel.swift
//  Aris
//
//  The answer card on screen (the owner's pick B): which one the last answer asked for (ArisWidget), and its values,
//  read here on the Mac: the weather from aris-agent's POST /weather (Open-Meteo), a stock from POST /stock (Yahoo's
//  chart), a place and its ETAs from POST /maps (MapKit) with a MKMapSnapshotter still, today's events from EventKit,
//  the to-dos from Reminders, the timer and what's playing from their own models. Nothing the brain wrote reaches a
//  card but the card's name and what it looks up (a place, a symbol: looked up and shown, on any turn, never acted
//  on); one that can't be found gives no card, never another city's weather. The map opens Maps only on a click. A
//  permission card shows only while aris-agent itself says that permission is off, and its button only opens that list
//  in System Settings. The card belongs to its answer: it shows only under that reply, so a new question puts it
//  away and hovering the closed notch brings it back with the parked answer. While it's up the notch stays open
//  (holdWhileShown) until Esc, a click outside or the next question; monitors for those exist only then.
//

import AppKit
import EventKit
import SwiftUI
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "widget")

@MainActor
final class ArisWidgetModel: ObservableObject {
    static let shared = ArisWidgetModel()

    enum Content: Equatable {
        case weather(ArisWeatherCard)
        case calendar([ArisWidgetEvent])
        case todo(ArisTodoCard)
        case timer
        case music
        case stock(ArisStockCard)
        case currency(ArisCurrencyCard)
        /// The map's still comes a moment after its values (nil until then, or when MapKit couldn't make one).
        case map(ArisMapCard, ArisMapTile?)
        /// A permission of aris-agent's that is off now.
        case permission(ArisPermissionPane)
    }

    struct Shown: Equatable {
        let id = UUID()
        /// The answer as the notch shows it; the card shows only under it.
        let reply: String
        let request: ArisWidgetRequest
        /// A turn that saw the screen or outside text: the card shows (its place too), its buttons don't.
        let untrusted: Bool
        /// Nil until the values are read (or when they couldn't be).
        var content: Content?
    }

    @Published private(set) var current: Shown?

    /// Card views on screen now (one per display at most).
    private var onScreen = 0
    private var hold: CheckedContinuation<Void, Never>?
    private var monitors: [Any] = []

    /// A brain's answer arrived: the card it asks for, if any, replaces the last one (`reply`: what the notch shows).
    /// `asked`: the words the turn answered, for the calendar card's day when the block names none.
    func present(answer: String, reply: String, untrusted: Bool, asked: String? = nil) {
        guard let (named, actions) = ArisWidget.presentation(in: answer, untrusted: untrusted),
              let request = ArisCalendarCardDay.resolve(named, asked: asked, now: .now) else {
            if current != nil { current = nil }
            return
        }
        let shown = Shown(reply: reply, request: request, untrusted: !actions, content: Self.immediate(request.kind))
        current = shown
        log.notice("card: \(request.kind.rawValue, privacy: .public)")
        guard shown.content == nil else { return }
        Task {
            let content = await Self.load(request)
            // Another answer came meanwhile.
            guard current?.id == shown.id else { return }
            // Once per kind (a weather card with no home location is normal, not news every turn).
            if content == nil, Self.saidEmpty.insert(request.kind.rawValue).inserted { log.notice("card: no values for \(request.kind.rawValue, privacy: .public)") }
            current?.content = content
            // Kept with the turn in the history, so it can be shown again as it was (ArisHistoryRestore).
            if let content, let card = Self.historyCard(request, content) { ArisController.shared.keepCard(card, forReply: reply) }
            // The map's still follows its values: the label shows at once.
            guard case .map(let card, nil)? = content else { return }
            let tile = await ArisMapSnapshot.tile(for: card)
            guard let tile, current?.id == shown.id else { return }
            current?.content = .map(card, tile)
        }
    }

    /// A card whose values are already read (a currency question answered here, with no brain): shown under `reply`.
    func show(_ content: Content, request: ArisWidgetRequest, reply: String) {
        current = Shown(reply: reply, request: request, untrusted: false, content: content)
        log.notice("card: \(request.kind.rawValue, privacy: .public) (local)")
    }

    /// A past turn is shown again (ArisController.resume): its card as it was then, or none. History, so its buttons
    /// are off (as on a turn that saw outside text), and nothing is read again from the Mac for it.
    func restore(_ card: ArisHistoryCard?, reply: String) {
        guard let card, let request = card.request else {
            if current != nil { current = nil }
            return
        }
        current = Shown(reply: reply, request: request, untrusted: true, content: Self.content(card.values))
    }

    /// A card's values as the history keeps them. The timer's and the music's cards show what is on now, and a
    /// permission card what is off now: not something a past turn can be shown with again.
    static func historyCard(_ request: ArisWidgetRequest, _ content: Content) -> ArisHistoryCard? {
        switch content {
        case .weather(let card): ArisHistoryCard(request: request, values: .weather(card))
        case .calendar(let events): ArisHistoryCard(request: request, values: .calendar(events))
        case .todo(let card): ArisHistoryCard(request: request, values: .todo(card))
        case .stock(let card): ArisHistoryCard(request: request, values: .stock(card))
        case .map(let card, _): ArisHistoryCard(request: request, values: .map(card))
        case .timer, .music, .permission: nil
        // A currency card is a quote of that moment; a restored turn shows its words (the number is in them).
        case .currency: nil
        }
    }

    private static func content(_ values: ArisHistoryCard.Values) -> Content {
        switch values {
        case .weather(let card): .weather(card)
        case .calendar(let events): .calendar(events)
        case .todo(let card): .todo(card)
        case .stock(let card): .stock(card)
        case .map(let card): .map(card, nil)
        }
    }

    /// Something on the card's list was just undone (the receipt's 되돌리기): the list is read again, now and once more a
    /// moment later (Reminders and Calendar tell another process of a change a beat after it is made).
    func undoHappened() {
        guard let shown = current, shown.request.kind.listsWhatUndoChanges else { return }
        Task {
            for wait in [Duration.zero, Self.settleAfterUndo] {
                try? await Task.sleep(for: wait)
                let content = await Self.load(shown.request)
                guard current?.id == shown.id else { return }
                if let content, content != current?.content { current?.content = content }
            }
        }
    }

    /// How long after an undo the card's list is read the second time.
    private static let settleAfterUndo: Duration = .milliseconds(1500)

    /// The card under `reply`, once its values are in.
    func card(for reply: String) -> Shown? {
        guard let current, current.reply == reply, current.content != nil else { return nil }
        return current
    }

    /// Whether `reply` is a card's line (shown as plain text above it, even before the values arrive).
    func isCardLine(_ reply: String) -> Bool { current?.reply == reply }

    // MARK: - Loading

    private static func immediate(_ kind: ArisWidgetKind) -> Content? {
        switch kind {
        case .timer: return .timer
        case .music: return .music
        case .weather, .calendar, .todo, .stock, .map, .permission, .currency: return nil
        }
    }

    /// The kinds already logged as having no values this run.
    private static var saidEmpty: Set<String> = []

    private static func load(_ request: ArisWidgetRequest) async -> Content? {
        switch request.kind {
        case .weather:
            return await ArisAgentClient.weather(place: request.place).flatMap { ArisWeatherCard.parse($0) }.map(Content.weather)
        case .calendar:
            guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return nil }
            // The day the answer is about, its calendar events only: never a due or ticked to-do as an "All day" row.
            let start = request.day.flatMap { ArisCalendarCardDay.date($0) } ?? Calendar.current.startOfDay(for: .now)
            guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return nil }
            return .calendar(ArisCalendarCardDay.rows(await ArisCalendarStore.shared.events(from: start, to: end)))
        case .todo:
            let reminders = ArisReminders.shared
            reminders.start()
            await reminders.reload()
            guard await reminders.accessForRequest() else { return nil }
            return .todo(ArisTodoCard.make(reminders.items, now: .now))
        case .timer: return .timer
        case .music: return .music
        case .stock:
            guard let symbol = request.symbol else { return nil }
            return await ArisAgentClient.cardValues(path: "stock", body: ["symbol": symbol]).flatMap { ArisStockCard.parse($0) }.map(Content.stock)
        case .currency:
            guard let ask = request.symbol else { return nil }
            return await ArisAgentClient.cardValues(path: "currency", body: ["ask": ask], timeout: 25).flatMap { ArisCurrencyCard.parse($0) }.map(Content.currency)
        case .map:
            guard let place = request.place else { return nil }
            let body = ["place": place].merging(request.from.map { ["from": $0] } ?? [:]) { $1 }
            guard let card = await ArisAgentClient.cardValues(path: "maps", body: body, timeout: 45).flatMap(ArisMapCard.parse) else { return nil }
            return .map(card, nil)
        case .permission:
            // Only while aris-agent itself says it is off: an answer's word alone never puts the card up.
            guard let pane = request.pane, await ArisAgentClient.agentHas(pane) == false else { return nil }
            return .permission(pane)
        }
    }

    /// The permission card's button: that list in System Settings, on a click (never on its own).
    func openSettings(_ pane: ArisPermissionPane) {
        guard let url = URL(string: pane.settingsURL) else { return }
        log.notice("card: opening System Settings (\(pane.rawValue, privacy: .public))")
        NSWorkspace.shared.open(url)
        // Once it is on, the same request is asked again (ArisFixReturn).
        ArisFixModel.shared.openedElsewhere(.pane(pane == .disk ? .disk : .screen))
        dismiss()
    }

    /// The way there in Maps, on a click on the map card (never on its own).
    func openMaps(_ card: ArisMapCard) {
        guard let url = card.mapsURL else { return }
        log.notice("card: opening Maps")
        NSWorkspace.shared.open(url)
        dismiss()
    }

    // MARK: - Holding the notch open

    func appeared() { onScreen += 1 }

    func disappeared() {
        onScreen = max(0, onScreen - 1)
        if onScreen == 0 { release() }
    }

    /// Returns once the card is put away: Esc, a click outside the notch, the card leaving the screen (the next
    /// question, 닫기), or the waiting task being cancelled. At once when no card is on screen.
    func holdWhileShown() async {
        guard onScreen > 0, hold == nil else { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                hold = continuation
                watch()
            }
        } onCancel: {
            Task { @MainActor in ArisWidgetModel.shared.release() }
        }
    }

    /// Esc or a click outside: the notch may close (the card stays with the parked answer for a hover).
    func dismiss() { release() }

    private func release() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        hold?.resume()
        hold = nil
    }

    /// Clicks in other apps' windows and Esc anywhere (a global monitor sees keys only with Accessibility, so Esc in
    /// Aris's own window is watched too). Watching only: no event is taken.
    private func watch() {
        let click = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            MainActor.assumeIsolated { ArisWidgetModel.shared.dismiss() }
        }
        let key = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == Self.escape else { return }
            MainActor.assumeIsolated { ArisWidgetModel.shared.dismiss() }
        }
        let localKey = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Esc in the currency card's amount field only leaves the field (ArisCurrencyLiveModel); Esc in a request's
            // editor only throws the edit away (ArisPromptEdit). Otherwise Esc puts the card away.
            if event.keyCode == Self.escape {
                MainActor.assumeIsolated {
                    if !ArisCurrencyLiveModel.editing && !ArisPromptEdit.escIsEditors(editing: ArisPromptEditing.shared.active) {
                        ArisWidgetModel.shared.dismiss()
                    }
                }
            }
            return event
        }
        monitors = [click, key, localKey].compactMap { $0 }
    }

    private static let escape: UInt16 = 53
}

extension ArisAgentClient {
    /// Whether aris-agent has the permission behind `pane` now; nil when it didn't answer.
    static func agentHas(_ pane: ArisPermissionPane) async -> Bool? {
        switch pane {
        case .disk: return await agentHasDiskAccess()
        case .screen: return await agentHasScreenAccess()
        }
    }

    /// The weather card's values (aris-tools weather --json through aris-agent); nil when it couldn't be read.
    static func weather(place: String?) async -> [String: Any]? {
        await cardValues(path: "weather", body: place.map { ["place": $0] } ?? [:])
    }

    /// An answer card's values from aris-agent's app-only POST /<path> (aris-tools … --json); nil when they couldn't
    /// be read. Only a JSON object comes back; the card's parse reads it as outside data.
    static func cardValues(path: String, body: [String: String], timeout: TimeInterval = 20) async -> [String: Any]? {
        guard let token = ClaudeHookToken.load(), let url = URL(string: "http://127.0.0.1:23351/" + path) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        request.httpBody = try? JSONSerialization.data(withJSONObject: identified(body))
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

// MARK: - The slot under the answer

/// The card under the spoken line, fed live by the timer and Now Playing where it ticks.
struct ArisWidgetSlot: View {
    let shown: ArisWidgetModel.Shown

    var body: some View {
        content
            .modifier(ArisWidgetPresent())
            .id(shown.id)
    }

    @ViewBuilder private var content: some View {
        switch shown.content {
        case .weather(let card): ArisWeatherCardView(card: card).modifier(ArisWidgetOnScreen())
        case .calendar(let events): ArisCalendarCardView(events: events, day: shown.request.day.flatMap { ArisCalendarCardDay.date($0) }).modifier(ArisWidgetOnScreen())
        case .todo(let card): ArisTodoCardView(card: card).modifier(ArisWidgetOnScreen())
        case .timer: ArisTimerSlot(untrusted: shown.untrusted)
        case .music: ArisMusicSlot(untrusted: shown.untrusted)
        case .stock(let card): ArisStockCardView(card: card).modifier(ArisWidgetOnScreen())
        case .currency(let card): ArisCurrencySlot(card: card, untrusted: shown.untrusted).modifier(ArisWidgetOnScreen())
        // Opening Maps waits for a click on every turn, an untrusted one too (the place is only shown).
        case .map(let card, let tile):
            ArisMapCardView(card: card, tile: tile, open: card.mapsURL == nil ? nil : { ArisWidgetModel.shared.openMaps(card) })
                .modifier(ArisWidgetOnScreen())
        // The button only opens a list in System Settings, so it is there on every turn (as the map's click is).
        case .permission(let pane):
            ArisPermissionOffCardView(pane: pane, open: { ArisWidgetModel.shared.openSettings(pane) }).modifier(ArisWidgetOnScreen())
        case nil: EmptyView()
        }
    }
}

private struct ArisTimerSlot: View {
    let untrusted: Bool
    @ObservedObject private var timer = ArisTimerModel.shared

    var body: some View {
        if let state = timer.state {
            ArisTimerCardView(state: state, actions: untrusted ? nil : ArisWidgetActions(
                timerToggle: { timer.togglePause() }, timerAdd: { timer.add(300) }, timerStop: { timer.cancel() }))
                .modifier(ArisWidgetOnScreen())
        }
    }
}

private struct ArisMusicSlot: View {
    let untrusted: Bool
    @ObservedObject private var music = ArisNowPlaying.shared

    var body: some View {
        if !music.songTitle.isEmpty {
            ArisMusicCardView(
                state: ArisMusicCardState(title: music.songTitle, artist: music.artistName, album: music.album, playing: music.isPlaying,
                                          duration: music.songDuration, elapsed: music.elapsedTime, at: music.timestampDate,
                                          rate: music.playbackRate, source: ArisMusicCardState.source(bundle: music.bundleIdentifier)),
                art: music.usingAppIconForArtwork ? nil : music.albumArt,
                actions: untrusted ? nil : ArisWidgetActions(
                    musicPrevious: { music.previousTrack() }, musicToggle: { music.togglePlay() }, musicNext: { music.nextTrack() }))
            .modifier(ArisWidgetOnScreen())
        }
    }
}

/// Counts a drawn card for the hold: a timer that ended or music that stopped leaves nothing drawn, so nothing holds
/// the notch open.
private struct ArisWidgetOnScreen: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { ArisWidgetModel.shared.appeared() }
            .onDisappear { ArisWidgetModel.shared.disappeared() }
    }
}
