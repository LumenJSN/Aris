//
//  ArisWidgetCards.swift
//  Aris
//
//  The five answer cards of the owner's pick B (mockups/widgets.html): weather (now and the next hours), 오늘 일정, the
//  timer, what's playing and 할 일. Each takes plain values (ArisWidget) and draws them as Text(verbatim:), never as
//  markup. Live cards tick at 1 Hz (a minute for the calendar) only while they're on screen and only while something
//  moves; nothing on them blinks or pulses. Buttons show only when `actions` are given (never on an untrusted turn).
//

import SwiftUI

/// The cards' tokens, from mockups/widgets.html.
enum ArisWidgetStyle {
    static let ink95 = Color.white.opacity(0.95)
    static let ink92 = Color.white.opacity(0.92)
    static let ink72 = Color.white.opacity(0.72)
    static let ink50 = Color.white.opacity(0.5)
    static let ink42 = Color.white.opacity(0.42)
    static let hairline = Color.white.opacity(0.08)
    static let fill = Color.white.opacity(0.06)
    static let track = Color.white.opacity(0.12)
    static let mark = Color.white.opacity(0.85)
    static let accent = Color(red: 57 / 255, green: 135 / 255, blue: 229 / 255)
    static let good = Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)
    static let warn = Color(red: 240 / 255, green: 185 / 255, blue: 90 / 255).opacity(0.95)
    static let dotFill = Color(red: 42 / 255, green: 43 / 255, blue: 47 / 255)
    /// The generic card: radius 26, padding 16 / 18.
    static var radius: CGFloat { ArisSiriLookNow.on ? CGFloat(ArisSiriLook.Card.radius) : 26 }
    /// The weather card's corners: 28, Siri's 32 in the siri look.
    static var weatherRadius: CGFloat { ArisSiriLookNow.on ? CGFloat(ArisSiriLook.Card.radius) : 28 }
    static let padding = EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)
    /// The card present: opacity + scale .965 from the top on the opening clock (280 ms, 0.2 0.8 0.2 1).
    static let present = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.28)
    /// The fade-in: 0.3 s ease-out, 4 points up.
    static let fadeIn = Animation.easeOut(duration: 0.3)
}

/// Things a card's buttons do; nil hides the button row (an untrusted turn's card never acts).
struct ArisWidgetActions {
    var timerToggle: () -> Void = {}
    var timerAdd: () -> Void = {}
    var timerStop: () -> Void = {}
    var musicPrevious: () -> Void = {}
    var musicToggle: () -> Void = {}
    var musicNext: () -> Void = {}
}

// MARK: - Shared pieces

/// The spoken line above the card (`.line`: 15 pt on a 1.5 line, padding 0 4, ink .97), as plain text.
struct ArisWidgetLine: View {
    let text: String

    /// The line's inset from the turn's edge.
    static let inset: CGFloat = 4

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 15))
            .lineSpacing(4.5)
            .foregroundStyle(.white.opacity(0.97))
            .fixedSize(horizontal: false, vertical: true)
            // Half the 1.5 line's leading above and below, as CSS lays a line box.
            .padding(.vertical, 2.25)
            .padding(.horizontal, Self.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }
}

/// The card's header (`.ch`): title 14.5 / 600, trailing 12 at .42, on one baseline, 10 above the content.
private struct ArisWidgetHeader: View {
    let title: String
    let trailing: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(verbatim: title).font(.system(size: 14.5, weight: .semibold)).tracking(-0.145).foregroundStyle(ArisWidgetStyle.ink95)
            Spacer(minLength: 0)
            Text(verbatim: trailing).font(.system(size: 12).monospacedDigit()).foregroundStyle(ArisWidgetStyle.ink42).lineLimit(1).arisTextBacking()
        }
        .padding(.bottom, 10)
    }
}

private extension View {
    /// At least the mockup's line box (Korean text sets a taller line in the browser than SwiftUI's default).
    func arisLineBox(_ height: CGFloat) -> some View { frame(minHeight: height, alignment: .leading) }

    /// The generic card surface (`.card`).
    func arisWidgetCard() -> some View {
        padding(ArisWidgetStyle.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: ArisWidgetStyle.radius, style: .continuous).fill(ArisWidgetStyle.fill))
    }
}

/// `.pb`: 26 high, radius 8, 12 / 600, a faint raised fill; pressed, 97%.
private struct ArisWidgetPillButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold)).tracking(0.12)
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.10), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 0.8))
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

// MARK: - Weather

