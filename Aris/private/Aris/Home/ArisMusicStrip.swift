//
//  ArisMusicStrip.swift
//  Aris
//
//  What's playing, as one slim row above the input: art, title and artist, previous / play / next, and a hairline
//  of progress.
//

import SwiftUI

struct ArisMusicStrip: View {
    @ObservedObject private var music = ArisNowPlaying.shared

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: music.albumArt)
                .resizable().scaledToFill()
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(music.songTitle.isEmpty ? ArisUIWords.text("재생 중인 곡 없음", "Nothing playing") : music.songTitle)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(ArisGlass.text)
                Text(music.artistName).font(.system(size: 11.5)).foregroundStyle(ArisGlass.secondaryText)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            control("backward.fill", size: 11) { music.previousTrack() }
            control(music.isPlaying ? "pause.fill" : "play.fill", size: 14) { music.togglePlay() }
            control("forward.fill", size: 11) { music.nextTrack() }
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .background(alignment: .bottom) { progress }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.05)))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func control(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold)).foregroundStyle(ArisGlass.text)
                .frame(width: 26, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            GeometryReader { geometry in
                let share = music.songDuration > 0 ? min(1, music.estimatedPlaybackPosition() / music.songDuration) : 0
                Rectangle().fill(.white.opacity(0.35)).frame(width: geometry.size.width * share, height: 1.5)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}
