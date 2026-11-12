//
//  ArisSettingsPageView.swift
//  Aris
//
//  Draws a page's sections, each as one card with its rows split by hairlines (the owner's pick 2-B, the shape of the AI
//  서비스 page): a section title (15/600), its card, and under the card the section's one small line. One rhythm and
//  one row anatomy on every page (ArisSettingsMetrics: 32 / 12 / 16, rows 20 inside, a 20-pt icon column). Values go
//  out through ArisSettingsHandlers; nothing here knows where a setting is kept.
//

import SwiftUI

/// What the page's controls call, and the parts drawn by the app (logos, API keys, the about card).
struct ArisSettingsHandlers {
    var set: (ArisSettingKey, ArisSettingValue, String) -> Void = { _, _, _ in }
    var perform: (ArisSettingsAction) -> Void = { _ in }
    /// Starts (or stops) recording the named shortcut.
    var record: (String) -> Void = { _ in }
    var recording: String?
    var openMenu: (ArisSettingMenu) -> Void = { _ in }
    /// The setting whose menu is open (its button looks pressed).
    var menuOpen: ArisSettingKey?
    var custom: (ArisSettingItem) -> AnyView? = { _ in nil }
    var logo: (String) -> AnyView = { id in AnyView(Text(String(id.prefix(1)).uppercased()).font(.system(size: 12, weight: .bold))) }
}

/// The row a search landed on, and a count that rises with each landing.
struct ArisSettingsFlashTarget: Equatable {
    let id: String
    let token: Int
}

private struct HandlersKey: EnvironmentKey { static let defaultValue = ArisSettingsHandlers() }
private struct FlashKey: EnvironmentKey { static let defaultValue: ArisSettingsFlashTarget? = nil }
private struct WordsKey: EnvironmentKey { static let defaultValue = ArisSettingsWording.korean }

extension EnvironmentValues {
    var arisSettingsHandlers: ArisSettingsHandlers {
        get { self[HandlersKey.self] }
        set { self[HandlersKey.self] = newValue }
    }

    var arisSettingsFlash: ArisSettingsFlashTarget? {
        get { self[FlashKey.self] }
        set { self[FlashKey.self] = newValue }
    }

    /// How the part of the window being drawn words itself: Korean as written, or English (ArisSettingsCopy).
    var arisWords: ArisSettingsWording {
        get { self[WordsKey.self] }
        set { self[WordsKey.self] = newValue }
    }
}

extension View {
    /// Highlights once when a search lands on `id`.
    func arisFlash(_ id: String, radius: CGFloat = 18) -> some View { modifier(ArisFlashSlot(id: id, radius: radius)) }

    /// Card surface: r18, the card fill, a 1-pt border (white light, 6% dark), dark's soft shadow and top light.
    func arisCard(radius: CGFloat = ArisSettingsMetrics.cardRadius) -> some View { modifier(ArisCardSurface(radius: radius)) }
}

private struct ArisFlashSlot: ViewModifier {
    @Environment(\.arisSettingsFlash) private var flash
    let id: String
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.modifier(ArisFlash(token: flash?.id == id ? flash?.token : nil, radius: radius))
    }
}