/// `.wx`: radius 28, padding 18, the condition gradient (day or night), an inset top highlight of .16.
struct ArisWeatherCardView: View {
    let card: ArisWeatherCard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "location.fill").font(.system(size: 9, weight: .semibold))
                        Text(verbatim: card.place).font(.system(size: 12.5, weight: .semibold)).tracking(-0.125).lineLimit(1)
                    }
                    // line-height 1: a 38-point box.
                    Text(verbatim: "\(card.temp)°").font(.system(size: 38, weight: .light)).tracking(-1.14).frame(height: 38)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 1) {
                    ArisWeatherIcon(code: card.code, day: card.day).font(.system(size: 17)).frame(height: 19).padding(.bottom, 3)
                    Text(verbatim: ArisWeatherCard.condition(card.code)).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.74))
                    if let range = card.range {
                        Text(verbatim: range).font(.system(size: 10.5, weight: .medium).monospacedDigit()).foregroundStyle(.white.opacity(0.58))
                    }
                }
            }
            if card.hours.count > 1 {
                HStack(spacing: 0) {
                    ForEach(Array(card.hours.enumerated()), id: \.offset) { _, hour in
                        VStack(spacing: 0) {
                            Text(verbatim: hour.label).font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color(red: 188 / 255, green: 227 / 255, blue: 1)).lineLimit(1)
                            ArisWeatherIcon(code: hour.code, day: hour.day).font(.system(size: 17)).frame(height: 20).padding(.top, 6).padding(.bottom, 4)
                            Text(verbatim: "\(hour.temp)°").font(.system(size: 13, weight: .semibold).monospacedDigit())
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 10)
                .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.22)).frame(height: 1) }
                .padding(.top, 14)
            }
        }
        .foregroundStyle(.white.opacity(0.96))
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: ArisWidgetStyle.weatherRadius, style: .continuous).fill(Self.gradient(code: card.code, day: card.day)))
        .overlay {
            RoundedRectangle(cornerRadius: ArisWidgetStyle.weatherRadius, style: .continuous).inset(by: 0.5)
                .stroke(LinearGradient(stops: [.init(color: .white.opacity(0.16), location: 0), .init(color: .clear, location: 0.03)],
                                       startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
    }

    /// The condition's gradient: four stops, top to bottom.
    static func gradient(code: Int, day: Bool) -> LinearGradient {
        let hex: [UInt32]
        switch (ArisWeatherCard.sky(code), day) {
        case (.clear, true): hex = [0x016dfd, 0x0289fe, 0x01b0fe, 0x02ccff]
        case (.clear, false): hex = [0x0a1b3d, 0x0f2a57, 0x16386f, 0x1e4c8f]
        case (.partly, true): hex = [0x1675e0, 0x2d8fe8, 0x54acee, 0x7cc6f3]
        case (.partly, false): hex = [0x1b2f52, 0x1a3556, 0x244468, 0x34597f]
        case (.cloudy, true): hex = [0x4c6075, 0x5a7086, 0x6e8499, 0x8298ac]
        case (.cloudy, false): hex = [0x23272e, 0x262c34, 0x2c333c, 0x353d47]
        case (.fog, true): hex = [0x5e646c, 0x6a7078, 0x777e86, 0x888f98]
        case (.fog, false): hex = [0x23262c, 0x282c32, 0x2e323a, 0x363b43]
        case (.rain, true): hex = [0x2c4a63, 0x355673, 0x426480, 0x54788f]
        case (.rain, false): hex = [0x16222e, 0x1a2835, 0x20303e, 0x283a4a]
        case (.snow, true): hex = [0x5a7488, 0x6a8499, 0x7e97ab, 0x94abbd]
        case (.snow, false): hex = [0x2a3641, 0x30404c, 0x384a58, 0x425567]
        case (.thunder, true): hex = [0x3c3f5a, 0x353851, 0x2e3146, 0x45496b]
        case (.thunder, false): hex = [0x262838, 0x222433, 0x1d1f2c, 0x34374e]
        }
        let colors = hex.map { Color(red: Double($0 >> 16 & 0xff) / 255, green: Double($0 >> 8 & 0xff) / 255, blue: Double($0 & 0xff) / 255) }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
}

/// The sky as an SF Symbol in its own colours (the sun yellow, clouds white).
private struct ArisWeatherIcon: View {
    let code: Int
    let day: Bool

    var body: some View {
        Image(systemName: symbol).symbolRenderingMode(.multicolor)
    }

    private var symbol: String {
        switch ArisWeatherCard.sky(code) {
        case .clear: return day ? "sun.max.fill" : "moon.fill"
        case .partly: return day ? "cloud.sun.fill" : "cloud.moon.fill"
        case .cloudy: return "cloud.fill"
        case .fog: return "cloud.fog.fill"
        case .rain: return "cloud.rain.fill"
        case .snow: return "cloud.snow.fill"
        case .thunder: return "cloud.bolt.rain.fill"
        }
    }
}

// MARK: - Today's calendar

/// 오늘 일정, kept current once a minute (the "25분 뒤" chip) while it's on screen.
struct ArisCalendarCardView: View {
    let events: [ArisWidgetEvent]
    /// The day the answer is about (ArisCalendarCardDay); nil is today.
    var day: Date? = nil
    /// A fixed moment, for the renders; nil follows the clock.
    var now: Date?

    var body: some View {
        if let now {
            ArisCalendarCardFace(card: .make(events, now: now, day: day))
        } else {
            TimelineView(.everyMinute) { context in ArisCalendarCardFace(card: .make(events, now: context.date, day: day)) }
        }
    }
}

private struct ArisCalendarCardFace: View {
    let card: ArisCalendarCard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ArisWidgetHeader(title: card.title, trailing: card.trailing)
            if card.rows.isEmpty {
                Text(verbatim: card.empty).font(.system(size: 13.5)).foregroundStyle(ArisWidgetStyle.ink50).padding(.vertical, 7)
            }
            ForEach(Array(card.rows.enumerated()), id: \.offset) { index, row in
                ArisScheduleRow(row: row, first: index == 0, last: index == card.rows.count - 1)
            }
            if card.more > 0 {
                Text(verbatim: ArisUIWords.text("+\(card.more)개 더", "+\(card.more) more")).font(.system(size: 11.5)).foregroundStyle(ArisWidgetStyle.ink50).arisTextBacking()
                    .padding(.leading, 17 + 66).padding(.top, 4)
            }
        }
        .arisWidgetCard()
    }
}

