//
//  ArisMemoryImportFields.swift
//  Aris
//
//  설정 › 기억 › 다른 AI에서 가져오기, steps 1 and 2: the request to copy, in the history page's transcript well (r12,
//  16 at the sides and 12 above and below, a faint fill, 14 pt on a 1.625 line), and the paste box (the same r12
//  and insets, 14 pt, white / a raised dark grey, a gray-200 edge, an inset shadow, a gray-400 edge and a 2-pt ring
//  on focus). A .txt or .md file dragged over the paste box lights its edge the way focus does.
//

import SwiftUI
import UniformTypeIdentifiers

/// The request, read only, scrolling inside its well with faded ends.
struct ArisImportWell: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisSettingsStill) private var still
    let text: String
    let height: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ArisImportMetric.radius, style: .continuous)
        Group {
            if still {
                words.frame(height: height, alignment: .top).clipped()
            } else {
                ScrollView { words.textSelection(.enabled) }.scrollIndicators(.automatic)
            }
        }
        .arisImportFadedEnds(ArisImportMetric.fieldTop)
        .frame(height: height)
        // The well: the settings window's --well (black 2.5 % / white 3 %).
        .background(shape.fill(palette.well))
        .clipShape(shape)
    }

    /// 14 pt on a 1.625 line (6 pt between lines), in the history body's grey (#666 / white 70 %, the
    /// window's description grey here).
    private var words: some View {
        Text(text).font(.system(size: 14)).lineSpacing(6).foregroundStyle(palette.desc)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ArisImportMetric.fieldSide).padding(.vertical, ArisImportMetric.fieldTop)
    }
}

/// The paste box: the export typed or pasted in, or a dropped file's text.
struct ArisImportPasteBox: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    @Environment(\.arisSettingsStill) private var still
    @Binding var text: String
    let hint: String
    let height: CGFloat
    let drop: (URL) -> Void
    @FocusState private var focused: Bool
    @State private var targeted = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ArisImportMetric.radius, style: .continuous)
        let lit = focused || targeted
        let field = ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(w(hint)).font(.system(size: 14)).foregroundStyle(palette.pasteHint)
                    .padding(.horizontal, ArisImportMetric.fieldSide).padding(.vertical, ArisImportMetric.fieldTop)
                    .allowsHitTesting(false)
            }
            editor
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        // `inset 0 1px 2px rgba(0,0,0,.05)` light, `.3` dark.
        .background(shape.fill(palette.field.shadow(.inner(color: .black.opacity(palette.dark ? 0.3 : 0.05), radius: 1, y: 1))))
        .clipShape(shape)
        .overlay(shape.strokeBorder(lit ? palette.fieldFocus : palette.fieldBorder, lineWidth: 1))
        .overlay(RoundedRectangle(cornerRadius: ArisImportMetric.radius + 2, style: .continuous)
            .stroke(lit ? palette.fieldRing : .clear, lineWidth: 2).padding(-2))
        // The field's own focus change (ArisFieldStyle): 150 ms ease-out, a colour only.
        .animation(.easeOut(duration: 0.15), value: lit)
        if still {
            field
        } else {
            field.onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in drop(url) }
                }
                return true
            }
        }
    }

    @ViewBuilder private var editor: some View {
        if still {
            Text(text).font(.system(size: 14)).lineSpacing(3).foregroundStyle(palette.title)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, ArisImportMetric.fieldSide).padding(.vertical, ArisImportMetric.fieldTop)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: height, alignment: .top).clipped()
        } else {
            // TextEditor keeps 5 pt of its own at each side of a line: 11 + 5 = 16.
            TextEditor(text: $text).font(.system(size: 14)).lineSpacing(3).foregroundStyle(palette.title)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .padding(.horizontal, ArisImportMetric.fieldSide - 5).padding(.vertical, ArisImportMetric.fieldTop)
                .accessibilityLabel(w(hint))
        }
    }
}
