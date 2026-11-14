//
//  ArisSettingsSheets.swift
//  Aris
//
//  The redesigned window's own sheets, in the modal host's frame: 쓰는 언어 (every language Aris can listen for,
//  searchable, the ones on first, one always on: the measured language dialog), the question after 앱 언어 changes
//  (settings-redesign.html `sheetHTML`), and 팀원 빼기.
//

import SwiftUI

/// 쓰는 언어's picker, the measured language dialog (ArisMenuLook, drawn by the modal host at 340, r16): the title and
/// its line, a search field, how many are on, and the list, the ones on first, each with a box. One always stays on
/// (a tap on the last one does nothing, as the measured one). A click outside or Esc closes it; there is no button.
struct ArisLanguageSheet: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    @Environment(\.arisSettingsStill) private var still
    @Binding var languages: [String]
    let close: () -> Void
    @State private var filter = ""
    @FocusState private var searching: Bool

    private var listed: [ArisLanguage] {
        let text = ArisSettingsIndex.normalized(filter)
        let all = ArisLanguages.all.filter { text.isEmpty || ArisSettingsIndex.normalized($0.name).contains(text) || ArisSettingsIndex.normalized($0.native).contains(text) }
        return all.filter { languages.contains($0.code) } + all.filter { !languages.contains($0.code) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(w("쓰는 언어")).font(.system(size: ArisMenuLook.sheetTitleFont, weight: .semibold)).foregroundStyle(palette.title)
                Text(w("말할 때 찾을 언어를 켜요. 하나는 꼭 켜 두세요.")).font(.system(size: ArisMenuLook.sheetLineFont)).foregroundStyle(palette.desc)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, ArisMenuLook.sheetLineGap)
                search.padding(.top, ArisMenuLook.sheetSearchGap)
            }
            .padding(.horizontal, ArisMenuLook.sheetPadding).padding(.top, ArisMenuLook.sheetPadding).padding(.bottom, ArisMenuLook.sheetHeadBottom)
            Text(w("\(languages.count)개 선택됨")).font(.system(size: ArisMenuLook.countFont, weight: .medium)).textCase(.uppercase)
                .tracking(ArisMenuLook.countFont * ArisMenuLook.labelTracking).foregroundStyle(palette.ink3)
                .padding(.horizontal, ArisMenuLook.sheetPadding).padding(.vertical, ArisMenuLook.countPaddingV)
            Group {
                if still {
                    VStack(alignment: .leading, spacing: ArisMenuLook.listSpacing) { ForEach(listed.prefix(6)) { language in row(language) } }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: ArisMenuLook.listSpacing) { ForEach(listed) { language in row(language) } }
                    }
                    .scrollIndicators(.never)
                }
            }
            .padding(.horizontal, ArisMenuLook.listPaddingH).padding(.vertical, ArisMenuLook.listPaddingV)
            // Under 70% of the window's 680 with the head above it.
            .frame(height: 316, alignment: .top)
        }
        .onAppear { if !still { searching = true } }
        .onExitCommand(perform: close)
    }

    /// `pl-9 pr-3 py-2 text-xs rounded-lg`: gray-50 on a gray-200 line (gray-100 while typing), the dark field with
    /// its control line (#222327 and the hover line while typing), a 14-pt glass 12 in.
    private var search: some View {
        let dark = palette.dark, shape = RoundedRectangle(cornerRadius: ArisMenuLook.searchRadius, style: .continuous)
        let fill = searching ? (dark ? Color(arisHex: 0x222327) : Color(arisHex: 0xf3f4f6)) : ArisMenuLook.searchFill.color(dark)
        let line = searching && dark ? Color(arisHex: 0xdfe2e8, 0x21 / 255.0) : ArisMenuLook.searchBorder.color(dark)
        return Group {
            if still {
                Text(filter.isEmpty ? w("언어 검색") : filter).foregroundStyle(filter.isEmpty ? palette.ink3 : palette.title).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("", text: $filter, prompt: Text(w("언어 검색")).foregroundColor(palette.ink3))
                    .textFieldStyle(.plain).foregroundStyle(palette.title).focused($searching)
            }
        }
        .font(.system(size: ArisMenuLook.searchFont))
        .padding(.leading, ArisMenuLook.searchLeading).padding(.trailing, 12)
        .frame(height: ArisMenuLook.searchHeight)
        .background(shape.fill(fill))
        .overlay(shape.strokeBorder(line, lineWidth: 1))
        .overlay(alignment: .leading) {
            ArisLineIcon("magnifyingglass", size: 13).foregroundStyle(palette.ink3)
                .frame(width: ArisMenuLook.searchIcon, height: ArisMenuLook.searchIcon).padding(.leading, ArisMenuLook.searchIconInset).allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.15), value: searching)
        .accessibilityLabel(w("언어 검색"))
    }

    private func row(_ language: ArisLanguage) -> some View {
        ArisLanguageOption(language: language, on: languages.contains(language.code)) {
            if languages.contains(language.code) {
                if languages.count > 1 { languages.removeAll { $0 == language.code } }
            } else {
                languages.append(language.code)
            }
        }
    }
}

