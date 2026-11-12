//
//  ArisUsageCard.swift
//  Aris
//
//  The left panel's 사용량 tab, CodexBar's information (github.com/steipete/CodexBar, MIT): sliding provider tabs
//  over the chosen provider's detail (windows with pace, cost, 30-day chart, recent weekly windows).
//

import SwiftUI

/// Logo and colour per provider id; an unknown provider gets a generic mark in the glass's white. The colours are
/// each provider's own (ArisProviderColors).
enum ArisUsageBrand {
    struct Style {
        let asset: String?
        let tint: Color
        let isTemplate: Bool
    }

    static func style(_ id: String) -> Style {
        let tint = ArisProviderColors.color(id).map { Color($0) } ?? .white.opacity(0.7)
        return switch id {
        case "claude": Style(asset: "ProviderBrand-claude", tint: tint, isTemplate: false)
        case "codex", "antigravity", "gemini", "openrouter": Style(asset: "ProviderIcon-\(id)", tint: tint, isTemplate: true)
        default: Style(asset: nil, tint: tint, isTemplate: true)
        }
    }
}

private enum UsageColor {
    static let under = Color(red: 0x4a / 255, green: 0xde / 255, blue: 0x80 / 255)
    static let over = Color(red: 0xf1 / 255, green: 0x6c / 255, blue: 0x70 / 255)
    static let amber = Color(red: 0xf4 / 255, green: 0xc6 / 255, blue: 0x4e / 255)
}

struct UsageLogo: View {
    let id: String
    let size: CGFloat

    var body: some View {
        let style = ArisUsageBrand.style(id)
        Group {
            if let asset = style.asset, !style.isTemplate {
                Image(asset).resizable().scaledToFit().frame(width: size, height: size)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 5 / 18, style: .continuous).fill(.white.opacity(0.08))
                    if let asset = style.asset {
                        Image(asset).renderingMode(.template).resizable().scaledToFit()
                            .foregroundStyle(style.tint).frame(width: size * 14 / 18, height: size * 14 / 18)
                    } else {
                        Image(systemName: "sparkles").font(.system(size: size * 0.6)).foregroundStyle(style.tint)
                    }
                }
                .frame(width: size, height: size)
            }
        }
    }
}

/// One limit as a row of the usage list: a window with its label for the cell and the detail.
private struct UsageRow: Identifiable {
    let id: String
    let lane: String
    let label: String
    let window: ArisUsageWindow
}

private extension ArisUsageProvider {
    var rows: [UsageRow] {
        lanes.enumerated().flatMap { index, lane -> [UsageRow] in
            var rows: [UsageRow] = []
            if let window = lane.fiveHour { rows.append(UsageRow(id: "\(index)s", lane: lane.name, label: ArisUsageWords.session(), window: window)) }
            if let window = lane.weekly { rows.append(UsageRow(id: "\(index)w", lane: lane.name, label: ArisUsageWords.weekly(), window: window)) }
            return rows
        }
    }
}

/// A provider's bare glyph for the tabs: a template image the tab colours, like the header's symbols.
private struct UsageTabIcon: View {
    let id: String

    var body: some View {
        if let asset = id == "claude" ? "ProviderIcon-claude" : ArisUsageBrand.style(id).asset {
            Image(asset).renderingMode(.template).resizable().scaledToFit().frame(width: 13, height: 13)
        } else {
            Image(systemName: "sparkles").font(.system(size: 12, weight: .medium))
        }
    }
}

struct ArisUsageCard: View {
    @ObservedObject private var usage = ArisUsageModel.shared
    @ObservedObject private var panels = ArisSidePanels.shared

