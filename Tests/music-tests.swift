// Acceptance tests for the clean-room music layer (cleanroom-specs/08-music.md, QUESTIONS A12/A13).
import AppKit
import SwiftUI

func runMusicTests() {
    jsonLineTests()
    adapterStateTests()
    positionTests()
    idleTests()
    fallbackTests()
    sourcePreferenceTests()
    artworkLookupTests()
    colourTests()
    headerTests()
}

private func lines(_ text: String) -> Data { Data(text.utf8) }

private func jsonLineTests() {
    var reader = ArisJSONLines()
    check(reader.feed(lines("{\"a\":1}\r\n{\"b\"")).count == 1, "json lines: a CRLF line is read, a partial one waits")
    let rest = reader.feed(lines(":2}\n\n   \n"))
    check(rest.count == 1 && rest[0]["b"] as? Int == 2, "json lines: the partial line completes, blank lines are skipped")
    check(reader.feed(lines("oops\n{\"c\":3}\nbad\nworse\n")).count == 1 && !reader.isBroken, "json lines: a good line resets the bad count")
    check(reader.feed(lines("[1]\n")).isEmpty && reader.isBroken, "json lines: three bad lines in a row break the stream")
    check(reader.feed(lines("{\"d\":4}\n")).isEmpty, "json lines: nothing is read after the stream broke")
}

private func adapterStateTests() {
    var state = ArisAdapterState()
    let art = Data([1, 2, 3]).base64EncodedString()
    state.apply(["type": "data", "diff": false, "payload": [
        "title": "Song", "artist": "Artist", "album": "Album", "playing": true, "durationMicros": 200_000_000,
        "elapsedTimeMicros": 10_000_000, "timestampEpochMicros": 1_000_000_000_000_000, "playbackRate": 1,
        "bundleIdentifier": "com.apple.WebKit.GPU", "parentApplicationBundleIdentifier": "com.apple.Safari", "artworkData": art,
    ] as [String: Any]])
    var p = state.playback()
    check(p.title == "Song" && p.isPlaying && p.duration == 200 && p.elapsed == 10 && p.artwork == Data([1, 2, 3])
          && p.timestamp == Date(timeIntervalSince1970: 1_000_000_000), "adapter: a full payload (times in microseconds)")
    check(p.bundleID == "com.apple.Safari", "adapter: the parent app names the source")
    state.apply(["type": "data", "diff": true, "payload": ["playing": false, "elapsedTimeMicros": 12_000_000] as [String: Any]])
    p = state.playback()
    check(!p.isPlaying && p.elapsed == 12 && p.title == "Song" && p.artwork == Data([1, 2, 3]), "adapter: a diff merges into the last state")
    state.apply(["type": "data", "diff": true, "payload": ["artworkData": NSNull(), "parentApplicationBundleIdentifier": NSNull()] as [String: Any]])
    p = state.playback()
    check(p.artwork == nil && p.bundleID == "com.apple.WebKit.GPU", "adapter: a null in a diff removes the key")
    state.apply(["type": "data", "diff": false, "payload": [String: Any]()])
    p = state.playback()
    check(p.title.isEmpty && !p.isPlaying && p.bundleID == nil, "adapter: an empty full payload means nothing is playing")
    state.apply(["type": "other", "payload": ["title": "x"] as [String: Any]])
    check(state.playback().title.isEmpty, "adapter: messages of another type are ignored")
}

private func positionTests() {
    let t0 = Date(timeIntervalSince1970: 1000)
    var p = ArisPlayback(duration: 100, elapsed: 10, timestamp: t0, rate: 1, isPlaying: true)
    check(p.position(at: t0.addingTimeInterval(5)) == 15, "position: playing moves with time")
    p.rate = 2
    check(p.position(at: t0.addingTimeInterval(5)) == 20, "position: rate 2 moves twice as fast")
    check(p.position(at: t0.addingTimeInterval(500)) == 100, "position: clamped to the duration")
    check(p.position(at: t0.addingTimeInterval(-50)) == 0, "position: never below 0")
    p.isPlaying = false
    check(p.position(at: t0.addingTimeInterval(5)) == 10, "position: paused holds")
    p.elapsed = 150
    check(p.position(at: t0) == 100, "position: paused past the end shows the end")
    let a = ArisPlayback(title: "a", artist: "b", album: "c", artwork: Data([1]), bundleID: "x")
    var b = a
    b.elapsed = 9
    b.isPlaying = true
    check(!b.differsInContent(from: a), "content: times and playing don't change the content")
    b.artwork = Data([2])
    check(b.differsInContent(from: a), "content: new artwork bytes do")
}

