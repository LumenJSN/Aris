//
//  ArisNowPlaying.swift
//  Aris
//
//  What's playing, for the notch's music pill and peek, the user's music strip and widgets, and voice commands. It runs
//  one source at a time: the system's Now Playing (default) when its adapter passes its self-test, otherwise Music or
//  Spotify — the app Now Playing last reported, else Music. If Now Playing was picked by hand and can't be used, a
//  notice says so for 6 s. A stream that dies falls back at once and Now Playing is tried again 1 s later (a failed
//  retry shows the notice again).
//

import AppKit
import Combine
import Defaults
import SwiftUI

@MainActor
final class ArisNowPlaying: ObservableObject {
    static let shared = ArisNowPlaying()

    /// Shown when the track has no artwork and its app has no icon.
    static let placeholderArt = NSImage(systemSymbolName: "heart.fill", accessibilityDescription: nil) ?? NSImage()

    @Published private(set) var songTitle = ""
    @Published private(set) var artistName = ""
    @Published private(set) var album = ""
    @Published private(set) var albumArt = ArisNowPlaying.placeholderArt
    /// The artwork's colour (white until one is known).
    @Published private(set) var avgColor = NSColor.white
    @Published private(set) var isPlaying = false
    @Published private(set) var isPlayerIdle = true
    @Published private(set) var bundleIdentifier: String?
    @Published private(set) var songDuration: TimeInterval = 0
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var timestampDate = Date()
    @Published private(set) var playbackRate: Double = 1
    /// The artwork is the playing app's icon (the track had none).
    @Published private(set) var usingAppIconForArtwork = false
    @Published private(set) var nowPlayingNotice: NowPlayingFallbackNotice?
    @Published private(set) var nowPlayingAvailability: NowPlayingAvailability = .unchecked
    /// The source picked in settings.
    @Published private(set) var preferredMediaController: MediaControllerType
    /// The source in use (differs from the preferred one while falling back).
    @Published private(set) var activeMediaController: MediaControllerType?

    private var source: ArisMusicSource?
    private var playback = ArisPlayback()
    private var hasPlayback = false
    /// Bumped whenever a source change starts, so a slower, older one can't take over.
    private var activation = 0
    private var idleTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var presentedNotices: Set<UUID> = []
    private var artworkGeneration = 0

    private init() {
        Self.migrateChoiceIfNeeded()
        preferredMediaController = Defaults[.mediaController]
        Task { await self.activate(self.preferredMediaController, notify: true) }
    }

    // MARK: - Transport

    func play() { source?.send(.play) }
    func pause() { source?.send(.pause) }
    func togglePlay() { source?.send(.toggle) }
    func nextTrack() { source?.send(.next) }
    func previousTrack() { source?.send(.previous) }

    /// Does the command and says whether it was done (a voice command's reply comes from this).
    func perform(_ command: ArisMusicCommand) async -> Bool {
        guard let source else { return false }
        return await source.perform(command)
    }

    /// What is playing now, for "지금 무슨 노래야?": read from the app when its source can, else what was last reported.
    func currentPlayback() async -> ArisPlayback? {
        if let read = await source?.current() { return read }
        guard hasPlayback else { return nil }
        return playback
    }

    /// The playback position at `date`, estimated from the last report.
    func estimatedPlaybackPosition(at date: Date = Date()) -> TimeInterval {
        playback.position(at: date)
    }

    /// Asks the source for its state now (a notch opened).
    func forceUpdate() { source?.refresh() }

    /// Stops the source (the app is quitting).
    func destroy() {
        activation += 1
        source?.stop()
        source = nil
        [idleTask, retryTask, noticeTask].forEach { $0?.cancel() }
    }

    // MARK: - Source choice

    func selectMediaController(_ choice: MediaControllerType) {
        Defaults[.mediaController] = choice
        Defaults[.didChooseMediaController] = true
        preferredMediaController = choice
        nowPlayingNotice = nil
        Task { await activate(choice, notify: true) }
    }

    /// Checks Now Playing once if nobody has yet (the settings page shows whether it works).
    func ensureNowPlayingAvailabilityChecked() {
        guard nowPlayingAvailability == .unchecked else { return }
        refreshNowPlayingAvailability()
    }

    /// Checks Now Playing again; when it is the chosen source and now works, switches to it.
    func refreshNowPlayingAvailability() {
        if preferredMediaController == .nowPlaying {
            Task { await activate(.nowPlaying, notify: true) }
            return
        }
        Task {
            guard let files = ArisAdapterFiles.bundled() else { nowPlayingAvailability = .unavailable(.setup); return }
            nowPlayingAvailability = .checking
            nowPlayingAvailability = await files.probe() ? .available : .unavailable(.probe)
        }
    }