    var body: some View {
        let providers = usage.providers
        let current = providers.first { $0.id == panels.usageDetail } ?? providers.first
        VStack(alignment: .leading, spacing: 8) {
            if let current {
                ArisSlidingTabs(
                    items: providers.map { .init(id: $0.id, icon: AnyView(UsageTabIcon(id: $0.id)), title: $0.title,
                                                 selectedTint: ArisUsageBrand.style($0.id).tint) },
                    selection: Binding(get: { current.id }, set: { panels.usageDetail = $0 }),
                    unselectedWidth: 30, height: 28)
                // Every provider's detail has the same layout, so switching morphs it in place (numbers, bars, colours)
                // rather than crossfading two pages, which blinked the panel darker (ArisTabSwap).
                ScrollView(.vertical, showsIndicators: false) {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        ArisUsageDetail(provider: current, now: context.date)
                    }
                    .padding(.horizontal, 7)
                    .padding(ArisSideStyle.listInsets(underHeader: false, toEdge: true))
                    .animation(ArisTabMotion.fade, value: current.id)
                }
                // Under the providers' tabs and down to the panel's edge, with the 34-point fade at the end.
                .modifier(ArisSideListFrame(underHeader: false, toEdge: true))
                // After the mask: the mask must cover the rows widened by -7, or it cuts their rounded ends off.
                .padding(.horizontal, -7)
            } else {
                switch usage.tabState {
                case .none:
                    // No AI with a plan on this Mac: said in one line, with the way to connect one.
                    notice(ArisUsageTabCopy.none(), button: ArisBrainTrouble.settingsButton(english: ArisUIWords.english)) {
                        ArisSettingsNav.shared.go(.ai, anchor: ArisSettingsCaption.brainAnchor)
                        ArisStepAside.showSettings()
                    }
                case .unread:
                    notice(ArisUsageTabCopy.unread(), button: ArisUsageTabCopy.retry()) { Task { await usage.refresh() } }
                case .loading, .listed:
                    ArisSideStyle.empty(ArisUsageTabCopy.loading())
                }
            }
        }
        .onAppear { Task { await usage.refresh() } }
    }

    /// A line and one button in the panel's pill, as the 캘린더 tab asks for access.
    private func notice(_ line: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(line).font(.system(size: 12)).foregroundStyle(.white.opacity(0.82)).fixedSize(horizontal: false, vertical: true)
            Button(action: action) {
                Text(button)
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
}

/// A bar filled with what's left of a window, with a pace tick (green under the pace, red over it) and, thick,
/// the dark marks at half and a fifth left.
private struct UsageBar: View {
    let window: ArisUsageWindow
    let now: Date
    let tint: Color
    let height: CGFloat
    let separators: Bool

    var body: some View {
        let remaining = min(max(window.remaining(at: now), 0), 100) / 100
        let pace = window.pace(at: now)
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1))
                Capsule().fill(tint).frame(width: width * remaining)
                if separators {
                    ForEach([0.5, 0.2], id: \.self) { mark in
                        Rectangle().fill(Color(red: 0, green: 0, blue: 6 / 255).opacity(0.85)).frame(width: 1.5, height: height)
                            .offset(x: width * mark - 0.75)
                    }
                }
                if let pace {
                    RoundedRectangle(cornerRadius: 1).fill(pace.deltaPercent < 0 ? UsageColor.under : UsageColor.over)
                        .frame(width: 2, height: height + 4)
                        .offset(x: width * (1 - pace.expectedUsedPercent / 100) - 1)
                }
            }
            .frame(height: height + 4)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: height + 4)
    }
}

private struct ArisUsageDetail: View {
    let provider: ArisUsageProvider
    let now: Date
    /// While side-demo is on (the ad), who is signed in and every amount of money are masked (ArisUsageMask).
    @ObservedObject private var demo = ArisSideDemo.shared