struct ArisCardSurface: ViewModifier {
    @Environment(\.arisPalette) private var palette
    var radius: CGFloat = 18
    var hover = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(shape.fill(palette.cardFill).shadow(color: palette.cardShadow, radius: 3, y: 1))
            .overlay(shape.strokeBorder(hover ? palette.cardBorderHover : palette.cardBorder, lineWidth: 1))
            .overlay(shape.strokeBorder(LinearGradient(colors: [palette.cardTopLight, .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
    }
}

// MARK: - Page

struct ArisSettingsPageView: View {
    let sections: [ArisSettingSection]
    @Environment(\.arisSettingsFolds) private var folds
    @Environment(\.arisSettingsFlash) private var flash

    private enum Element: Identifiable {
        case heading(String, anchor: String)
        /// A section's card; `fold`: the one line it is until opened, and the section it belongs to.
        case card([ArisSettingItem], anchor: String?, fold: ArisSettingFold?, section: String)
        /// The small line under a card: what must be known about the rows above it.
        case fine(String, anchor: String?)

        var id: String {
            switch self {
            case .heading(_, let anchor): "h." + anchor
            case .fine(let text, _): "n." + text
            case .card(let rows, _, _, let section): "g." + section + "." + rows.map(\.id).joined(separator: ",")
            }
        }
    }

    /// Each element with the space above it: a title 32 under what came before and 12 over its card, cards 16 apart,
    /// the small line 8 under its card. The page's first element sits right under the page's title.
    private var elements: [(element: Element, top: CGFloat)] {
        typealias M = ArisSettingsMetrics
        var out: [(Element, CGFloat)] = []
        for section in sections {
            var previous: String?
            var anchor: String? = section.id
            if let heading = section.heading {
                out.append((.heading(heading, anchor: section.id), M.sectionGap))
                previous = "heading"
                anchor = nil
            }
            for block in ArisSettingsLayout.blocks(section) {
                guard case .group(let rows) = block else { continue }
                out.append((.card(rows, anchor: anchor, fold: section.fold, section: section.id), previous == "heading" ? M.headingGap : M.cardGap))
                previous = "card"
                anchor = nil
            }
            if let note = section.note {
                out.append((.fine(note, anchor: anchor), previous == "card" ? M.fineGap : previous == "heading" ? M.headingGap : M.cardGap))
            }
        }
        if let first = out.first { out[0] = (first.0, 0) }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(elements.enumerated()), id: \.element.element.id) { index, item in
                element(item.element)
                    .padding(.top, item.top)
                    .modifier(ArisRise(index: index + 2))
            }
        }
        // A search (or a link) that lands inside a folded group opens the fold first; the shell scrolls a moment later.
        .onAppear { unfold(flash) }
        .onChange(of: flash) { _, target in unfold(target) }
    }

    private func unfold(_ target: ArisSettingsFlashTarget?) {
        guard let id = target?.id, let holder = ArisSettingsLayout.fold(holding: id, in: sections) else { return }
        folds.set(holder, open: true)
    }

    @ViewBuilder
    private func element(_ element: Element) -> some View {
        switch element {
        case .heading(let text, let anchor): ArisSectionTitle(text: text).id(anchor)
        case .fine(let text, let anchor): ArisFineLine(text: text).id(anchor ?? element.id)
        case .card(let rows, let anchor, let fold, let section):
            ArisGroupCard(rows: rows, fold: fold, section: section, folds: folds)
                // A folded section keeps its own tag even under a title: a search for the group lands on its line.
                .id(anchor ?? (fold == nil ? element.id : section))
                .arisFlash(anchor ?? (fold == nil ? "" : section))
        }
    }
}

/// The window's entrance: each element rises 6 pt and fades in, 0.34 s on the house curve, 40 ms apart (at most 8).
/// It plays when the window opens and never when a page is chosen (pick 4-A: staggered entrances are for first
/// presentation; emil-design-eng: nothing staged on what is done tens of times).
struct ArisRise: ViewModifier {
    @Environment(\.arisSettingsStill) private var still
    @Environment(\.arisSettingsEntering) private var entering
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || still || !entering ? 1 : 0)
            .offset(y: shown || still || !entering || ArisSettingsMotion.reduced ? 0 : 6)
            .onAppear {
                guard entering else { shown = true; return }
                withAnimation(ArisSettingsMotion.reduced ? .easeOut(duration: 0.15) : ArisSettingsMotion.house(0.34).delay(Double(min(index, 8)) * 0.04)) { shown = true }
            }
    }
}

/// A page chosen in the sidebar: its cards come in over 0.15 s, with no movement and no stagger, while the preview and
/// the title stay where they are (pick 4-A). Chosen with a key, or while the window is still opening, they are simply there.
struct ArisPageSwap: ViewModifier {
    let animated: Bool
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || !animated ? 1 : 0)
            .onAppear {
                guard animated else { shown = true; return }
                withAnimation(ArisSettingsMotion.swap) { shown = true }
            }
    }
}

