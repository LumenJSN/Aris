//
//  ArisComposer.swift
//  Aris
//
//  The open notch's bottom row: a white-6% pill, radius 19, 15-point type and
//  "Type or hold [option] [space] to speak" with the keys drawn as keycaps. It grows with what you type, one to three
//  lines (lines·22 + 16) over 340 ms, then scrolls. Return sends the words to Aris like speech; files given to Aris ride
//  along as chips. Hovering takes nothing; a click on it brings Aris forward to type (ArisPanelKeys).
//

import AppKit
import SwiftUI

struct ArisComposer: View {
    @ObservedObject private var aris = ArisController.shared
    @ObservedObject private var attachments = ArisAttachments.shared
    /// Re-draws this view when the hidden look changes (ArisSiriLookGate).
    @ObservedObject private var siriLook = ArisSiriLookGate.shared
    @State private var text = ""
    /// Set only after files are given to Aris (BUG-24a); never on hover.
    @FocusState private var focused: Bool
    /// The lines the text takes, one to three (ArisComposerLines).
    @State private var lines = 1

    /// The field's own line at 15 points (ascender, descender and leading), to count its lines from its height.
    private static let fieldLine: CGFloat = {
        let font = NSFont.systemFont(ofSize: 15)
        return font.ascender - font.descender + font.leading
    }()
    /// The placeholder at weight 450 on SF's variation axis.
    private static let hintFont = Font(ArisFont.system(15, weight: 450) as CTFont)
    /// Sets the composer's text (the preview harness only).
    static let previewDraft = Notification.Name("ArisComposer.previewDraft")

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !attachments.files.isEmpty { chips }
            ArisDropChipsView()
            if ArisSiriLookNow.on {
                // The siri look: Siri's row, a round + (choose files for Aris), the pill, a round microphone.
                ArisSiriLookFieldRow(attachHelp: ArisUIWords.text("파일 주기", "Give files"), speakHelp: ArisUIWords.text("말하기", "Speak"),
                                     attach: { ArisSiriLookAttach.choose() }, speak: { aris.startListening() }) { field }
            } else {
                field
            }
        }
        .contentShape(Rectangle())
        // The preview harness's composer states (ArisPreview), as if typed.
        .onReceive(NotificationCenter.default.publisher(for: Self.previewDraft)) { text = $0.object as? String ?? "" }
        // Files just dropped on Aris (the user's own act toward it): the composer takes the keyboard to ask what to do with
        // them (BUG-24a), through ArisPanelKeys so its panel really is key, and gives it back when it lets go (BUG-22).
        .onChange(of: attachments.files.count) { old, new in
            guard new > old else { return }
            takeKeyboard()
        }
    }

    /// The pill and its field. In the siri look it is Siri's: 36 tall for one line, the control glass, a capsule.
    private var field: some View {
        let siri = ArisSiriLookNow.on
        let radius = siri ? CGFloat(ArisSiriLook.Field.height) / 2 : ArisGlass.pillRadius
        return ZStack(alignment: .leading) {
                if text.isEmpty { hint.allowsHitTesting(false) }
                TextField("", text: $text, axis: .vertical)
                    .lineLimit(1...ArisComposerLines.maxLines)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.95))
                    .arisTextBacking(when: !text.isEmpty)
                    .focused($focused)
                    .onSubmit(send)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        let next = ArisComposerLines.lines(measured: height, lineHeight: Self.fieldLine)
                        // The height transition: 340 ms (0.45, 0, 0.55, 1), the notch growing with it.
                        if next != lines { withAnimation(ArisGlass.resize) { lines = next } }
                    }
            }
            .padding(.horizontal, 16)
            .frame(height: ArisComposerLines.height(lines: lines) - (siri ? ArisComposerLines.height(lines: 1) - CGFloat(ArisSiriLook.Field.height) : 0))
            .frame(maxWidth: .infinity)
            // Just the fill: no shadow or rim. (The siri look's is Siri's glass, rim and all.)
            .background {
                if siri {
                    ArisSiriLookGlass(shape: RoundedRectangle(cornerRadius: radius, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(ArisGlass.composerFill)
                }
            }
            // A click anywhere on the pill puts the cursor in its field: on the hint's key caps and beside the one
            // line of text too (third VM run: a click on the "option" cap focused nothing, and the typing went to the
            // window behind). A click on the field itself is the field's own, as before.
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onTapGesture { takeKeyboard(tapped: true) }
    }

    /// The composer's field takes the keyboard, through ArisPanelKeys so its panel really is key (and gives it back
    /// when it lets go).
    /// `tapped`: by a click on the pill, which counts only as the user's own press (the press monitor's rule: a click
    /// another process posted takes nothing; security review 3, L3). Files dropped on Aris are not a click.
    private func takeKeyboard(tapped: Bool = false) {
        guard let panel = NSApp.windows.first(where: { $0 is ArisNotchPanel && $0.isVisible && $0.frame.contains(NSEvent.mouseLocation) }) else { return }
        if tapped, !ArisPanelKeys.tapTakesKeyboard(in: panel) { return }
        ArisPanelKeys.take(panel)
        focused = true
    }

    /// The hint in the siri look: the same colour at .78, because it sits on lighter glass there (ArisSiriLook.Field).
    private static let siriHint = Color(red: 236 / 255, green: 239 / 255, blue: 247 / 255).opacity(ArisSiriLook.Field.arisHintInk)

    /// The composer's hint line in the app's language.
    private static var korean: Bool { !ArisUILanguage.english }

    /// The placeholder: rgb(236, 239, 247) at 62%, weight 450 and 0.2 wider than body text, with the
    /// talk keys drawn as inline keycaps.
    @ViewBuilder private var hint: some View {
        if let given = ArisPendingFiles.hint(for: attachments.files, korean: Self.korean) {
            // Files just given: the same line says they arrived and asks what to do (BUG-24a).
            Text(given).font(Self.hintFont).tracking(0.2).lineLimit(1)
                .foregroundStyle(ArisSiriLookNow.on ? Self.siriHint : Color(red: 236 / 255, green: 239 / 255, blue: 247 / 255).opacity(0.62))
                .arisTextBacking()
        } else {
            keysHint
        }
    }

    private var keysHint: some View {
        // In the app's language (QA BUG-46: the English line under a Korean UI); the keys are the talk key's.
        HStack(spacing: 5) {
            Text(Self.korean ? "입력하거나" : "Type or hold")
            ArisKeycap(label: "option")
            ArisKeycap(label: "space")
            Text(Self.korean ? "누른 채 말하기" : "to speak")
        }
        .font(Self.hintFont)
        .tracking(0.2)
        .foregroundStyle(ArisSiriLookNow.on ? Self.siriHint : Color(red: 236 / 255, green: 239 / 255, blue: 247 / 255).opacity(0.62))
        .arisTextBacking()
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(attachments.files, id: \.self) { url in
                    HStack(spacing: 5) {
                        Image(nsImage: ArisFileIcons.icon(forFile: url.path)).resizable().frame(width: 14, height: 14)
                        Text(url.lastPathComponent).font(.system(size: 11.5)).lineLimit(1).foregroundStyle(ArisGlass.text)
                        Button { attachments.remove(url) } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(Capsule().fill(.white.opacity(0.08)))
                }
            }
        }
        .frame(height: 24)
    }

    private func send() {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        aris.submitTyped(attachments.request(with: words))
        attachments.clear()
        text = ""
    }
}