    private var tint: Color { ArisUsageBrand.style(provider.id).tint }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The name and when it was read are whole; who is signed in and the plan take all the room left on their
            // line and end in an ellipsis only when that is not enough (side 1: the account was held to 120 points
            // with room beside it, and a long plan broke the line before it in two).
            HStack(alignment: .firstTextBaseline) {
                Text(provider.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1).fixedSize().layoutPriority(1)
                Spacer(minLength: 8)
                if let account = provider.account {
                    Text(ArisUsageMask.account(account, masked: demo.isOn)).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1).truncationMode(.tail)
                }
            }
            .padding(EdgeInsets(top: 4, leading: 4, bottom: 0, trailing: 4))
            HStack {
                Text(updated).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1).fixedSize().layoutPriority(1)
                Spacer(minLength: 8)
                if let plan = provider.plan {
                    Text(plan).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineLimit(1).truncationMode(.tail)
                }
            }
            .padding(EdgeInsets(top: 1, leading: 4, bottom: provider.note == nil ? 9 : 4, trailing: 4))
            if let note = provider.note {
                Text(note).font(.system(size: 10)).foregroundStyle(UsageColor.amber)
                    .padding(EdgeInsets(top: 0, leading: 4, bottom: 9, trailing: 4))
            }
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1).padding(.bottom, 10)
            let rows = provider.rows
            let multiLane = Set(rows.map(\.lane).filter { !$0.isEmpty }).count > 1
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if multiLane, !row.lane.isEmpty, index == 0 || rows[index - 1].lane != row.lane {
                    ArisSideStyle.dayHeading(row.lane).padding(.horizontal, -8).padding(.top, -8)
                }
                windowBlock(row)
            }
            if let cost = provider.cost {
                costBlock(cost)
            } else if provider.id == "claude" || provider.id == "codex" {
                Text(ArisUsageWords.costLoading()).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).padding(EdgeInsets(top: 2, leading: 4, bottom: 0, trailing: 4))
            }
        }
    }

    private var updated: String {
        ArisUsageWords.updated(minutes: Int(max(0, now.timeIntervalSince(provider.updatedAt)) / 60))
    }

    private func windowBlock(_ row: UsageRow) -> some View {
        let remaining = Int(row.window.remaining(at: now).rounded())
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(ArisUsageWords.remaining(row.label, percent: remaining)).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1).layoutPriority(1)
                Spacer(minLength: 4)
                if row.window.resetsAt != nil {
                    Text(ArisUsageWords.resets(row.window.resetsAt, now: now))
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1).minimumScaleFactor(0.85)
                }
            }
            UsageBar(window: row.window, now: now, tint: tint, height: 7, separators: true)
            if let pace = row.window.pace(at: now) {
                Text(ArisUsageWords.pace(pace, now: now)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).padding(.top, 0)
            }
        }
        .padding(EdgeInsets(top: 0, leading: 4, bottom: 12, trailing: 4))
    }

    private func costBlock(_ cost: ArisUsageCost) -> some View {
        let week = cost.windows.first
        return VStack(alignment: .leading, spacing: 0) {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 7) {
                stat(ArisUsageWords.today(), ArisUsageMask.usd(cost.today.usd, masked: demo.isOn), big: true)
                stat(ArisUsageWords.thisWeek(), ArisUsageMask.usd(week?.usd ?? 0, masked: demo.isOn), big: true)
                stat(ArisUsageWords.todayTokens(), ArisUsageFormat.tokens(cost.today.tokens))
                stat(ArisUsageWords.weekTokens(), ArisUsageFormat.tokens(week?.tokens ?? 0))
                stat(ArisUsageWords.monthCost(), ArisUsageMask.usd(cost.last30.usd, masked: demo.isOn))
                stat(ArisUsageWords.monthTokens(), ArisUsageFormat.tokens(cost.last30.tokens))
            }
            .padding(EdgeInsets(top: 2, leading: 4, bottom: 8, trailing: 4))
            chart(cost)
            Text(ArisUsageWords.recentWeeks()).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).padding(EdgeInsets(top: 12, leading: 4, bottom: 4, trailing: 4))
            ForEach(Array(cost.windows.enumerated()), id: \.offset) { index, window in
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(ArisUsageWords.week(index))
                        Spacer()
                        Text("\(ArisUsageMask.usd(window.usd, masked: demo.isOn)) · \(ArisUsageFormat.tokens(window.tokens))")
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                    Text(range(window, withTime: index == 0)).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.45))
                }
                .foregroundStyle(.white.opacity(0.94))
                .padding(EdgeInsets(top: 3, leading: 4, bottom: 3, trailing: 4))
            }
            VStack(alignment: .leading, spacing: 0) {
                if let model = cost.topModel { Text(ArisUsageWords.topModel(model)) }
                Text(ArisUsageWords.costNote())
            }
            .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.4))
            .padding(EdgeInsets(top: 10, leading: 4, bottom: 0, trailing: 4))
        }
    }

    private func stat(_ title: String, _ value: String, big: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            Text(value).font(.system(size: big ? 14 : 12.5, weight: .semibold).monospacedDigit()).foregroundStyle(.white.opacity(0.94))
        }
    }

    private func chart(_ cost: ArisUsageCost) -> some View {
        let peak = cost.daily.map(\.usd).max() ?? 0
        return ZStack(alignment: .topTrailing) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(cost.daily.enumerated()), id: \.offset) { _, day in
                    UnevenRoundedRectangle(topLeadingRadius: 1.5, topTrailingRadius: 1.5)
                        .fill(day.usd > 0 ? tint.opacity(day.usd == peak ? 1 : 0.72) : Color.white.opacity(0.12))
                        .frame(height: max(1.5, peak > 0 ? 48 * day.usd / peak : 0))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.top, 14)
            if peak > 0 {
                Text(ArisUsageMask.peak(peak, masked: demo.isOn)).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(height: 62)
        .padding(.horizontal, 4)
    }

    private func range(_ window: ArisUsageSpendWindow, withTime: Bool) -> String {
        ArisUsageWords.range(window.start, window.end, withTime: withTime)
    }
}