    /// Marks the notice as on screen; true only the first time for that notice (it then leaves after 6 s).
    func markNowPlayingNoticePresented(_ id: UUID) -> Bool {
        guard nowPlayingNotice?.id == id, presentedNotices.insert(id).inserted else { return false }
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: ArisMusicRules.noticeDuration)
            guard !Task.isCancelled, let self, self.nowPlayingNotice?.id == id else { return }
            self.nowPlayingNotice = nil
        }
        return true
    }

    private func activate(_ choice: MediaControllerType, notify: Bool) async {
        activation += 1
        let mine = activation
        retryTask?.cancel()
        guard choice == .nowPlaying else {
            nowPlayingNotice = nil
            use(scripted(choice), as: choice)
            return
        }
        guard let files = ArisAdapterFiles.bundled() else {
            nowPlayingAvailability = .unavailable(.setup)
            fallBack(.setup, notify: notify)
            return
        }
        nowPlayingAvailability = .checking
        let works = await files.probe()
        guard mine == activation else { return }
        guard works else {
            nowPlayingAvailability = .unavailable(.probe)
            fallBack(.probe, notify: notify)
            return
        }
        nowPlayingAvailability = .available
        nowPlayingNotice = nil
        let adapter = ArisNowPlayingAdapter(files: files)
        adapter.onFailure = { [weak self] in self?.streamFailed() }
        use(adapter, as: .nowPlaying)
    }

    private func fallBack(_ failure: NowPlayingFailure, notify: Bool) {
        let fallback = ArisMusicRules.fallback(lastSupported: Defaults[.lastSupportedNowPlayingBundleIdentifier])
        Log.music.notice("Now Playing unavailable (\(String(describing: failure), privacy: .public)); using \(fallback.rawValue, privacy: .public)")
        use(scripted(fallback), as: fallback)
        if notify, let notice = ArisMusicRules.notice(for: failure, using: fallback, chosen: Defaults[.didChooseMediaController]) {
            nowPlayingNotice = notice
        }
    }

    private func streamFailed() {
        guard activeMediaController == .nowPlaying else { return }
        nowPlayingAvailability = .unavailable(.runtime)
        fallBack(.runtime, notify: true)
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: ArisMusicRules.retryDelay)
            guard !Task.isCancelled, let self, self.preferredMediaController == .nowPlaying else { return }
            await self.activate(.nowPlaying, notify: true)
        }
    }

    private func scripted(_ choice: MediaControllerType) -> ArisMusicSource {
        ArisScriptedPlayer(choice == .spotify ? .spotify : .music)
    }

    private func use(_ next: ArisMusicSource, as choice: MediaControllerType) {
        source?.stop()
        source = next
        activeMediaController = choice
        next.onUpdate = { [weak self, weak next] playback in
            guard let self, let next, self.source === next else { return }
            self.apply(playback)
        }
        next.start()
    }

    // MARK: - Updates

    /// Takes a new playback (from the source; also the render harness's way to set a state).
    func apply(_ new: ArisPlayback) {
        let old = playback
        let first = !hasPlayback
        playback = new
        hasPlayback = true
        if let bundle = ArisMusicRules.supportedBundle(new.bundleID, source: activeMediaController ?? .nowPlaying) {
            Defaults[.lastSupportedNowPlayingBundleIdentifier] = bundle
        }
        if songTitle != new.title { songTitle = new.title }
        if artistName != new.artist { artistName = new.artist }
        if album != new.album { album = new.album }
        songDuration = new.duration
        elapsedTime = new.elapsed
        timestampDate = new.timestamp
        playbackRate = new.rate
        if bundleIdentifier != new.bundleID { bundleIdentifier = new.bundleID }

        let playingChanged = new.isPlaying != isPlaying
        let contentChanged = first || new.differsInContent(from: old)
        if playingChanged {
            withAnimation(.smooth) { isPlaying = new.isPlaying }
            updateIdle()
        }
        if contentChanged { updateArtwork(new) }
        if playingChanged || contentChanged { peek() }
    }

    private func updateIdle() {
        idleTask?.cancel()
        if isPlaying {
            if isPlayerIdle { withAnimation(.smooth) { isPlayerIdle = false } }
            return
        }
        let wait = Defaults[.waitInterval]
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self, !self.isPlaying else { return }
            withAnimation(.smooth) { self.isPlayerIdle = true }
        }
    }

    private func updateArtwork(_ playback: ArisPlayback) {
        if let data = playback.artwork, let image = NSImage(data: data) {
            albumArt = image
            usingAppIconForArtwork = false
        } else if let bundle = playback.bundleID, let icon = appIconAsNSImage(for: bundle) {
            albumArt = icon
            usingAppIconForArtwork = true
        } else {
            albumArt = Self.placeholderArt
            usingAppIconForArtwork = false
        }
        guard Defaults[.coloredSpectrogram] else { return }
        artworkGeneration += 1
        let generation = artworkGeneration
        let image = albumArt
        Task { [weak self] in
            let color = await image.averageColor() ?? .white
            guard let self, generation == self.artworkGeneration else { return }
            self.avgColor = color
        }
    }

    private func peek() {
        switch ArisMusicRules.peek(enabled: Defaults[.enableSneakPeek], style: Defaults[.sneakPeekStyles],
                                   playing: isPlaying, title: songTitle, artist: artistName) {
        case .standard: ArisNotchNavigation.shared.toggleSneakPeek(status: true, type: .music, duration: ArisMusicRules.peekDuration)
        case .inline: ArisNotchNavigation.shared.toggleExpandingView(status: true, type: .music)
        case nil: break
        }
    }

    /// Older builds didn't record whether the source was picked by hand; one that stored a source did.
    private static func migrateChoiceIfNeeded() {
        guard !Defaults[.didMigrateMediaControllerChoice] else { return }
        if UserDefaults.standard.object(forKey: Defaults.Keys.mediaController.name) != nil {
            Defaults[.didChooseMediaController] = true
        }
        Defaults[.didMigrateMediaControllerChoice] = true
    }
}
