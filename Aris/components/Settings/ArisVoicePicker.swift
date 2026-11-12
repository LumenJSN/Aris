//
//  ArisVoicePicker.swift
//  Aris
//
//  목소리 · 언어 › 목소리 with an ElevenLabs key: a menu button naming the voice, opening the account's voices
//  (fetched once per run, own ones first), each with a free preview. The list is the window's dropdown look
//  (r16, items r8 9 × 12, a check on the chosen voice) in a popover, because it loads and plays.
//

import AVFoundation
import Defaults
import SwiftUI

struct ArisVoiceMenu: View {
    @Environment(\.arisWords) private var w
    @Default(.arisVoiceID) private var voiceID
    @Default(.arisVoiceName) private var voiceName
    @ObservedObject private var nav = ArisSettingsNav.shared
    @State private var picking = false
    let changed: (String) -> Void

    var body: some View {
        ArisAISelect(face: ArisAISelectFace(label: voiceName.isEmpty ? "목소리 고르기" : voiceName), label: "목소리", width: nil, minWidth: ArisAISelect.pageWidth,
                     expanded: picking) { _ in picking = true }
            .popover(isPresented: $picking, arrowEdge: .bottom) {
                ArisVoicePicker { name in
                    picking = false
                    changed(name)
                }
            }
            .onChange(of: nav.sheet) { _, sheet in picking = sheet == "voice" }
            // The saved name can be stale (the default's library name, or a voice renamed in the account).
            .task {
                if let match = await ArisVoicePicker.voices()?.first(where: { $0.id == voiceID }), match.name != voiceName {
                    voiceName = match.name
                }
            }
            .accessibilityLabel(w("목소리"))
            .accessibilityValue(voiceName)
    }
}

struct ArisVoicePicker: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    @Default(.arisVoiceID) private var voiceID
    @Default(.arisVoiceName) private var voiceName
    let done: (String) -> Void
    @State private var voices: [ArisElevenLabs.Voice]?
    @State private var failed = false
    @State private var playing: String?
    @State private var player: AVPlayer?
    private static var cache: [ArisElevenLabs.Voice]?

    var body: some View {
        Group {
            if let voices {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(voices, id: \.id) { voice in ArisVoiceRow(voice: voice, chosen: voice.id == voiceID, playing: playing == voice.id,
                                                                          preview: { preview(voice) }, pick: { pick(voice) }) }
                    }
                    .padding(8)
                }
                .scrollIndicators(.never)
            } else {
                Text(w(failed ? "목소리 목록을 못 받았어요" : "목소리를 불러오는 중…"))
                    .font(.system(size: 12)).foregroundStyle(palette.desc).frame(maxWidth: .infinity).padding(28)
            }
        }
        .frame(width: 320, height: voices == nil ? 90 : 340)
        .background(palette.menu)
        .task { await load() }
        .onDisappear { player?.pause() }
    }

    private func pick(_ voice: ArisElevenLabs.Voice) {
        voiceID = voice.id
        voiceName = voice.name
        done(voice.name)
    }

    private func preview(_ voice: ArisElevenLabs.Voice) {
        player?.pause()
        guard playing != voice.id, let url = voice.previewURL else { playing = nil; return }
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        player?.play()
        playing = voice.id
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
            MainActor.assumeIsolated { if playing == voice.id { playing = nil } }
        }
    }

    private func load() async {
        guard let list = await Self.voices() else { failed = true; return }
        voices = list
    }

    /// The account's voices, fetched once per run.
    static func voices() async -> [ArisElevenLabs.Voice]? {
        if let cache { return cache }
        guard let key = ArisElevenLabs.loadKey(), let list = await ArisElevenLabs.voiceList(key: key) else { return nil }
        cache = list
        return list
    }
}

private struct ArisVoiceRow: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let voice: ArisElevenLabs.Voice
    let chosen: Bool
    let playing: Bool
    let preview: () -> Void
    let pick: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: preview) {
                Image(systemName: playing ? "stop.fill" : "play.fill").font(.system(size: 10)).foregroundStyle(palette.icon)
                    .frame(width: 26, height: 26).background(Circle().fill(palette.chip))
            }
            .buttonStyle(ArisPressScale(scale: 0.95))
            .disabled(voice.previewURL == nil)
            .accessibilityLabel(w(playing ? "\(voice.name) 그만 듣기" : "\(voice.name) 들어 보기"))
            Button(action: pick) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(voice.name).font(.system(size: 14, weight: .medium)).foregroundStyle(palette.title).lineLimit(1)
                        if !voice.detail.isEmpty { Text(voice.detail).font(.system(size: 11.5)).foregroundStyle(palette.desc).lineLimit(1) }
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.title).opacity(chosen ? 1 : 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(chosen ? .isSelected : [])
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? palette.menuHover : .clear))
        .onHover { hovering = $0 }
    }
}