struct ArisSectionTitle: View {
    @Environment(\.arisPalette) private var palette
    let text: String

    var body: some View {
        Text(text).font(.system(size: 15, weight: .semibold)).tracking(-0.15).foregroundStyle(palette.title)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The 팀원 page's own lines above its lists.
struct ArisPageNote: View {
    @Environment(\.arisPalette) private var palette
    let text: String

    var body: some View {
        Text(ArisKoreanText.keepAll(text)).font(.system(size: 12.5)).foregroundStyle(palette.desc).lineSpacing(3.5).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The one small line under a card (mockup `.fine`: 12 pt in the faintest ink, 4 in from the card's edge).
struct ArisFineLine: View {
    @Environment(\.arisPalette) private var palette
    let text: String

    var body: some View {
        Text(ArisKoreanText.keepAll(text)).font(.system(size: 12)).foregroundStyle(palette.ink3).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ArisSettingsMetrics.fineInset)
    }
}

// MARK: - Cards

/// A section's card: its rows one under the other, a hairline between, each row 20 inside. A folded section's card is
/// its one line, and the rows under it only while it is open.
struct ArisGroupCard: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisSettingsHandlers) private var handlers
    let rows: [ArisSettingItem]
    var fold: ArisSettingFold?
    var section = ""
    @ObservedObject var folds: ArisSettingsFolds

    init(rows: [ArisSettingItem], fold: ArisSettingFold? = nil, section: String = "", folds: ArisSettingsFolds = .memory) {
        self.rows = rows
        self.fold = fold
        self.section = section
        self.folds = folds
    }

    var body: some View {
        let open = fold == nil || folds.open.contains(section)
        VStack(alignment: .leading, spacing: 0) {
            if let fold {
                ArisFoldRow(symbol: fold.symbol, title: fold.title, desc: fold.desc, open: open) { folds.set(section, open: !open) }
            }
            if open {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 || fold != nil { Rectangle().fill(palette.hairline).frame(height: 1) }
                    rowView(row)
                        // The tag a search result scrolls to (ArisSettingsLayout.tags).
                        .id(row.id)
                        .arisFlash(row.id, radius: 0)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ArisSettingsMetrics.cardRadius, style: .continuous))
        .arisCard()
    }

    @ViewBuilder
    private func rowView(_ row: ArisSettingItem) -> some View {
        if case .link = row.control {
            ArisLinkRowButton(item: row)
        } else if case .custom(let kind) = row.control, let custom = handlers.custom(row) {
            // A row the app draws insets itself; the about card is a plain view and takes the row's inset here.
            if kind == "about" { custom.padding(ArisSettingsMetrics.rowInset).frame(maxWidth: .infinity, alignment: .leading) } else { custom }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ArisSettingRowView(item: row).padding(ArisSettingsMetrics.rowInset).frame(minHeight: ArisSettingsMetrics.rowMinHeight)
                ArisRowExtraBelow(item: row)
            }
        }
    }
}

/// A card's one line that folds what is under it (the row AI 서비스 folds 연결된 서비스 with): the icon, the name, what
/// is inside, and a chevron that turns down when open. The rows under it simply appear (nothing slides).
struct ArisFoldRow: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let symbol: String
    let title: String
    let desc: String
    let open: Bool
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: ArisSettingsMetrics.iconGap) {
                Image(systemName: symbol).font(.system(size: 16.5, weight: .medium)).foregroundStyle(palette.icon)
                    .frame(width: ArisSettingsMetrics.iconBox, height: ArisSettingsMetrics.iconBox)
                VStack(alignment: .leading, spacing: 2) {
                    Text(w(title)).font(.system(size: 14, weight: .medium)).tracking(-0.07).foregroundStyle(palette.title)
                    Text(w.dotted(desc)).font(.system(size: 12)).foregroundStyle(palette.desc)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.title)
                    .rotationEffect(.degrees(open ? 90 : 0))
            }
            .padding(ArisSettingsMetrics.rowInset).frame(minHeight: ArisSettingsMetrics.rowMinHeight)
            .background(hovering ? palette.rowHover : .clear)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.15), value: hovering)
            .animation(ArisSettingsMotion.reduced ? nil : .easeOut(duration: 0.15), value: open)
        }
        .buttonStyle(ArisPressScale(scale: 0.99))
        .onHover { hovering = $0 }
        .accessibilityLabel(w(title))
        .accessibilityValue(w(open ? "펼침" : "접힘"))
        .accessibilityHint(w.dotted(desc))
    }
}

