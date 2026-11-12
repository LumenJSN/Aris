//
//  ArisSettingsSheets.swift
//  Aris
//
//  The redesigned window's own sheets (settings-redesign.html `sheetHTML`), in the modal host's frame: 언어 추가 (every
//  language Aris can listen for, searchable, the ones on first, one always on), the question after 앱 언어 changes,
//  and 팀원 빼기.
//

import SwiftUI

struct ArisLanguageSheet: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisSettingsStill) private var still
    @Binding var languages: [String]
    let close: () -> Void
    @State private var filter = ""

    private var listed: [ArisLanguage] {
        let text = ArisSettingsIndex.normalized(filter)
        let all = ArisLanguages.all.filter { text.isEmpty || ArisSettingsIndex.normalized($0.name).contains(text) || ArisSettingsIndex.normalized($0.native).contains(text) }
        return all.filter { languages.contains($0.code) } + all.filter { !languages.contains($0.code) }
    }

    var body: some View {
        ArisSheetFrame(title: "언어 추가", subtitle: "말할 때 찾을 언어를 켜요. 하나는 꼭 켜 두세요.", onClose: close) {
            VStack(alignment: .leading, spacing: 8) {
                ArisTextField(placeholder: "언어 검색", text: $filter)
                Group {
                    if still {
                        VStack(alignment: .leading, spacing: 0) { ForEach(listed.prefix(7)) { language in row(language) } }
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(listed) { language in row(language) }
                            }
                        }
                        .scrollIndicators(.never)
                    }
                }
                .frame(height: 300, alignment: .top)
            }
            .padding(.top, 12)
        } footer: {
            ArisPillButton(title: "완료", action: close)
        }
    }

    private func row(_ language: ArisLanguage) -> some View {
        let on = languages.contains(language.code)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(language.native).font(.system(size: 13)).foregroundStyle(palette.title)
                Text(language.name).font(.system(size: 11.5)).foregroundStyle(palette.ink3)
            }
            Spacer(minLength: 8)
            ArisSwitch(isOn: on, enabled: !(on && languages.count == 1), label: language.native) {
                if on { languages.removeAll { $0 == language.code } } else { languages.append(language.code) }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
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
