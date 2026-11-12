//
//  ArisDayTimeline.swift
//  Aris
//
//  One day as Google or Notion Calendar draws it, in the side notch: all-day events as chips on top, then the
//  hours down a scrolling column with each timed event a block in its calendar's colour (overlapping ones side by
//  side), and a red line at the current time on today. It opens scrolled to just before now (today), the day's
//  first event, or 8 a.m.
//

import SwiftUI

struct ArisDayTimeline: View {
    let day: Date
    let events: [ArisCalendarEvent]
    let now: Date
    let onTap: (ArisCalendarEvent) -> Void
    let menu: (ArisCalendarEvent) -> AnyView

    static let hourHeight: CGFloat = 44
    private static let gutter: CGFloat = 46
    private static let nowRed = Color(red: 1, green: 95 / 255, blue: 87 / 255)

    @State private var scrolledOnce = false
    @State private var topHour: Int?

    private var calendar: Calendar { .current }
    private var isToday: Bool { calendar.isDate(day, inSameDayAs: now) }
    private var allDay: [ArisCalendarEvent] { events.filter(\.isAllDay) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !allDay.isEmpty {
                ArisFlow(spacing: 5) {
                    ForEach(allDay, id: \.timelineID) { event in
                        chip(event).contextMenu { menu(event) }
                    }
                }
                .padding(EdgeInsets(top: 0, leading: 12, bottom: 6, trailing: 12))
            }
            ScrollView(.vertical, showsIndicators: false) {
                grid.padding(.vertical, 8)
            }
            // The hour rows are scroll targets: the view opens with the right hour at the top, and a new day glides.
            .scrollPosition(id: $topHour, anchor: .top)
            .task(id: day) {
                let target = startHour
                if scrolledOnce { withAnimation(ArisSideStyle.cssEase(0.28)) { topHour = target } } else { topHour = target }
                scrolledOnce = true
            }
            .mask {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.03),
                                       .init(color: .black, location: 0.92), .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
    }

    // MARK: - The hours