/// Which folded sections are open, remembered between launches (the window's own; the offscreen renders keep theirs
/// in memory and write nothing).
final class ArisSettingsFolds: ObservableObject {
    static let key = "arisSettingsOpenFolds"
    /// Only ever touched on the main thread, by the views that draw the folds.
    nonisolated(unsafe) static let memory = ArisSettingsFolds(store: nil)

    @Published private(set) var open: Set<String>
    private let store: UserDefaults?

    init(store: UserDefaults?) {
        self.store = store
        open = ArisSettingsLayout.openFolds(stored: store?.array(forKey: Self.key))
    }

    func set(_ section: String, open isOpen: Bool) {
        guard open.contains(section) != isOpen else { return }
        if isOpen { open.insert(section) } else { open.remove(section) }
        store?.set(ArisSettingsLayout.stored(openFolds: open), forKey: Self.key)
    }
}

private struct FoldsKey: EnvironmentKey { static let defaultValue = ArisSettingsFolds.memory }

extension EnvironmentValues {
    /// The window's folds (ArisSettingsRoot hands in the remembered ones).
    var arisSettingsFolds: ArisSettingsFolds {
        get { self[FoldsKey.self] }
        set { self[FoldsKey.self] = newValue }
    }
}

/// 정보's top card: the star, the name, the version.
struct ArisAboutCard: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisSettingsArt) private var art
    let version: String

    var body: some View {
        HStack(spacing: 16) {
            art.star(48).frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("Aris").font(.system(size: 17, weight: .bold)).tracking(-0.34).foregroundStyle(palette.title)
                Text(version).font(.system(size: 12)).foregroundStyle(palette.desc)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Rows

struct ArisRowIcon: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    @Environment(\.arisSettingsHandlers) private var handlers
    let icon: ArisSettingIcon

    var body: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name).font(.system(size: 16.5, weight: .medium)).foregroundStyle(palette.icon)
                .frame(width: ArisSettingsMetrics.iconBox, height: ArisSettingsMetrics.iconBox)
        case .dot(let hex):
            Circle().fill(Color(arisHexString: hex) ?? .gray).overlay(Circle().strokeBorder(.black.opacity(0.1), lineWidth: 0.5))
                .frame(width: 11, height: 11).frame(width: 20, height: 20)
        case .status(let ok):
            Circle().fill(ok ? palette.ok : palette.bad).frame(width: 9, height: 9).frame(width: 20, height: 20)
                .accessibilityLabel(w(ok ? "허용됨" : "허용 안 됨"))
        case .logo(let id):
            handlers.logo(id).frame(width: 20, height: 20)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(palette.appTile))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(palette.appTileRing, lineWidth: 1))
        case .none:
            // The column is kept: a row with no icon starts its words where every other row does.
            Color.clear.frame(width: ArisSettingsMetrics.iconBox, height: ArisSettingsMetrics.iconBox)
        }
    }
}

/// An icon, the title and its line (and chips under them), and the control at the end.
struct ArisSettingRowView: View {
    @Environment(\.arisPalette) private var palette
    let item: ArisSettingItem

    private var chips: Bool { if case .chips = item.extra { true } else { false } }

    var body: some View {
        switch item.control {
        case .empty: ArisEmptyRow(title: item.title, sub: item.desc, loading: false)
        case .loading: ArisEmptyRow(title: item.title, sub: item.desc, loading: true)
        default: row
        }
    }