/// Files dropped on "Aris한테 주기": they go with the next request, however it is asked (ArisPendingFiles), as paths
/// Aris may read.
@MainActor
final class ArisAttachments: ObservableObject {
    static let shared = ArisAttachments()

    @Published private(set) var pending = ArisPendingFiles()
    var files: [URL] { pending.files }

    /// Clears what was given once it is 5 minutes old (ArisPendingFiles.lifetime), chips and all.
    private var expiry: Task<Void, Never>?

    func add(_ urls: [URL]) {
        pending = pending.adding(urls, at: Date())
        expiry?.cancel()
        expiry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(ArisPendingFiles.lifetime + 1))
            guard !Task.isCancelled, let self, self.pending.isExpired() else { return }
            self.clear()
        }
    }

    func remove(_ url: URL) { pending = pending.removing(url) }

    func clear() { pending = pending.cleared() }

    /// The typed words, then the files they're about (none once they're too old).
    func request(with words: String) -> String {
        pending.isExpired() ? words : pending.request(with: words, contents: { ArisAttachmentText.block(for: $0, read: ArisDropModel.shared.text) })
    }

    /// The turn's words with the files (once, when they may ride along: ArisPendingFiles.taking).
    func take(into words: String, handsFree: Bool = false, shown: Bool = true) -> String {
        // Nor with a request that was edited and sent again: the chips are out of sight while its card is the editor,
        // so the files keep waiting (ArisPromptEdit; security review 7, L2).
        let shown = ArisPromptEdit.chipsInSight(notchOpen: shown, editedRequest: ArisPromptEditing.shared.takeEdit(words))
        let taken = pending.taking(into: words, handsFree: handsFree, shown: shown, contents: { ArisAttachmentText.block(for: $0, read: ArisDropModel.shared.text) })
        pending = taken.left
        return taken.text
    }
}