/// `.ev`: a 17-point rail, a 66-point time column, the title and place, the chip; padding 7 0. The rail's line runs
/// dot to dot; the next one's dot is the accent with a 3-point ring, still, never pulsing.
private struct ArisScheduleRow: View {
    let row: ArisCalendarCard.Row
    let first: Bool
    let last: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Color.clear.frame(width: 17)
            Text(verbatim: row.time).font(.system(size: 13.5).monospacedDigit())
                .foregroundStyle(row.state == .past ? ArisWidgetStyle.ink50 : ArisWidgetStyle.ink72)
                .frame(width: 66, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.title).font(.system(size: 13.5)).lineSpacing(1.5)
                    .foregroundStyle(row.state == .past ? ArisWidgetStyle.ink50 : ArisWidgetStyle.ink92)
                    .arisLineBox(18.2)
                if let sub = row.sub {
                    Text(verbatim: sub).font(.system(size: 11.5)).foregroundStyle(ArisWidgetStyle.ink50).lineLimit(1).arisLineBox(14.5).arisTextBacking()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let chip = row.chip {
                Text(verbatim: chip).font(.system(size: 11, weight: .medium)).foregroundStyle(Color(red: 169 / 255, green: 200 / 255, blue: 1))
                    .lineLimit(1).fixedSize()
                    .padding(.vertical, 3.5).padding(.horizontal, 10)
                    .background(Capsule().fill(ArisWidgetStyle.accent.opacity(0.18)))
            }
        }
        .padding(.vertical, 7)
        .background(alignment: .topLeading) {
            ArisRailLine(first: first, last: last).fill(ArisWidgetStyle.hairline).frame(width: 17)
        }
        .overlay(alignment: .topLeading) { dot.offset(x: 3, y: 7 + 6) }
    }

    @ViewBuilder private var dot: some View {
        switch row.state {
        case .next:
            Circle().fill(ArisWidgetStyle.accent).frame(width: 6, height: 6)
                .background(Circle().fill(ArisWidgetStyle.accent.opacity(0.2)).frame(width: 12, height: 12))
        case .past, .later:
            Circle().fill(ArisWidgetStyle.dotFill)
                .overlay(Circle().strokeBorder(row.state == .past ? ArisWidgetStyle.ink42 : ArisWidgetStyle.ink72, lineWidth: 1.5))
                .frame(width: 6, height: 6)
        }
    }
}

/// The rail's 1.5-point line at 5.25 across: through the whole row, from the first dot's centre, to the last one's.
private struct ArisRailLine: Shape {
    let first: Bool
    let last: Bool
    /// Row padding 7 plus the dot's centre, 9.
    private static let centre: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        let top = first ? Self.centre : 0, bottom = last ? Self.centre : rect.height
        guard bottom > top else { return Path() }
        return Path(CGRect(x: 5.25, y: top, width: 1.5, height: bottom - top))
    }
}

