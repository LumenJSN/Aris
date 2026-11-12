//
//  ArisReaderView.swift
//  Aris
//
//  The owner's 2A (mockups/done-and-reader.html, .reader): the Aris board grown up into a reader. A dark glass panel, 22
//  round (fill rgba(0,0,6,.93) over a blur, ring .09, a .06 highlight on top); a bar with the star, the title (13.5/600
//  .94) and when and where it was saved (10.5, .43), then 복사 · 메모에 저장 · 파일로 열기 and close (28 high, 8 round,
//  white .08 → .14, 12/600); under a hairline, the markdown as styled text in a scroller whose edges fade (14 on top,
//  30 below). It comes in from .965 on the opening clock (280 ms) and leaves to .965, 6 up, over 200 ms. Never HTML:
//  links are words (mono, pale blue) whose click copies the address; nothing is opened or loaded.
//

import AppKit
import SwiftUI

/// What the reader's buttons do. A nil action hides its button (an answer or the board has no file).
struct ArisReaderActions {
    var copy: () -> Void
    /// Nil when it worked, else what went wrong.
    var note: (() async -> String?)?
    var openFile: (() async -> Bool)?
    var copyLink: (URL) -> Void
    var close: () -> Void
}

/// In or out: the panel's present and dismiss.
@MainActor
final class ArisReaderPresence: ObservableObject {
    @Published var shown = false
}

struct ArisReaderView: View {
    let document: ArisReaderDocument
    let actions: ArisReaderActions
    @ObservedObject var presence: ArisReaderPresence
    var now = Date()

    @State private var linkCopied = false

    static let size = CGSize(width: 620, height: 428)
    /// The most the panel grows to for a document a little taller than it (ArisBoardContent.readerHeight).
    static let tallest: CGFloat = 640
    /// The bar and its hairline, above the scroller.
    static let barHeight: CGFloat = 55
    static let bodyInsets = EdgeInsets(top: 18, leading: 26, bottom: 28, trailing: 26)
    /// Documents with more blocks than this are not measured: they scroll in the panel at its own height.
    static let measuredBlocks = 40

    /// What the whole document takes at `width`, bar included; nil for one too long to be worth laying out twice.
    @MainActor static func neededHeight(_ document: ArisReaderDocument, width: CGFloat) -> CGFloat? {
        guard document.blocks.count <= measuredBlocks else { return nil }
        let body = NSHostingView(rootView: ArisReaderBody(document: document).padding(bodyInsets).frame(width: width))
        return body.fittingSize.height.rounded(.up) + barHeight
    }
    static let radius: CGFloat = 22
    static let present = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.28)
    static let dismiss = Animation.timingCurve(0.45, 0, 0.55, 1, duration: 0.2)

    var body: some View {
        VStack(spacing: 0) {
            bar
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            ArisReaderScroll {
                ArisReaderBody(document: document)
                    .padding(Self.bodyInsets)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color(.sRGB, red: 0, green: 0, blue: 6.0 / 255, opacity: 0.93)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous).strokeBorder(.white.opacity(0.09), lineWidth: 1)
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous).strokeBorder(
                LinearGradient(stops: [.init(color: .white.opacity(0.06), location: 0), .init(color: .clear, location: 0.08)],
                               startPoint: .top, endPoint: .bottom), lineWidth: 1)
                .padding(1)
        }
        .scaleEffect(presence.shown ? 1 : 0.965, anchor: .top)
        .offset(y: presence.shown ? 0 : -6)
        .opacity(presence.shown ? 1 : 0)
        .environment(\.openURL, OpenURLAction { url in
            // Never opened: the words may come from web pages or mail. The address goes on the clipboard.
            actions.copyLink(url)
            withAnimation(ArisReaderButton.swap) { linkCopied = true }
            Task { @MainActor in
                try? await Task.sleep(for: ArisReaderButton.doneFor)
                withAnimation(ArisReaderButton.swap) { linkCopied = false }
            }
            return .handled
        })
        .preferredColorScheme(.dark)
    }

    private var bar: some View {
        HStack(spacing: 10) {
            ArisCharacterView(size: 18, isAris: true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: document.title)
                    .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1).truncationMode(.tail)
                ArisSwapText(text: subtitle, font: .system(size: 10.5), color: .white.opacity(0.43))
            }
            .frame(minWidth: 0)
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                ArisReaderButton(symbol: "square.on.square", label: ArisUIWords.text("복사", "Copy")) {
                    actions.copy()
                    return ArisUIWords.text("복사했어요", "Copied")
                }
                if let note = actions.note {
                    ArisReaderButton(symbol: "note.text", label: ArisUIWords.text("메모에 저장", "Save to Notes")) { await note() ?? ArisUIWords.text("메모에 넣었어요", "Saved to Notes") }
                }
                if let openFile = actions.openFile {
                    ArisReaderButton(symbol: "arrow.up.right.square", label: ArisUIWords.text("파일로 열기", "Open as a file")) {
                        await openFile() ? ArisUIWords.text("텍스트 편집기에서 열어요", "Opening in TextEdit") : ArisUIWords.text("열지 못했어요", "Couldn't open it")
                    }
                }
                ArisReaderButton(symbol: "xmark", label: nil) { actions.close(); return nil }
                    .help(ArisUIWords.text("닫기", "Close"))
            }
        }
        .padding(EdgeInsets(top: 12, leading: 18, bottom: 10, trailing: 12))
    }

    private var subtitle: String {
        if linkCopied { return ArisUIWords.text("링크를 복사했어요 · 열지 않아요", "Link copied · not opened") }
        guard let modified = document.modified else { return ArisUIWords.text("답 전체", "The whole answer") }
        let folder = document.file?.contains("/Documents/Aris/") == false ? ArisUIWords.text("Aris 폴더", "the Aris folder") : ArisReaderDocument.folderLabel
        return ArisReaderDocument.subtitle(modified: modified, now: now, folder: folder)
    }
}