private func idleTests() {
    let paused = Date(timeIntervalSince1970: 50)
    check(!ArisMusicRules.isIdle(playing: true, pausedSince: nil, now: paused, wait: 3), "idle: playing is never idle")
    check(!ArisMusicRules.isIdle(playing: false, pausedSince: paused, now: paused.addingTimeInterval(2.9), wait: 3), "idle: not before the wait")
    check(ArisMusicRules.isIdle(playing: false, pausedSince: paused, now: paused.addingTimeInterval(3), wait: 3), "idle: after the wait")
    check(ArisMusicRules.isIdle(playing: false, pausedSince: nil, now: paused, wait: 3), "idle: nothing ever played")
    check(ArisMusicRules.peek(enabled: true, style: .standard, playing: true, title: "t", artist: "a") == .standard
          && ArisMusicRules.peek(enabled: true, style: .inline, playing: true, title: "t", artist: "a") == .inline, "peek: style picks the kind")
    check(ArisMusicRules.peek(enabled: false, style: .standard, playing: true, title: "t", artist: "a") == nil
          && ArisMusicRules.peek(enabled: true, style: .standard, playing: false, title: "t", artist: "a") == nil
          && ArisMusicRules.peek(enabled: true, style: .standard, playing: true, title: "t", artist: "") == nil, "peek: only when on, playing, with title and artist")
    check(ArisMusicRules.peekDuration == 1.5, "peek: a standard peek shows for 1.5 s, as the old app did")
}

private func fallbackTests() {
    check(ArisMusicRules.fallback(lastSupported: "com.spotify.client") == .spotify, "fallback: Spotify when Now Playing last saw it")
    check(ArisMusicRules.fallback(lastSupported: "com.apple.Music") == .appleMusic, "fallback: Music when Now Playing last saw it")
    check(ArisMusicRules.fallback(lastSupported: "com.google.Chrome") == .appleMusic && ArisMusicRules.fallback(lastSupported: nil) == .appleMusic,
          "fallback: Music otherwise")
    check(ArisMusicRules.supportedBundle("com.spotify.client", source: .nowPlaying) == "com.spotify.client"
          && ArisMusicRules.supportedBundle("com.google.Chrome", source: .nowPlaying) == nil
          && ArisMusicRules.supportedBundle("com.spotify.client", source: .spotify) == nil, "fallback: only music apps seen through Now Playing are remembered")
    check(ArisMusicRules.notice(for: .probe, using: .spotify, chosen: false) == nil, "notice: none unless Now Playing was picked by hand")
    let texts: [(NowPlayingFailure, String, String)] = [
        (.setup, "Now Playing components unavailable", "Using Spotify instead"),
        (.probe, "Could not verify Now Playing", "Using Spotify temporarily"),
        (.runtime, "Now Playing connection lost", "Using Spotify temporarily"),
    ]
    for (failure, title, subtitle) in texts {
        let notice = ArisMusicRules.notice(for: failure, using: .spotify, chosen: true)
        check(notice.map { String(localized: $0.title) } == title && notice.map { String(localized: $0.subtitle) } == subtitle,
              "notice: \(failure) says \"\(title)\" / \"\(subtitle)\"")
    }
    check(NowPlayingAvailability.unavailable(.runtime).failure == .runtime && NowPlayingAvailability.checking.failure == nil,
          "availability: only unavailable carries a failure")
}

private func sourcePreferenceTests() {
    let cases: [(String, MediaControllerType?)] = [("nowPlaying", .nowPlaying), ("Now Playing", .nowPlaying), ("appleMusic", .appleMusic),
                                                   ("Apple Music", .appleMusic), ("spotify", .spotify), ("Spotify", .spotify),
                                                   ("youtubeMusic", .nowPlaying), ("YouTube Music", .nowPlaying), ("tidal", nil)]
    check(cases.allSatisfy { MediaControllerType(rawValue: $0.0) == $0.1 }, "source preference: raw values, legacy and YouTube spellings")
}