// MARK: - Timer

/// The timer (`.tmr`): what it is, the time left at 30 / 600, a 44-point ring of what's left with its share, the bar,
/// then 일시정지 · 5분 더 · 그만. A running timer redraws once a second; a paused one never.
struct ArisTimerCardView: View {
    let state: ArisTimerState
    var actions: ArisWidgetActions?
    /// A fixed moment, for the renders; nil follows the clock.
    var now: Date?

    var body: some View {
        if let now {
            face(at: now)
        } else if state.isPaused {
            face(at: Date())
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in face(at: context.date) }
        }
    }

    private func face(at date: Date) -> some View {
        let left = state.left(at: date), share = state.remaining(at: date)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: state.cardLabel).font(.system(size: 11)).foregroundStyle(ArisWidgetStyle.ink50).arisTextBacking()
                    Text(verbatim: left > 0 ? ArisTimerState.clock(left) : ArisUIWords.text("끝", "Done"))
                        .font(.system(size: 30, weight: .semibold).monospacedDigit()).tracking(-0.3)
                        .foregroundStyle(left > 0 ? ArisWidgetStyle.ink95 : ArisWidgetStyle.good)
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle().stroke(ArisWidgetStyle.track, lineWidth: 4.5)
                    Circle().trim(from: 0, to: share)
                        .stroke(ArisWidgetStyle.mark, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(verbatim: "\(Int((share * 100).rounded()))%").font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(ArisWidgetStyle.ink95)
                }
                .padding(2.25)
                .frame(width: 44, height: 44)
            }
            Capsule().fill(ArisWidgetStyle.track).frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { geometry in
                        Capsule().fill(ArisWidgetStyle.mark).frame(width: geometry.size.width * share)
                    }
                }
                .clipShape(Capsule())
                .padding(.top, 14)
            if let actions {
                HStack(spacing: 8) {
                    Button(state.isPaused ? ArisUIWords.text("계속", "Resume") : ArisUIWords.text("일시정지", "Pause"), action: actions.timerToggle)
                    Button(ArisUIWords.text("5분 더", "5 more min"), action: actions.timerAdd)
                    Button(ArisUIWords.text("그만", "Stop"), action: actions.timerStop)
                }
                .buttonStyle(ArisWidgetPillButton())
                .padding(.top, 12)
            }
        }
        .arisWidgetCard()
    }
}

// MARK: - Music

/// What's playing (`.mu`, the Apple Music palette): radius 14, #1f1f1f, 64-point art, title 16 / 650, previous ·
/// play/pause · next, a 4-point progress track. Playing, the progress moves once a second; paused, nothing moves.
/// No equaliser bars.
struct ArisMusicCardView: View {
    let state: ArisMusicCardState
    var art: NSImage?
    var actions: ArisWidgetActions?
    var now: Date?

    private static let primary = Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
    private static let secondary = Color(red: 161 / 255, green: 161 / 255, blue: 166 / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "music.note").font(.system(size: 11, weight: .semibold))
                Text(verbatim: state.playing ? ArisUIWords.text("지금 재생 중", "Now playing") : ArisUIWords.text("일시정지됨", "Paused")).font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 0)
                if let source = state.source {
                    Text(verbatim: source).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(source == "Spotify" ? Color(red: 30 / 255, green: 215 / 255, blue: 96 / 255) : Color(red: 250 / 255, green: 45 / 255, blue: 72 / 255))
                }
            }
            .foregroundStyle(Self.secondary)
            .padding(.bottom, 12)
            HStack(spacing: 14) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: state.title).font(.system(size: 16, weight: .semibold)).tracking(-0.3).foregroundStyle(Self.primary).lineLimit(1)
                    Text(verbatim: state.byline).font(.system(size: 12)).foregroundStyle(Self.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let actions {
                    HStack(spacing: 2) {
                        control("backward.fill", color: Self.secondary, action: actions.musicPrevious)
                        control(state.playing ? "pause.fill" : "play.fill", color: Self.primary, action: actions.musicToggle)
                        control("forward.fill", color: Self.secondary, action: actions.musicNext)
                    }
                }
            }
            progress.padding(.top, 12)
        }
        .padding(.vertical, 14).padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(red: 31 / 255, green: 31 / 255, blue: 31 / 255)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.047), lineWidth: 1))
    }

    @ViewBuilder private var artwork: some View {
        Group {
            if let art {
                Image(nsImage: art).resizable().scaledToFill()
            } else {
                LinearGradient(stops: [.init(color: Color(white: 0.228), location: 0), .init(color: Color(white: 0.174), location: 0.6),
                                       .init(color: Color(white: 0.143), location: 1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(Image(systemName: "music.note").font(.system(size: 22)).foregroundStyle(Self.primary.opacity(0.55)))
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 6)
    }

    @ViewBuilder private var progress: some View {
        if let now {
            track(at: now)
        } else if state.playing {
            TimelineView(.periodic(from: .now, by: 1)) { context in track(at: context.date) }
        } else {
            track(at: Date())
        }
    }

    private func track(at date: Date) -> some View {
        let position = state.position(at: date)
        let share = state.duration > 0 ? position / state.duration : 0
        return VStack(spacing: 6) {
            Capsule().fill(.white.opacity(0.176)).frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { geometry in Capsule().fill(Self.primary).frame(width: geometry.size.width * share) }
                }
                .clipShape(Capsule())
            HStack {
                Text(verbatim: ArisMusicCardState.clock(position))
                Spacer(minLength: 0)
                Text(verbatim: state.duration > 0 ? ArisMusicCardState.clock(state.duration) : "")
            }
            .font(.system(size: 10).monospacedDigit()).foregroundStyle(Self.secondary)
        }
    }

    private func control(_ symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(color).frame(width: 34, height: 34).contentShape(Circle())
        }
        .buttonStyle(ArisWidgetPressStyle())
    }
}

/// A round control pressed to 90%.
private struct ArisWidgetPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.9 : 1).animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - To-dos

