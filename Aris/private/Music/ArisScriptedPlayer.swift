//
//  ArisScriptedPlayer.swift
//  Aris
//
//  Music and Spotify driven by raw Apple Events from the app (ArisAppleEvents: no script is compiled, QA BUG-37). State
//  is read when the app announces a change (its distributed "player info" notification) or when asked, a fresh read
//  reused for a moment and a failing one logged once (ArisMusicReadGate); it is never read from an app that isn't
//  running, so reading never launches it. A command says whether it was done. Music's streamed tracks have no artwork
//  to fetch: that comes from the iTunes Search API.
//

import AppKit
import Foundation

@MainActor
final class ArisScriptedPlayer: ArisMusicSource {
    struct App {
        let name: String
        let bundleID: String
        let notification: String
        /// Seconds per unit of the app's track duration (Spotify reports milliseconds).
        let durationUnit: Double
        let artwork: Artwork

        enum Artwork { case scriptedData, scriptedURL }

        static let music = App(name: "Music", bundleID: MediaAppBundleID.appleMusic, notification: "com.apple.Music.playerInfo",
                               durationUnit: 1, artwork: .scriptedData)
        static let spotify = App(name: "Spotify", bundleID: MediaAppBundleID.spotify,
                                 notification: "com.spotify.client.PlaybackStateChanged", durationUnit: 0.001, artwork: .scriptedURL)
    }

    var onUpdate: ((ArisPlayback) -> Void)?
    var onFailure: (() -> Void)?

    private let app: App
    private let events: ArisAppleEventClient
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var reading: Task<Void, Never>?
    private var gate = ArisMusicReadGate()
    private var artworkCache: [String: Data] = [:]
    private var last = ArisPlayback()

    init(_ app: App, sender: ArisAppleEventSending = ArisLiveAppleEvents()) {
        self.app = app
        events = ArisAppleEventClient(bundle: app.bundleID, sender: sender)
    }

    func start() {
        guard observers.isEmpty else { return }
        let distributed = DistributedNotificationCenter.default()
        observers.append((distributed, distributed.addObserver(forName: Notification.Name(app.notification), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(announced: true) }
        }))
        let workspace = NSWorkspace.shared.notificationCenter
        let bundleID = app.bundleID
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let quit = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == bundleID
            MainActor.assumeIsolated { if quit { self?.appQuit() } }
        }))
        refresh(announced: true)
    }

    func stop() {
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
        reading?.cancel()
        reading = nil
    }

    func refresh() { refresh(announced: false) }

    /// `announced`: the app said its state changed (read even if a read just ran).
    private func refresh(announced: Bool) {
        guard isRunning, gate.wants(now: Self.now, announced: announced) else { return }
        reading = Task { [weak self] in
            guard let self else { return }
            let playback = await self.read()
            let (logFailure, again) = self.gate.finished(now: Self.now, ok: playback != nil)
            if logFailure, let failure = self.lastFailure {
                Log.music.error("\(self.app.name, privacy: .public) state unreadable: \(failure, privacy: .public)")
            }
            if let playback, !Task.isCancelled {
                self.publish(playback)
                if playback.artwork == nil, !playback.title.isEmpty, let artwork = await self.artwork(for: playback), !Task.isCancelled {
                    var withArt = playback
                    withArt.artwork = artwork
                    self.publish(withArt)
                }
            }
            if again { self.refresh(announced: true) }
        }
    }

    func send(_ command: ArisMusicCommand) {
        Task { _ = await perform(command) }
    }

    func perform(_ command: ArisMusicCommand) async -> Bool {
        // Play may start the app; anything else needs it running.
        if !isRunning {
            guard command == .play, await launch() else { return false }
        }
        let code = ArisMusicEvents.command(command, bundleID: app.bundleID)
        do {
            _ = try await events.send(ask: true, { ArisAppleEvents.command(code, to: $0) }, read: { _ in true })
            refresh(announced: true)
            return true
        } catch {
            Log.music.error("\(self.app.name, privacy: .public) \(code, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func current() async -> ArisPlayback? {
        guard isRunning else { return nil }
        if let lastReadAt, Self.now - lastReadAt < ArisMusicReadGate.freshFor { return last }
        guard let playback = await read() else { return nil }
        publish(playback)
        return playback
    }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    /// When the last good read came in.
    private var lastReadAt: TimeInterval?
    /// What the last failed read said.
    private var lastFailure: String?

    /// Opens the app in the background and waits a moment for it to run.
    private func launch() async -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        guard (try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)) != nil else { return false }
        for _ in 0..<30 where !isRunning { try? await Task.sleep(for: .milliseconds(100)) }
        // A just-started app takes a moment before it answers events.
        try? await Task.sleep(for: .milliseconds(500))
        return isRunning
    }

    private var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
    }

    private func publish(_ playback: ArisPlayback) {
        last = playback
        onUpdate?(playback)
    }

    private func appQuit() {
        reading?.cancel()
        var stopped = last
        stopped.isPlaying = false
        stopped.elapsed = stopped.position(at: Date())
        stopped.timestamp = Date()
        publish(stopped)
    }

    /// The app's state, or nil if it couldn't be read (why, kept for the log).
    private func read() async -> ArisPlayback? {
        do {
            var playback = try await ArisMusicEvents.read(events, durationUnit: app.durationUnit, at: Date())
            // Same track as before: keep the artwork already found for it.
            if !playback.differsInContent(from: ArisPlayback(title: last.title, artist: last.artist, album: last.album, artwork: nil, bundleID: last.bundleID)) {
                playback.artwork = last.artwork
            }
            lastReadAt = Self.now
            lastFailure = nil
            return playback
        } catch {
            lastFailure = error.localizedDescription
            return nil
        }
    }

    private func artwork(for playback: ArisPlayback) async -> Data? {
        switch app.artwork {
        case .scriptedData:
            if let data = try? await ArisMusicEvents.musicArtwork(events) { return data }
            return await searchedArtwork(for: playback)
        case .scriptedURL:
            guard let url = try? await ArisMusicEvents.spotifyArtworkURL(events) else { return nil }
            return try? await ArisArtworkFetch.shared.data(from: url)
        }
    }

    private func searchedArtwork(for playback: ArisPlayback) async -> Data? {
        let key = ArisArtworkLookup.key(title: playback.title, artist: playback.artist, album: playback.album)
        if let cached = artworkCache[key] { return cached }
        guard let search = ArisArtworkLookup.searchURL(title: playback.title, artist: playback.artist, album: playback.album),
              let body = try? await ArisArtworkFetch.shared.data(from: search),
              let url = ArisArtworkLookup.artworkURL(in: body, title: playback.title, artist: playback.artist, album: playback.album),
              let data = try? await ArisArtworkFetch.shared.data(from: url), NSImage(data: data) != nil else { return nil }
        artworkCache[key] = data
        return data
    }
}