private func artworkLookupTests() {
    check(ArisArtworkLookup.matches("Album (Deluxe Edition)", "album"), "artwork: edition suffix and case ignored")
    check(ArisArtworkLookup.matches("Song - Single", "Song") && ArisArtworkLookup.matches("Café [Remastered 2011]", "cafe"),
          "artwork: \" - Single\", brackets and accents ignored")
    check(!ArisArtworkLookup.matches("Other", "Album") && !ArisArtworkLookup.matches("", ""), "artwork: different or empty names don't match")
    check(ArisArtworkLookup.matches("Album", "Album: The Sequel (Deluxe)") && ArisArtworkLookup.matches("Song (Live) - Single", "Song Live at Home"),
          "artwork: one name starting with the other matches, after edition suffixes go")
    check(!ArisArtworkLookup.matches("Album", "Other Album"), "artwork: a name inside, not at the start, doesn't")
    check(ArisArtworkLookup.key(title: "t", artist: "Ärtist", album: "Album (Deluxe)") == ArisArtworkLookup.key(title: "u", artist: "artist", album: "album"),
          "artwork: one cache entry per album")
    let body = Data("""
    {"resultCount":2,"results":[
      {"collectionName":"Other Album","artistName":"Artist","artworkUrl100":"https://x/a/100x100bb.jpg"},
      {"collectionName":"Álbum (Deluxe Edition)","artistName":"The Artist","artworkUrl100":"https://x/b/100x100bb.jpg"}]}
    """.utf8)
    check(ArisArtworkLookup.artworkURL(in: body, title: "t", artist: "Artist", album: "album")?.absoluteString == "https://x/b/600x600bb.jpg",
          "artwork: the matching album's art, at 600 × 600")
    check(ArisArtworkLookup.artworkURL(in: body, title: "t", artist: "Nobody", album: "album") == nil, "artwork: the artist must match too")
    let url = ArisArtworkLookup.searchURL(title: "Song", artist: "Artist", album: "")
    check(url?.host == "itunes.apple.com" && url?.query?.contains("entity=song") == true, "artwork: a song search when there is no album")
}

private func colourTests() {
    func image(_ color: NSColor, _ size: CGSize, clearHalf: Bool = false) -> CGImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill(); CGRect(origin: .zero, size: size).fill()
        if clearHalf { NSColor.clear.setFill(); CGRect(x: 0, y: 0, width: size.width / 2, height: size.height).fill(using: .copy) }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }
    func rgb(_ c: NSColor?) -> [Double] { c.map { [$0.redComponent, $0.greenComponent, $0.blueComponent] } ?? [] }
    func near(_ a: [Double], _ b: [Double]) -> Bool { a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 0.01 } }
    check(near(rgb(ArisArtworkColor.average(of: image(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), CGSize(width: 300, height: 300)))), [1, 0, 0]),
          "colour: a bright image keeps its mean")
    check(near(rgb(ArisArtworkColor.average(of: image(NSColor(deviceRed: 0.1, green: 0.2, blue: 0.05, alpha: 1), CGSize(width: 100, height: 50)))), [0.4, 0.5, 0.35]),
          "colour: a dark mean is lifted until its top channel is 0.5")
    check(near(rgb(ArisArtworkColor.average(of: image(.black, CGSize(width: 10, height: 10)))), [0.5, 0.5, 0.5]), "colour: near-black becomes mid grey")
    check(near(rgb(ArisArtworkColor.average(of: image(NSColor(deviceRed: 1, green: 1, blue: 1, alpha: 1), CGSize(width: 64, height: 64), clearHalf: true))), [0.5, 0.5, 0.5]),
          "colour: transparent pixels count as black")
    func ensure(_ r: Double, _ g: Double, _ b: Double) -> [Double] {
        let c = Color(.sRGB, red: r, green: g, blue: b).ensureMinimumBrightness(factor: 0.5)
        return rgb(NSColor(c).usingColorSpace(.sRGB))
    }
    check(near(ensure(1, 0, 0), [1, 0, 0]) && near(ensure(0.2, 0.2, 0.2), [0.5, 0.5, 0.5]) && near(ensure(0.9, 0.9, 0.9), [0.5, 0.5, 0.5]),
          "brightness: luminance set to the factor, channels capped at 1")
    check(near(ensure(0.1, 0.5, 0.9), [0.1127, 0.5633, 1]), "brightness: Rec. 709 weights on the encoded values")
    check(near(ensure(0, 0, 0), [0.5, 0.5, 0.5]), "brightness: black becomes grey at the factor")
    check(near(rgb(NSColor(Color(.sRGB, red: 0.2, green: 0.2, blue: 0.2).ensureMinimumBrightness(factor: 1.5)).usingColorSpace(.sRGB)), [0.2, 0.2, 0.2]),
          "brightness: a factor outside 0…1 changes nothing")
}

private func headerTests() {
    check(ArisNotchHeaderLayout.placeCount == 3, "header: three places (shelf, Claude, settings) now the player page is gone")
    let user = ArisNotchHeaderLayout.places(count: ArisNotchHeaderLayout.placeCount, headerWidth: 416, housing: 224 + 8, textInset: 16)
    check(user.slot == 23 && user.width == 73 && user.trailing == 10 && user.width + user.trailing <= (416 - 232) / 2,
          "header: on the user's 224-point notch the three places get full 23-point slots and still fit beside the camera")
    let fits = stride(from: CGFloat(150), through: 250, by: 1).allSatisfy { notch in
        let p = ArisNotchHeaderLayout.places(count: ArisNotchHeaderLayout.placeCount, headerWidth: 416, housing: notch + 8, textInset: 16)
        return p.slot == ArisNotchHeaderLayout.minSlot || p.width + p.trailing <= (416 - notch - 8) / 2
    }
    check(fits, "header: three places fit beside any notch 150–250 wide")
}