    private var row: some View {
        HStack(alignment: chips ? .top : .center, spacing: ArisSettingsMetrics.iconGap) {
            // A row that destroys something looks like any other: the red is said once, on its button (item 13).
            ArisRowIcon(icon: item.icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 14, weight: .medium)).tracking(-0.07).foregroundStyle(palette.title)
                if let desc = item.desc, !desc.isEmpty {
                    Text(ArisKoreanText.keepAll(desc)).font(.system(size: 12)).foregroundStyle(palette.desc).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }
                ArisRowChips(item: item)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ArisRowControl(item: item)
        }
    }
}

private struct ArisRowChips: View {
    @Environment(\.arisSettingsHandlers) private var handlers
    let item: ArisSettingItem

    var body: some View {
        if case .chips(let chips, let removable) = item.extra {
            ArisFlow(spacing: 6) {
                ForEach(chips, id: \.id) { chip in
                    ArisRemovableChip(title: chip.title, removable: removable) { handlers.perform(.removeLanguage(chip.id)) }
                }
            }
            .padding(.top, 10)
        }
    }
}

/// What sits under a row inside its card: the accent swatches.
private struct ArisRowExtraBelow: View {
    @Environment(\.arisSettingsHandlers) private var handlers
    let item: ArisSettingItem

    var body: some View {
        if case .swatches(let colors, let selected) = item.extra {
            ArisSwatches(colors: colors, selected: selected, pick: { handlers.perform(.accent($0)) }, custom: { handlers.perform(.pickAccent) })
                .padding(.leading, ArisSettingsMetrics.rowInset + ArisSettingsMetrics.iconBox + ArisSettingsMetrics.iconGap).padding(.trailing, ArisSettingsMetrics.rowInset)
                .padding(.bottom, ArisSettingsMetrics.rowInset).padding(.top, -8)
        }
    }
}

/// A whole row that is a button: icon, title, line, the value and a chevron.
struct ArisLinkRowButton: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisSettingsHandlers) private var handlers
    let item: ArisSettingItem
    @State private var hovering = false

    var body: some View {
        guard case .link(let action, let value) = item.control else { return AnyView(EmptyView()) }
        return AnyView(
            Button { handlers.perform(action) } label: {
                HStack(spacing: ArisSettingsMetrics.iconGap) {
                    ArisRowIcon(icon: item.icon)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.system(size: 14, weight: .medium)).tracking(-0.07).foregroundStyle(palette.title)
                        if let desc = item.desc {
                            Text(ArisKoreanText.keepAll(desc)).font(.system(size: 12)).foregroundStyle(palette.desc).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let value { Text(value).font(.system(size: 13)).foregroundStyle(palette.desc) }
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(hovering ? palette.desc : palette.ink3)
                        .offset(x: hovering && !ArisSettingsMotion.reduced ? 1 : 0)
                }
                .padding(ArisSettingsMetrics.rowInset).frame(minHeight: ArisSettingsMetrics.rowMinHeight)
                .background(hovering ? palette.rowHover : .clear)
                .contentShape(Rectangle())
                .animation(.easeOut(duration: 0.12), value: hovering)
            }
            // A whole row presses only a little (the approved kit's 0.99): at a button's 0.97 a 700-pt row would jump.
            .buttonStyle(ArisPressScale(scale: 0.99))
            .onHover { hovering = $0 }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
        )
    }
}

/// Plain small words at a row's end (mockup `.said`: 12 pt in the faintest ink): a state that needs nothing done.
struct ArisSaid: View {
    @Environment(\.arisPalette) private var palette
    let text: String

    var body: some View {
        Text(text).font(.system(size: 12)).foregroundStyle(palette.ink3).lineLimit(1).fixedSize()
    }
}

/// A card with nothing to list yet, or still being read: plain centred 13-pt text in the second ink, 32 above and
/// below, no illustration. While it loads the words shimmer.
struct ArisEmptyRow: View {
    @Environment(\.arisPalette) private var palette
    let title: String
    var sub: String?
    let loading: Bool

