//
//  ArisNotchClosedParts.swift
//  Aris
//
//  What the closed notch draws for music and for the Now Playing fallback notice: the notice card, the music pill
//  (artwork in the left ear, bars in the right, title and artist beside the camera while the inline peek widens it),
//  and the peek row under the notch.
//

import AppKit
import Defaults
import SwiftUI

/// "Now Playing had to fall back": an orange warning, the title and what Aris uses instead.
struct ArisNowPlayingNoticeCard: View {
    let notice: NowPlayingFallbackNotice

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.orange)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text(notice.subtitle).font(.caption).foregroundStyle(.white.opacity(0.62))
            }
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(width: 330)
        .frame(minHeight: 58)
        .onAppear {
            guard ArisNowPlaying.shared.markNowPlayingNoticePresented(notice.id) else { return }
            let text = "\(String(localized: notice.title)). \(String(localized: notice.subtitle))."
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }
}

/// The closed notch while music plays: artwork | camera | bars.
struct ArisMusicPill: View {
    @ObservedObject private var music = ArisNowPlaying.shared
    @Default(.coloredSpectrogram) private var colouredBars

    let notchWidth: CGFloat
    let height: CGFloat
    let inlineExpanded: Bool

    static let inlineWidth: CGFloat = 110
    /// The band's width on this display (ArisVNotch), from the notch.
    @Environment(\.arisBandBody) private var bandBody

    var body: some View {
        let ear = ArisBand.earWidth(notchWidth: notchWidth, body: bandBody)
        let slot = 2 * ArisBand.markCenter
        HStack(spacing: 0) {
            Image(nsImage: music.albumArt)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .frame(width: slot, height: height)
                .frame(width: ear, alignment: .leading)
            centre
            MusicVisualizer(isPlaying: music.isPlaying, tintColor: barTint)
                .frame(width: 18, height: 12)
                .frame(width: slot, height: height)
                .frame(width: ear, alignment: .trailing)
        }
        .frame(height: height)
    }

    private var centre: some View {
        ZStack {
            // The camera's place, left to the notch's own surface (as ArisBandRow does).
            Color.clear
            if inlineExpanded {
                HStack(spacing: 0) {
                    MarqueeText(music.songTitle, color: textTint, delayDuration: 0.4, frameWidth: Self.inlineWidth)
                        .frame(width: Self.inlineWidth, alignment: .leading)
                    Spacer(minLength: 0)
                    Text(music.artistName)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(textTint)
                        .frame(width: Self.inlineWidth, alignment: .trailing)
                }
            }
        }
        .frame(width: notchWidth + (inlineExpanded ? 2 * Self.inlineWidth : 0), height: height)
    }

    private var barTint: Color {
        colouredBars ? Color(nsColor: music.avgColor).ensureMinimumBrightness(factor: 0.5) : .gray
    }

    private var textTint: Color {
        colouredBars ? Color(nsColor: music.avgColor) : .gray
    }
}

/// The standard peek under the closed notch: a note and "title - artist".
struct ArisMusicPeekRow: View {
    @ObservedObject private var music = ArisNowPlaying.shared
    @Default(.playerColorTinting) private var tinting
    let width: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "music.note")
            MarqueeText("\(music.songTitle) - \(music.artistName)", color: tint, delayDuration: 1, frameWidth: max(0, width - 30))
                .offset(y: 1)
        }
        .foregroundStyle(.gray)
        .padding(.top, 1)
        .padding(.bottom, 9)
    }

    private var tint: Color {
        tinting ? Color(nsColor: music.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray
    }
}
