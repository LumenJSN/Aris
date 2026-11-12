//
//  ArisOnboardingTalk.swift
//  Aris
//
//  Aris speaks first, from the notch (mockups/onboarding2/js/talk.js, css/scenes.css .talk, glass.css .composer):
//  captions in the transcript style (clamp(22, 2vw, 28) / 1.42, −.018 em, white .88, at most 920 wide, 142
//  above the middle), each sentence resolving 150 ms after its voice starts, 560 ms blur → 0; the question on its own
//  line. Then the name pill: the intro pill (52 high, frosted light glass on the dark veil), 360 wide, entering
//  from {opacity 0, y 16, scale .985, blur 6} over .5 s.
//

import SwiftUI

struct ArisOnboardingTalkView: View {
    @ObservedObject var guide: ArisOnboardingGuide
    let now: Double

    private typealias M = ArisOnboardingMotion

    var body: some View {
        let w = guide.screenSize.width, h = guide.screenSize.height
        let top = h / 2 - 142, clear = guide.captionsClearAt.map { M.exit(M.span(now, $0, $0 + (guide.reduced ? 0.12 : 0.24))) } ?? 0
        ZStack(alignment: .top) {
            if let spoken = guide.spoken {
                captions(spoken.captions(synthStarts: guide.audio?.synthStarts ?? []), width: min(920, w * 0.88))
                    .opacity(1 - clear)
                    .blur(radius: 6 * clear)
            }
            if let shown = guide.composerAt {
                composer(shown: shown)
                    .opacity(1 - clear)
                    .padding(.top, 198)
            }
        }
        .frame(width: w)
        .offset(y: top)
        .frame(width: w, height: h, alignment: .topLeading)
    }

    // MARK: - Captions

    private func captions(_ c: ArisCaptions, width: CGFloat) -> some View {
        let size = min(28, max(22, guide.screenSize.width * 0.02))
        let lines = c.sentences.count > 1 ? [Array(c.sentences.indices.dropLast()), [c.sentences.count - 1]] : [Array(c.sentences.indices)]
        return VStack(spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, indices in
                indices.reduce(Text("")) { text, i in
                    let p = c.progress(i, at: now)
                    return text + Text((i == indices.first ? "" : " ") + c.sentences[i]).foregroundColor(.white.opacity(0.88 * p))
                }
                .font(.system(size: size, weight: .regular))
                .tracking(-0.018 * size)
                .lineSpacing(size * 0.42)
                .frame(minHeight: size * 1.42)
                .blur(radius: guide.reduced ? 0 : 8 * (1 - indices.map { c.progress($0, at: now) }.min()!))
            }
        }
        .multilineTextAlignment(.center)
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: size * 1.42 * 2, alignment: .top)
        .shadow(color: .black.opacity(0.4), radius: 10, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(c.sentences.joined(separator: " "))
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - The name

    private func composer(shown: Double) -> some View {
        let p = guide.reduced ? M.span(now, shown, shown + 0.15) : M.settle(M.span(now, shown + 0.03, shown + 0.53))
        return VStack(alignment: .leading, spacing: 12) {
            ArisNamePill(guide: guide)
            Text(guide.nameError ? ArisOnboardingCopy.nameMissing : " ")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.58))
                .padding(.leading, 20)
                .accessibilityHidden(!guide.nameError)
        }
        .frame(width: 360)
        .opacity(p)
        .scaleEffect(guide.reduced ? 1 : 0.985 + 0.015 * p)
        .offset(y: guide.reduced ? 0 : 16 * (1 - p))
        .blur(radius: guide.reduced ? 0 : 6 * (1 - p))
    }
}

/// The pill itself: one field and the send button (32, the dark star-ink circle with a corner-highlight ring).
private struct ArisNamePill: View {
    @ObservedObject var guide: ArisOnboardingGuide
    @FocusState private var focused: Bool
    @Environment(\.arisOnboardingStill) private var still

    private var empty: Bool { ArisCaptions.cleanName(guide.nameText).isEmpty }

    var body: some View {
        HStack(spacing: 8) {
            if still {
                Text(guide.nameText.isEmpty ? ArisOnboardingCopy.namePlaceholder : guide.nameText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(guide.nameText.isEmpty ? Color(.sRGB, red: 76 / 255, green: 81 / 255, blue: 92 / 255, opacity: 0.55) : ArisOBColor.hex(0x24272e))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
            TextField("", text: $guide.nameText, prompt: Text(ArisOnboardingCopy.namePlaceholder).foregroundColor(Color(.sRGB, red: 76 / 255, green: 81 / 255, blue: 92 / 255, opacity: 0.55)))
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium))
                .tracking(-0.075)
                .foregroundStyle(ArisOBColor.hex(0x24272e))
                .focused($focused)
                .disabled(guide.nameSent)
                .onSubmit { guide.submitName() }
                .onChange(of: guide.nameText) { _, text in
                    if text.count > 24 { guide.nameText = String(text.prefix(24)) }
                    guide.nameError = false
                }
                .accessibilityLabel(ArisOnboardingCopy.nameLabel)
            }
            Button { guide.submitName() } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ArisOBColor.hex(0xf6e7b4))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(ArisOBColor.hex(0x1d1a12)))
                    .overlay(Circle().strokeBorder(RadialGradient(colors: [.white.opacity(0.35), .white.opacity(0.1), .clear], center: .topLeading,
                                                                  startRadius: 0, endRadius: 20), lineWidth: 1.5))
                    .overlay(Circle().strokeBorder(.white.opacity(0.1), lineWidth: 1.5))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(empty || guide.nameSent)
            .opacity(empty || guide.nameSent ? 0.32 : 1)
            .accessibilityLabel(ArisOnboardingCopy.send)
        }
        .padding(.leading, 20)
        .padding(.trailing, 10)
        .frame(width: 360, height: 52)
        .background {
            let shape = Capsule()
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).clipShape(shape)
                shape.fill(focused || still ? ArisOBColor.hexa(0xe2e5edd6) : ArisOBColor.hexa(0xdcdfe8c9))
                shape.fill(LinearGradient(colors: [ArisOBColor.hexa(0xffffff2e), .clear], startPoint: .top, endPoint: .center))
                shape.strokeBorder(focused ? ArisOBColor.hexa(0xffffff80) : ArisOBColor.hexa(0xffffff47), lineWidth: 1)
            }
            .shadow(color: ArisOBColor.hexa(0x070a1233), radius: 17, y: 16)
        }
        .environment(\.colorScheme, .light)
        .animation(.easeOut(duration: 0.22), value: focused)
        .onAppear { focused = true }
    }
}