    var body: some View {
        VStack(spacing: 4) {
            if loading { ArisShimmerText(text: title) } else { Text(title).font(.system(size: 13)).foregroundStyle(palette.desc) }
            if let sub, !sub.isEmpty { Text(ArisKoreanText.keepAll(sub)).font(.system(size: 12)).foregroundStyle(palette.ink3) }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

/// Words with a soft light passing over them every 2.4 s while
/// something is on its way: one sweep, nothing blinks. Under Reduce Motion, and offscreen, the words are still.
struct ArisShimmerText: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisSettingsStill) private var still
    let text: String
    @State private var sweep = false

    var body: some View {
        let words = Text(text).font(.system(size: 13))
        words.foregroundStyle(palette.desc)
            .overlay {
                if !still && !ArisSettingsMotion.reduced {
                    GeometryReader { proxy in
                        LinearGradient(colors: [.clear, palette.title, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: proxy.size.width * 0.5)
                            .offset(x: sweep ? proxy.size.width * 1.2 : -proxy.size.width * 0.7)
                    }
                    .mask(words)
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard !still, !ArisSettingsMotion.reduced else { return }
                withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) { sweep = true }
            }
    }
}

/// The control at a row's end.
struct ArisRowControl: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    @Environment(\.arisSettingsHandlers) private var handlers
    let item: ArisSettingItem

    var body: some View {
        switch item.control {
        case .none, .link, .empty, .loading:
            EmptyView()
        case .said(let text):
            ArisSaid(text: text)
        case .toggle(let key, let on, let enabled):
            ArisSwitch(isOn: on, enabled: enabled, label: item.title) { handlers.set(key, .bool(!on), item.title) }
        case .choice(let key, let options, let selected, let disabled, let lead):
            HStack(spacing: 8) {
                if let lead { button(lead) }
                ArisGlassSegmented(options: options, selected: selected, disabled: Set(disabled), label: item.title) { handlers.set(key, .text($0), item.title) }
            }
        case .menu(let key, let options, let selected):
            ArisMenuButton(key: key, title: item.title, options: options, selected: selected)
        case .buttons(let buttons):
            HStack(spacing: 8) { ForEach(Array(buttons.enumerated()), id: \.offset) { _, b in button(b) } }
        case .status(let ok, let next):
            // Allowed is said in words (a lone green dot said nothing); what is next to do keeps its button.
            HStack(spacing: 10) {
                if ok { ArisSaid(text: w("허용됨")) }
                if let next { button(next) }
            }
        case .shortcut(let name, let caps):
            ArisShortcutCapsButton(caps: caps, recording: handlers.recording == name, label: item.title, clearable: name != ArisDictationKey.Choice.recorderName,
                                   toggle: { handlers.record(name) }, clear: { handlers.perform(.clearShortcut(name)) })
        case .caps(let caps):
            // Raised caps say “press me”: a key that can't be changed is plain words.
            ArisFixedKey(caps: caps)
        case .slider(let key, let value, let lower, let upper, let unit, let step, let zero):
            ArisRangeSlider(value: value, range: lower...upper, label: item.title, change: { handlers.set(key, .number($0), item.title) },
                            editing: { handlers.perform(.sliding(key, $0)) }, step: step, said: ArisSliderStep.label(value, step: step, unit: unit, zero: zero))
        case .chip(let text, let tone):
            ArisChip(text: text, tone: tone)
        case .field(let key, let text, let placeholder, let action):
            HStack(spacing: 8) {
                ArisTextField(placeholder: placeholder, text: Binding(get: { text }, set: { handlers.set(key, .text($0), item.title) }), width: 130) {
                    if action.enabled { handlers.perform(action.action) }
                }
                button(action)
            }
        case .trailing, .custom:
            handlers.custom(item) ?? AnyView(EmptyView())
        }
    }

    private func button(_ b: ArisSettingButton) -> some View {
        ArisSettingsButton(title: b.title, kind: b.kind, enabled: b.enabled) { handlers.perform(b.action) }
    }
}