/// One language: its box, its own name and under it its English one; lit while on, a lighter fill under the pointer.
private struct ArisLanguageOption: View {
    @Environment(\.arisPalette) private var palette
    let language: ArisLanguage
    let on: Bool
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        let dark = palette.dark, shape = RoundedRectangle(cornerRadius: ArisMenuLook.rowRadius, style: .continuous)
        Button(action: toggle) {
            HStack(spacing: ArisMenuLook.optionGap) {
                box
                VStack(alignment: .leading, spacing: 0) {
                    Text(language.native).font(.system(size: ArisMenuLook.optionNameFont, weight: .medium)).foregroundStyle(palette.title).lineLimit(1)
                    Text(language.name).font(.system(size: ArisMenuLook.optionNativeFont)).foregroundStyle(palette.ink3).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, ArisMenuLook.rowPaddingH).padding(.vertical, ArisMenuLook.rowPaddingV)
            .background(shape.fill(on ? ArisMenuLook.optionOn.color(dark) : hovering ? ArisMenuLook.optionHover.color(dark) : .clear))
            .contentShape(shape)
            .animation(.easeInOut(duration: 0.15), value: hovering)
            .animation(.easeInOut(duration: 0.15), value: on)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(language.native)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// `w-4 h-4 rounded`: on, a fill, a line and an inset shade with a 10-pt check; off, a line only.
    private var box: some View {
        let dark = palette.dark, shape = RoundedRectangle(cornerRadius: ArisMenuLook.boxRadius, style: .continuous)
        return ZStack {
            if on {
                shape.fill(ArisMenuLook.boxOnFill.color(dark))
                ForEach(Array((dark ? ArisMenuLook.boxShadeDark : ArisMenuLook.boxShadeLight).enumerated()), id: \.offset) { _, shade in
                    ArisInsetShade(shape: shape, shadow: shade)
                }
                shape.strokeBorder(ArisMenuLook.boxOnBorder.color(dark), lineWidth: 1)
                ArisLineIcon("checkmark", size: 9, stroke: 2.5).foregroundStyle(ArisMenuLook.boxCheckInk.color(dark))
                    .frame(width: ArisMenuLook.boxCheck, height: ArisMenuLook.boxCheck)
            } else {
                shape.strokeBorder((hovering ? ArisMenuLook.boxOffBorderHover : ArisMenuLook.boxOffBorder).color(dark), lineWidth: 1)
            }
        }
        .frame(width: ArisMenuLook.box, height: ArisMenuLook.box)
    }
}

struct ArisRestartSheet: View {
    let later: () -> Void
    let restart: () -> Void

    var body: some View {
        ArisSheetFrame(title: "언어를 바꾸려면 다시 시작해야 해요", subtitle: "지금 다시 시작하면 바로 바뀌어요.", onClose: later) {
            EmptyView()
        } footer: {
            ArisPillButton(title: "나중에", kind: .ghost, action: later)
            ArisPillButton(title: "지금 다시 시작", action: restart)
        }
    }
}

struct ArisRemoveMateSheet: View {
    let name: String
    let cancel: () -> Void
    let remove: () -> Void

    var body: some View {
        ArisSheetFrame(title: "\(name) 빼기", subtitle: "이 팀원의 이름과 캐릭터가 지워져요.", onClose: cancel) {
            EmptyView()
        } footer: {
            ArisPillButton(title: "취소", kind: .ghost, action: cancel)
            ArisPillButton(title: "빼기", kind: .solidRed, action: remove)
        }
    }
}