/// The mockup's .lg: icon 13 at .85 and 12/600 words, 28 high, 8 round, white .08 (.14 on hover), an inner ring .05
/// and a .06 highlight; it presses to .97 (ArisPressStyle). After a click its words change for 1.5 s (ArisUIWords.text("복사했어요", "Copied")), blurring across.
struct ArisReaderButton: View {
    let symbol: String
    let label: String?
    /// Runs the action; returns the words to show for a moment, or nil.
    let action: () async -> String?

    @State private var hovering = false
    @State private var said: String?

    static let doneFor: Duration = .milliseconds(1500)
    /// .lg .w: opacity and a 2-point blur over 160 ms.
    static let swap = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.16)
    private static let hover = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.14)

    var body: some View {
        Button {
            Task { @MainActor in
                guard let words = await action() else { return }
                withAnimation(Self.swap) { said = words }
                try? await Task.sleep(for: Self.doneFor)
                withAnimation(Self.swap) { said = nil }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11.5, weight: .semibold)).frame(width: 13, height: 13).opacity(0.85)
                if let label {
                    ArisSwapText(text: said ?? label, font: .system(size: 12, weight: .semibold), color: .white.opacity(0.9))
                }
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, label == nil ? 0 : 11)
            .frame(width: label == nil ? 28 : nil, height: 28)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(hovering ? 0.14 : 0.08))
                RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.05), lineWidth: 1)
                RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(
                    LinearGradient(stops: [.init(color: .white.opacity(0.06), location: 0), .init(color: .clear, location: 0.1)],
                                   startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(ArisPressStyle())
        .fixedSize()
        .onHover { hovering = $0 }
        .animation(Self.hover, value: hovering)
    }
}

/// Words that blur across to new words in place (the mockup's relabel: out to 0 and a 2-point blur, then in).
struct ArisSwapText: View {
    let text: String
    let font: Font
    let color: Color

    var body: some View {
        Text(verbatim: text).font(font).foregroundStyle(color).lineLimit(1)
            .id(text)
            .transition(.modifier(active: ArisBlurFade(amount: 1), identity: ArisBlurFade(amount: 0)))
    }
}

struct ArisBlurFade: ViewModifier {
    let amount: Double
    func body(content: Content) -> some View { content.opacity(1 - amount).blur(radius: 2 * amount) }
}

/// The reader's scroller: hidden indicators, its edges faded 14 points on top and 30 below (.fadebox).
struct ArisReaderScroll<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(.vertical) {
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .mask {
            GeometryReader { geometry in
                let height = max(geometry.size.height, 60)
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 14 / height),
                                       .init(color: .black, location: 1 - 30 / height), .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
    }
}