/// The Now Playing source end to end against a stand-in adapter script (no system media involved).
@MainActor
func runMusicAdapterTests() async {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("aris-adapter-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let script = dir.appendingPathComponent("stub.pl")
    try? """
    $| = 1;
    my $f = $ARGV[-1] eq "--micros" ? $ARGV[-2] : $ARGV[-1];
    if ($f eq "test") { sleep(30) if -e "$ARGV[0].hang"; exit(-e "$ARGV[0].ok" ? 0 : 1); }
    if ($ARGV[-2] eq "send") { open(my $h, ">", "$ARGV[0].sent-$ARGV[-1]"); close($h); exit(0); }
    if ($f eq "stream") {
      print "{\\"type\\":\\"data\\",\\"diff\\":false,\\"payload\\":{\\"title\\":\\"T\\",\\"artist\\":\\"A\\",\\"playing\\":true}}\\r\\n";
      print "\\n";
      print "{\\"type\\":\\"data\\",\\"diff\\":true,\\"payload\\":{\\"playing\\":false}}\\n";
      sleep(1); exit(0);
    }
    """.write(to: script, atomically: true, encoding: .utf8)
    let files = ArisAdapterFiles(script: script, framework: dir, testClient: dir)
    var started = Date()
    check(await !files.probe(attempts: 3, timeout: 5, backoff: .milliseconds(100)), "adapter: a failing self-test fails every attempt")
    check(Date().timeIntervalSince(started) >= 0.3, "adapter: retries wait the backoff times the attempt (0.1 + 0.2 s here)")
    FileManager.default.createFile(atPath: dir.path + ".hang", contents: Data())
    started = Date()
    check(await !files.probe(attempts: 1, timeout: 0.5) && Date().timeIntervalSince(started) < 5, "adapter: a hung self-test is killed at its timeout")
    try? FileManager.default.removeItem(atPath: dir.path + ".hang")
    FileManager.default.createFile(atPath: dir.path + ".ok", contents: Data())
    defer { try? FileManager.default.removeItem(atPath: dir.path + ".ok") }
    check(await files.probe(attempts: 1, timeout: 5), "adapter: a passing self-test passes")

    let adapter = ArisNowPlayingAdapter(files: files)
    var updates: [ArisPlayback] = []
    var failed = 0
    adapter.onUpdate = { updates.append($0) }
    adapter.onFailure = { failed += 1 }
    adapter.start()
    let deadline = Date().addingTimeInterval(5)
    while failed == 0, Date() < deadline { try? await Task.sleep(for: .milliseconds(50)) }
    check(updates.last?.title == "T" && updates.last?.isPlaying == false, "adapter: streamed lines become playback (diff merged)")
    check(failed == 1, "adapter: a stream that ends by itself reports one failure")
    adapter.stop()

    let transport = FakeTransport(accepts: true)
    let direct = ArisNowPlayingAdapter(files: files, transport: transport)
    direct.send(.next)
    direct.send(.toggle)
    try? await Task.sleep(for: .milliseconds(500))
    check(transport.sent == [.next, .toggle] && !FileManager.default.fileExists(atPath: dir.path + ".sent-4"),
          "adapter: transport goes in-process when MediaRemote takes it, no helper started")
    let refusing = ArisNowPlayingAdapter(files: files, transport: FakeTransport(accepts: false))
    refusing.send(.previous)
    let sentDeadline = Date().addingTimeInterval(5)
    while !FileManager.default.fileExists(atPath: dir.path + ".sent-5"), Date() < sentDeadline { try? await Task.sleep(for: .milliseconds(50)) }
    check(FileManager.default.fileExists(atPath: dir.path + ".sent-5"), "adapter: a refused command falls back to the adapter's send (id 5 = previous)")
    try? FileManager.default.removeItem(atPath: dir.path + ".sent-5")
    check(ArisMediaRemoteTransport.load() != nil, "MediaRemote: the send-command symbol resolves on this macOS (nothing is sent)")
    check([ArisMusicCommand.play, .pause, .toggle, .next, .previous].map(ArisMediaRemoteTransport.id) == [0, 1, 2, 4, 5],
          "MediaRemote: command numbers")
}

private final class FakeTransport: ArisTransport {
    let accepts: Bool
    var sent: [ArisMusicCommand] = []
    init(accepts: Bool) { self.accepts = accepts }
    func send(_ command: ArisMusicCommand) -> Bool { sent.append(command); return accepts }
}

func runMusicTestsBlocking() {
    runMusicTests()
    let done = MusicTestFlag()
    Task { @MainActor in
        await runMusicAdapterTests()
        done.value = true
    }
    while !done.value { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
}

private final class MusicTestFlag: @unchecked Sendable { var value = false }
