//
//  ArisRightPanel.swift
//  Aris
//
//  The right side notch: 할 일 (your to-dos and Canvas deadlines) or 캘린더 (a date strip and the chosen day's timetable).
//

import AppKit
import Defaults
import SwiftUI

struct ArisRightPanel: View {
    @ObservedObject private var panels = ArisSidePanels.shared

    var body: some View {
        // The tabs left on in settings.
        let tabs = panels.shownTabs(.right)
        ArisSideTabs(edge: .right, tabs: tabs.map { ($0, $0.name()) }, current: $panels.rightTab)
        ArisTabSwap(index: tabs.firstIndex(of: panels.rightTab) ?? 0) {
            switch panels.rightTab {
            case .calendar: ArisAgendaView()
            default: ArisTodoView()
            }
        }
    }
}

/// The events the 캘린더 tab last read, kept while Aris runs: the tab is made again each time it is picked.
@MainActor
enum ArisAgendaMemory {
    static var events: [ArisCalendarEvent]?
}

/// Boring Notch's scrolling date strip on top (a week back, two weeks ahead), and under it the chosen day as a
/// Google/Notion-style timetable: all-day chips, then hour rows with each event a block in its calendar's colour and
/// a red line at the current time on today. Uses the calendars chosen in settings.
struct ArisAgendaView: View {
    @ObservedObject private var calendar = ArisCalendarStore.shared
    /// The side panels' demo: its sample events, and no EventKit at all.
    @ObservedObject private var demo = ArisSideDemo.shared
    /// Starts from what the tab last showed (ArisAgendaMemory), so coming back to it shows the timetable at once: it
    /// used to start empty behind a spinner on every change of tab (side 3), then pop in.
    @State private var events: [ArisCalendarEvent] = ArisAgendaMemory.events ?? []
    @State private var loading = ArisAgendaMemory.events == nil
    @State private var day = Calendar.current.startOfDay(for: .now)
    @Default(.hideAllDayEvents) private var hideAllDayEvents

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            VStack(alignment: .leading, spacing: 0) {
                if !demo.isOn, calendar.access != .fullAccess {
                    access
                    Spacer(minLength: 0)
                } else if loading {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.vertical, 28)
                    Spacer(minLength: 0)
                } else {
                    ArisCalendarStrip(selection: $day, dots: dots)
                    ArisSideStyle.dayHeading(heading(now: now), first: true)
                        .padding(.horizontal, -7)
                    if !demo.isOn, !calendar.eventCalendars.contains(where: { calendar.selectedCalendarIDs.contains($0.id) }) {
                        ArisSideStyle.empty(ArisUIWords.text("설정에서 표시할 캘린더를 골라 주세요", "Choose the calendars to show in Settings"))
                        Spacer(minLength: 0)
                    } else {
                        // A sample opens nothing and has no menu.
                        ArisDayTimeline(day: day, events: dayEvents, now: now,
                                        onTap: { if !demo.isOn { tap($0, now: now) } }, menu: { demo.isOn ? AnyView(EmptyView()) : AnyView(menu($0)) })
                    }
                }
            }
        }
        .task(id: calendar.revision) { await reload() }
        // Loads what's already allowed (the prompt only comes from the button): at first, and when the demo turns on
        // (its samples) or off (the real calendars again).
        .task(id: demo.isOn) {
            if !demo.isOn { await calendar.loadIfAuthorized() }
            await reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if !demo.isOn { Task { await calendar.loadIfAuthorized() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            day = Calendar.current.startOfDay(for: .now)
            Task { await reload() }
        }
    }

    private var visibleEvents: [ArisCalendarEvent] { events.filter { !hideAllDayEvents || !$0.isAllDay } }

    /// The chosen day's events, all-day ones included.
    private var dayEvents: [ArisCalendarEvent] {
        let start = Calendar.current.startOfDay(for: day)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return [] }
        return visibleEvents.filter { $0.start < end && ($0.end > start || ($0.end == $0.start && $0.start >= start)) }
            .sorted { $0.start < $1.start }
    }

    /// Up to three calendar colours for each day on the strip.
    private var dots: [Date: [Color]] {
        var result: [Date: [Color]] = [:]
        for stripDay in ArisCalendarStrip.days {
            let slots = visibleEvents.map(Self.slot)
            guard ArisAgenda.dots(slots, on: stripDay) > 0 else { continue }
            let start = Calendar.current.startOfDay(for: stripDay)
            guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { continue }
            result[start] = visibleEvents.filter { $0.start < end && $0.end > start }.prefix(3).map { Color(nsColor: $0.calendar.color) }
        }
        return result
    }

    /// "오늘 · 11월 2일 월요일", "내일 · …", or the date alone.
    private func heading(now: Date) -> String {
        let date = ArisAgenda.dayTitle(day, now: .distantPast)
        let relative = ArisAgenda.dayTitle(day, now: now)
        return relative == date ? date : "\(relative) · \(date)"
    }

    private var access: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ArisUIWords.text("캘린더 접근을 허용해 주세요", "Allow access to your calendar")).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.94))
            Text(ArisUIWords.text("일정을 날짜별 시간표로 여기에 보여 줘요.", "Your events show here as a timetable for each day.")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            Button {
                Task { await calendar.requestAccess(); await reload() }
            } label: {
                Text(calendar.access == .denied || calendar.access == .restricted ? ArisUIWords.text("시스템 설정 열기", "Open System Settings") : ArisUIWords.text("허용", "Allow"))
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.95))
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 9, style: .circular).fill(.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ArisSideStyle.pill(RoundedRectangle(cornerRadius: 16, style: .circular)))
        .padding(.top, 6)
    }

    @ViewBuilder private func menu(_ event: ArisCalendarEvent) -> some View {
        Button(Defaults[.calendarOpenIn] == "google" ? ArisUIWords.text("Google 캘린더에서 열기", "Open in Google Calendar") : ArisUIWords.text("캘린더에서 열기", "Open in Calendar")) { openInCalendar(event) }
        if let link = event.meetingLink {
            Button(ArisUIWords.text("회의 참가", "Join the meeting")) { NSWorkspace.shared.open(link.url) }
            Button(ArisUIWords.text("링크 복사", "Copy the link")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link.url.absoluteString, forType: .string)
            }
        }
    }

    /// A meeting that's on or about to start opens its link (when the setting says so); anything else opens in Calendar.
    func tap(_ event: ArisCalendarEvent, now: Date) {
        if Defaults[.joinMeetingOnEventTap], let link = event.meetingLink, ArisAgenda.shouldJoin(Self.slot(event), now: now) {
            NSWorkspace.shared.open(link.url)
        } else {
            openInCalendar(event)
        }
    }

    private func openInCalendar(_ event: ArisCalendarEvent) {
        if Defaults[.calendarOpenIn] == "google" { NSWorkspace.shared.open(ArisAgenda.googleDayURL(event.start)); return }
        if let url = event.calendarAppURL() { NSWorkspace.shared.open(url) }
        else if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") { NSWorkspace.shared.openApplication(at: app, configuration: .init()) }
    }

    private func reload() async {
        defer { loading = false }
        if let samples = demo.samples { events = samples.events; return }
        guard calendar.access == .fullAccess else { events = []; ArisAgendaMemory.events = nil; return }
        let days = ArisCalendarStrip.days
        guard let first = days.first, let last = days.last, let end = Calendar.current.date(byAdding: .day, value: 1, to: last) else { return }
        let result = await calendar.events(from: first, to: end).filter { !$0.kind.isReminder }
        // The demo began while EventKit was asked: its samples stay.
        guard !Task.isCancelled, !demo.isOn else { return }
        events = result
        ArisAgendaMemory.events = result
    }

    static func slot(_ event: ArisCalendarEvent) -> ArisAgendaSlot {
        ArisAgendaSlot(id: event.timelineID, start: event.start, end: event.end, isAllDay: event.isAllDay)
    }
}