/// A permission of aris-agent's that is off: what it is for, and one button that opens that list in System Settings
/// (nothing else; the switch is the user's to turn on).
struct ArisPermissionOffCardView: View {
    let pane: ArisPermissionPane
    let open: () -> Void
    /// The UI's language, like every other card (it was read off the bundle's localisations on its own).
    private var korean: Bool { !ArisUIWords.english }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ArisWidgetHeader(title: pane.title(korean: korean), trailing: "")
            Text(verbatim: pane.detail(korean: korean)).font(.system(size: 12.5)).foregroundStyle(ArisWidgetStyle.ink72)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            Button(ArisPermissionPane.button(korean: korean), action: open)
                .buttonStyle(ArisWidgetPillButton())
                .padding(.top, 12)
        }
        .arisWidgetCard()
    }
}

/// 할 일 (`.todo`): a hollow check, the title and its list, the due date; today's in the warm colour. A hairline from
/// the text column divides the rows.
struct ArisTodoCardView: View {
    let card: ArisTodoCard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ArisWidgetHeader(title: ArisUIWords.text("할 일", "To-dos"), trailing: ArisUIWords.text("미리 알림 · \(card.total)개", "Reminders · \(card.total)"))
            if card.rows.isEmpty {
                Text(verbatim: ArisUIWords.text("남은 할 일이 없어요", "Nothing left to do")).font(.system(size: 13.5)).foregroundStyle(ArisWidgetStyle.ink50).padding(.vertical, 10)
            }
            ForEach(Array(card.rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 11) {
                    Circle().strokeBorder(ArisWidgetStyle.ink42, lineWidth: 1.5).frame(width: 18, height: 18)
                        .padding(.leading, 2).frame(width: 26, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: row.title).font(.system(size: 13.5)).foregroundStyle(ArisWidgetStyle.ink92).lineLimit(1).arisLineBox(17)
                        if !row.sub.isEmpty {
                            Text(verbatim: row.sub).font(.system(size: 11.5)).foregroundStyle(ArisWidgetStyle.ink50).lineLimit(1).arisLineBox(14.5).arisTextBacking()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let due = row.due {
                        Text(verbatim: due).font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(row.urgent ? ArisWidgetStyle.warn : ArisWidgetStyle.ink42).lineLimit(1).fixedSize().arisTextBacking()
                    }
                }
                .padding(.vertical, 10)
                .overlay(alignment: .top) {
                    if index > 0 { ArisWidgetStyle.hairline.frame(height: 1).padding(.leading, 37) }
                }
            }
        }
        .arisWidgetCard()
    }
}

// MARK: - Presenting

/// The card present: opacity and 96.5% from the top on the opening clock, its face rising 4 points over 0.3 s.
/// With Reduce Motion, a fade only.
struct ArisWidgetPresent: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .offset(y: shown || reduceMotion ? 0 : 4)
            .scaleEffect(shown || reduceMotion ? 1 : 0.965, anchor: .top)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : ArisWidgetStyle.present) { shown = true }
            }
    }
}
