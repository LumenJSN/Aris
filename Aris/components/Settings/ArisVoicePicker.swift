//
//  ArisVoicePicker.swift
//  Aris
//
//  목소리 · 언어 › 목소리 with an ElevenLabs key: a menu button naming the voice, opening the account's voices
//  (fetched once per run, own ones first), each with a free preview. The button is the settings rows' select; the
//  list has the window's dropdown rows (ArisMenuLook: r8, 10 × 12, 14/500 over 11, a 16-pt accent check on the chosen
//  voice) in a popover, because it loads and plays.
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
        ArisSettingSelect(choice: voiceName.isEmpty ? "목소리 고르기" : voiceName, label: "목소리") { _ in picking = true }
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
                ArisLineIcon(playing ? "stop.fill" : "play.fill", size: 12).foregroundStyle(palette.icon)
                    .frame(width: 26, height: 26).background(Circle().fill(palette.chip))
            }
            .buttonStyle(ArisPressScale(scale: 0.95))
            .disabled(voice.previewURL == nil)
            .accessibilityLabel(w(playing ? "\(voice.name) 그만 듣기" : "\(voice.name) 들어 보기"))
            Button(action: pick) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(voice.name).font(.system(size: 14, weight: .medium)).foregroundStyle(palette.title).lineLimit(1)
                        if !voice.detail.isEmpty { Text(voice.detail).font(.system(size: 11)).foregroundStyle(palette.desc).lineLimit(1) }
                    }
                    Spacer(minLength: 4)
                    // The measured voice menu's check: 16 square, in the accent.
                    ArisLineIcon("checkmark", size: 14).foregroundStyle(palette.accent)
                        .frame(width: ArisMenuLook.checkBox, height: ArisMenuLook.checkBox).opacity(chosen ? 1 : 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(chosen ? .isSelected : [])
        }
        .padding(.horizontal, ArisMenuLook.rowPaddingH).padding(.vertical, ArisMenuLook.rowPaddingV)
        .background(RoundedRectangle(cornerRadius: ArisMenuLook.rowRadius, style: .continuous).fill(hovering ? ArisMenuLook.rowHover.color(palette.dark) : .clear))
        .onHover { hovering = $0 }
    }
}
