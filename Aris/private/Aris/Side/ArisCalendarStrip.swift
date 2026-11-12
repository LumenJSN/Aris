//
//  ArisCalendarStrip.swift
//  Aris
//
//  The calendar tab's date strip: Boring Notch's day wheel (a week back, two weeks ahead, the chosen day in the
//  middle, the scroll wheel or a sideways swipe stepping a day with a tap of the trackpad), drawn in the side notch's
//  language. Today wears a faint disc, the chosen day the solid white one the lock uses, and dots under a day are
//  its calendars' colours. A plain row slid into place (ArisStripLayout), not a ScrollView: the ScrollView's position
//  never reached the side panel, so it opened off centre and a day's button never got the click (QA BUG-57).
//

import AppKit
import SwiftUI

struct ArisCalendarStrip: View {
    @Binding var selection: Date
    /// Up to three dot colours per day (start of day → colours).
    let dots: [Date: [Color]]

    static let past = 7
    static let future = 14
    private static let cell: CGFloat = 30
    private static let ink = Color(red: 18 / 255, green: 20 / 255, blue: 27 / 255)

    @State private var hovering = false
    @State private var scrollMonitor: Any?
    @State private var wheel: CGFloat = 0

    private var calendar: Calendar { .current }
    private var today: Date { calendar.startOfDay(for: .now) }

    static var days: [Date] {
        let today = Calendar.current.startOfDay(for: .now)
        return (-past...future).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(Array(Self.days.enumerated()), id: \.offset) { _, day in cell(day) }
            }
            .fixedSize()
            .offset(x: ArisStripLayout.offset(width: geometry.size.width, index: index(of: selection), cell: Self.cell))
            .animation(ArisSideStyle.cssEase(0.28), value: selection)
            .frame(width: geometry.size.width, alignment: .leading)
            .clipped()
            .contentShape(Rectangle())
        }
        .frame(height: 54)
        .mask {
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.1),
                                   .init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
        }
        .onContinuousHover { phase in
            if case .active = phase { hovering = true } else { hovering = false }
        }
        .onAppear(perform: watchWheel)
        .onDisappear {
            if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
            scrollMonitor = nil
        }
    }

    private func cell(_ day: Date) -> some View {
        let chosen = calendar.isDate(day, inSameDayAs: selection)
        let isToday = calendar.isDate(day, inSameDayAs: today)
        return Button {
            guard !chosen else { return }
            withAnimation(ArisSideStyle.cssEase(0.28)) { selection = day }
            tap()
        } label: {
            VStack(spacing: 3) {
                Text(Self.weekday(day))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(chosen ? 0.9 : 0.42))
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(chosen ? Self.ink.opacity(0.92) : .white.opacity(isToday ? 1 : 0.94))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(.white.opacity(chosen ? 0.92 : isToday ? 0.14 : 0)))
                HStack(spacing: 2) {
                    ForEach(Array((dots[calendar.startOfDay(for: day)] ?? []).prefix(3).enumerated()), id: \.offset) { _, color in
                        Circle().fill(color).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(width: Self.cell, height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(ArisStripPress())
        .animation(ArisSideStyle.cssEase(0.14), value: chosen)
    }

    private func index(of day: Date) -> Int {
        let offset = calendar.dateComponents([.day], from: Self.days.first ?? today, to: calendar.startOfDay(for: day)).day ?? Self.past
        return min(max(0, offset), Self.days.count - 1)
    }

    /// As Boring Notch's wheel: while the pointer is on the strip, the scroll wheel or a sideways swipe steps a day.
    private func watchWheel() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard hovering else { return event }
            let (pending, step) = ArisStripLayout.scrolled(pending: wheel, dx: event.scrollingDeltaX, dy: event.scrollingDeltaY,
                                                           precise: event.hasPreciseScrollingDeltas)
            wheel = pending
            guard let step else { return nil }
            let next = ArisStripLayout.stepped(index(of: selection), by: step, count: Self.days.count)
            guard next != index(of: selection) else { return nil }
            withAnimation(ArisSideStyle.cssEase(0.28)) { selection = Self.days[next] }
            tap()
            return nil
        }
    }

    private func tap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// "월", or "Mon" in English.
    private static func weekday(_ day: Date) -> String {
        ArisUIDates.string(day, korean: "E", template: "E")
    }
}

/// The press: scale 0.94 over 120 ms, no dimming.
private struct ArisStripPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(ArisSideStyle.cssEase(0.12), value: configuration.isPressed)
    }
}
