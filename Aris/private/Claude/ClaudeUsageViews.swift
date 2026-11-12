//
//  ClaudeUsageViews.swift
//  Aris
//
//  Usage gauges in the open Claude tab: a compact 5h / 7d row with the window the
//  ear's ring shows lit, or, on an API key, today's spend against the budget.
//

import SwiftUI

enum UsageTint {
    static func color(for percent: Double) -> Color {
        if percent >= ClaudeUsage.warnAt[1] { return Color(ClaudeAccent.error) }
        if percent >= ClaudeUsage.warnAt[0] { return Color(ClaudeAccent.approval) }
        return Color.white.opacity(0.75)
    }
}

struct UsageRing: View {
    let percent: Double
    var lineWidth: CGFloat = 2.5
    /// What the ring is filling with, for VoiceOver: a plan's window or the daily budget (ClaudeUsageWords.ringLabel).
    let reading: ClaudeRingReading

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: percent / 100)
                .stroke(UsageTint.color(for: percent), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.easeOut(duration: 0.4), value: percent)
        .accessibilityLabel(ClaudeUsageWords.ringLabel(reading))
    }
}

/// "5h ◔ 63%   7d ◔ 21%   귀: 5시간", with the reset time on hover; the label of the window the ear's ring shows is lit.
struct UsageMeter: View {
    let usage: ClaudeUsage
    /// The window the ear's ring follows (ClaudeRingReading.window), and what the mark after the gauges says.
    var showing: ClaudeLimitWindow? = nil
    var mark: String? = nil

    var body: some View {
        let now = Date()
        HStack(spacing: 10) {
            if let window = usage.fiveHour {
                gauge("5h", .fiveHour, window, now: now, lit: showing == .fiveHour, reset: window.resetsAt.formatted(date: .omitted, time: .shortened))
            }
            if let window = usage.sevenDay {
                gauge("7d", .sevenDay, window, now: now, lit: showing == .sevenDay, reset: window.resetsAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
            }
            if let mark, usage.fiveHour != nil || usage.sevenDay != nil {
                Text(mark).font(.system(size: 9.5)).foregroundStyle(.gray).lineLimit(1)
            }
        }
    }

    private func gauge(_ label: String, _ name: ClaudeLimitWindow, _ window: UsageWindow, now: Date, lit: Bool, reset: String) -> some View {
        let percent = window.percent(at: now)
        return HStack(spacing: 4) {
            UsageLabel(text: label, lit: lit)
            UsageRing(percent: percent, lineWidth: 2, reading: .limit(name, percent)).frame(width: 11, height: 11)
            // Claude Code reports whole percents; rounding up never makes a limit read lower than it is.
            Text("\(Int(percent.rounded(.up)))%")
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(UsageTint.color(for: percent))
                .animation(.easeOut(duration: 0.4), value: UsageTint.color(for: percent))
        }
        .help("\(label) limit resets \(reset)")
    }
}

/// An API key's line: "오늘 ◔ $1.24 / $5   이 세션 $0.75" (the budget's ring and "/ $Y" only while the budget is on).
struct SpendMeter: View {
    let spent: Double
    let budget: Double?
    let session: Double?

    var body: some View {
        let reading = ClaudeRingReading.budget(spent: spent, budget: budget)
        let tint = reading.percent.map(UsageTint.color(for:)) ?? Color.white.opacity(0.75)
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                UsageLabel(text: ClaudeUsageWords.todayLabel(), lit: true)
                if let percent = reading.percent { UsageRing(percent: percent, lineWidth: 2, reading: reading).frame(width: 11, height: 11) }
                Text(ClaudeBudget.money(spent)).font(.system(size: 10.5, weight: .semibold).monospacedDigit()).foregroundStyle(tint)
                if let budget { Text("/ \(ClaudeBudget.money(budget))").font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.gray) }
            }
            if let session {
                HStack(spacing: 4) {
                    UsageLabel(text: ClaudeUsageWords.sessionLabel(), lit: false)
                    Text(ClaudeBudget.money(session)).font(.system(size: 10.5, weight: .semibold).monospacedDigit()).foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ClaudeUsageWords.today(spent: spent, budget: budget, session: session))
    }
}

/// A gauge's name: grey, or bright for the one the ear shows.
private struct UsageLabel: View {
    let text: String
    let lit: Bool

    var body: some View {
        Text(text).font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(lit ? Color.white.opacity(0.9) : Color.gray)
            .animation(.easeInOut(duration: 0.3), value: lit)
    }
}