    private var grid: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                hourLine(hour).frame(height: Self.hourHeight, alignment: .top).id(hour)
            }
            hourLine(24)
        }
        .scrollTargetLayout()
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                let width = geometry.size.width - Self.gutter - 4
                ZStack(alignment: .topLeading) {
                    ForEach(blocks, id: \.event.timelineID) { block in
                        let columnWidth = width / CGFloat(block.of)
                        ArisTimelineBlock(event: block.event, height: block.height, past: isToday && block.event.end <= now,
                                          live: block.event.start <= now && now < block.event.end, onTap: { onTap(block.event) })
                            .contextMenu { menu(block.event) }
                            .frame(width: max(12, columnWidth - 2), height: block.height)
                            .offset(x: Self.gutter + CGFloat(block.column) * columnWidth, y: block.y)
                    }
                    if isToday { nowLine(width: geometry.size.width).offset(y: minutes(now) * Self.hourHeight / 60 - 4) }
                }
            }
        }
    }

    private func hourLine(_ hour: Int) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text(hour == 0 || hour == 24 ? "" : Self.hourLabel(hour))
                .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.42))
                .frame(width: Self.gutter - 6, alignment: .trailing)
            Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
        }
        .frame(height: 1)
    }

    private func nowLine(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Spacer().frame(width: Self.gutter - 4)
            Circle().fill(Self.nowRed).frame(width: 7, height: 7)
            Rectangle().fill(Self.nowRed).frame(height: 1.5)
        }
        .frame(width: width, height: 8)
        .allowsHitTesting(false)
    }

    private struct Block {
        let event: ArisCalendarEvent
        let y: CGFloat
        let height: CGFloat
        let column: Int
        let of: Int
    }

    private var blocks: [Block] {
        let placed = events.compactMap { event -> (event: ArisCalendarEvent, start: Double, end: Double)? in
            ArisAgenda.dayMinutes(ArisAgendaView.slot(event), on: day).map { (event, $0.start, $0.end) }
        }
        // Short events still take 20 minutes of room, so their text fits and they lay out like Google's.
        let layout = ArisAgenda.columns(placed.map { (id: $0.event.timelineID, start: $0.start, end: max($0.end, $0.start + 20)) })
        return placed.map { item in
            let slot = layout[item.event.timelineID] ?? (0, 1)
            let y = CGFloat(item.start) * Self.hourHeight / 60
            let height = max(18, CGFloat(item.end - item.start) * Self.hourHeight / 60 - 2)
            return Block(event: item.event, y: y + 1, height: height, column: slot.column, of: slot.of)
        }
    }

    // MARK: - All-day

    private func chip(_ event: ArisCalendarEvent) -> some View {
        HStack(spacing: 5) {
            Circle().fill(Color(nsColor: event.calendar.color)).frame(width: 6, height: 6)
            Text(event.title).font(.system(size: 11)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(.white.opacity(0.06)))
        .onTapGesture { onTap(event) }
    }

    // MARK: - Scrolling

    /// The hour at the top when the day opens: just before now on today, the day's first event, or 8 a.m.
    private var startHour: Int {
        if isToday { return max(0, Int(minutes(now) / 60) - 1) }
        if let first = events.compactMap({ ArisAgenda.dayMinutes(ArisAgendaView.slot($0), on: day)?.start }).min() {
            return max(0, Int(first / 60) - (first.truncatingRemainder(dividingBy: 60) < 15 ? 1 : 0))
        }
        return 8
    }

    private func minutes(_ date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(calendar.startOfDay(for: day)) / 60)
    }

    /// "오전 9시", "오후 12시", "오후 3시".
    static func hourLabel(_ hour: Int, english: Bool = ArisUIWords.english, locale: Locale? = nil) -> String {
        if english {
            // "9 AM", "12 PM", or "09" where the locale's clock has 24 hours.
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
            let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: hour % 24)) ?? Date(timeIntervalSince1970: 0)
            return ArisUIDates.string(date, korean: "", template: "j", english: true, calendar: calendar, locale: locale)
        }
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(hour < 12 ? "오전" : "오후") \(h12)시"
    }
}

/// One timed event on the timetable: its calendar's colour as a tinted block with a solid edge, the title, and the
/// time when there's room; brighter while it's on, faded once today's has passed.
private struct ArisTimelineBlock: View {
    let event: ArisCalendarEvent
    let height: CGFloat
    let past: Bool
    let live: Bool
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        let color = Color(nsColor: event.calendar.color)
        HStack(alignment: .top, spacing: 5) {
            RoundedRectangle(cornerRadius: 1.5, style: .circular).fill(color).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .top, spacing: 3) {
                    Text(event.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.94))
                        .lineLimit(height >= 46 ? 2 : 1)
                    Spacer(minLength: 0)
                    if event.meetingLink != nil {
                        Image(systemName: "video.fill").font(.system(size: 9)).foregroundStyle(.white.opacity(0.7)).padding(.top, 2)
                    }
                }
                if height >= 32 {
                    Text(ArisAgenda.timeRange(event.start, event.end) + (event.location.flatMap { $0.isEmpty ? nil : " · \($0)" } ?? ""))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.64))
                        .lineLimit(1)
                }
            }
            .padding(.top, height >= 24 ? 3 : 1)
        }
        .padding(EdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 5))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 6, style: .circular).fill(color.opacity(live ? 0.36 : hovering ? 0.3 : 0.22)))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .circular))
        .opacity(past ? 0.5 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .circular))
        .onTapGesture(perform: onTap)
        .onHover { hovering = $0 }
        .animation(ArisSideStyle.cssEase(0.14), value: hovering)
    }
}

extension ArisCalendarEvent {
    /// Recurrences share an EventKit item identifier; each occurrence needs its own view identity.
    var timelineID: String { "\(id)|\(start.timeIntervalSinceReferenceDate)" }
}
