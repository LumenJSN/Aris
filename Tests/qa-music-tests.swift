// Tests for the music regression after QA BUG-37 (a sandboxed osascript child had no Automation grant: Spotify said
// errAEPrivilegeError): raw Apple Events sent by the app through a seam, permission checked first, replies from the
// player's answer, "지금 무슨 노래야?" answered here, and reads on demand, cached, failures logged once.
import CoreServices
import Foundation

func runQAMusicTestsBlocking() {
    final class Done: @unchecked Sendable { var value = false }
    let done = Done()
    Task {
        await runQAMusicTests()
        done.value = true
    }
    while !done.value { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
}

private func musicSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Aris/private")
    return (try? String(contentsOf: root.appendingPathComponent(path).standardized, encoding: .utf8)) ?? ""
}

/// Answers each property path as told, counts permission checks and sends.
private final class FakeEvents: ArisAppleEventSending, @unchecked Sendable {
    let lock = NSLock()
    var permissionAnswer = 0
    var asks: [Bool] = []
    var sent: [String] = []
    var values: [String: NSAppleEventDescriptor] = [:]
    var errorNumber: Int32 = 0

    func permission(for bundle: String, ask: Bool) -> Int {
        lock.withLock { asks.append(ask); return permissionAnswer }
    }

    func send(_ event: NSAppleEventDescriptor, timeout: TimeInterval) throws -> NSAppleEventDescriptor {
        let name = ArisAppleEvents.text(event.eventClass) + ArisAppleEvents.text(event.eventID)
        let path = FakeEvents.path(event.paramDescriptor(forKeyword: keyDirectObject))
        lock.withLock { sent.append(path.isEmpty ? name : name + ":" + path) }
        let reply = NSAppleEventDescriptor(eventClass: ArisAppleEvents.code("aevt"), eventID: ArisAppleEvents.code("ansr"), targetDescriptor: nil,
                                           returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        if errorNumber != 0 { reply.setParam(NSAppleEventDescriptor(int32: errorNumber), forKeyword: keyErrorNumber) }
        if let value = lock.withLock({ values[path] }) { reply.setParam(value, forKeyword: keyDirectObject) }
        return reply
    }

    /// "pTrk.pnam" from a nested property specifier.
    static func path(_ specifier: NSAppleEventDescriptor?) -> String {
        var names: [String] = []
        var current = specifier
        while let spec = current, let record = spec.coerce(toDescriptorType: ArisAppleEvents.code("reco")) ?? Optional(spec),
              let seld = record.forKeyword(ArisAppleEvents.code("seld")) {
            names.insert(seld.descriptorType == ArisAppleEvents.code("type") ? ArisAppleEvents.text(seld.typeCodeValue) : "#\(seld.int32Value)", at: 0)
            current = record.forKeyword(ArisAppleEvents.code("from"))
        }
        return names.joined(separator: ".")
    }
}

private func runQAMusicTests() async {
    qaMusicCodesTests()
    await qaMusicClientTests()
    qaMusicRepliesTests()
    qaMusicReadGateTests()
    qaMusicWiringTests()
}

private func qaMusicCodesTests() {
    check(ArisMusicEvents.command(.play, bundleID: "com.spotify.client") == "spfyPlay" && ArisMusicEvents.command(.toggle, bundleID: "com.spotify.client") == "spfyPlPs"
          && ArisMusicEvents.command(.pause, bundleID: "com.apple.Music") == "hookPaus" && ArisMusicEvents.command(.next, bundleID: "com.apple.Music") == "hookNext"
          && ArisMusicEvents.command(.previous, bundleID: "com.apple.Music") == "hookPrev", "music: each app's own suite codes (Spotify spfy, Music hook)")
    let play = ArisAppleEvents.command("spfyPlay", to: "com.spotify.client")
    check(ArisAppleEvents.text(play.eventClass) == "spfy" && ArisAppleEvents.text(play.eventID) == "Play", "music: a command is a raw event, no script")
    let get = ArisAppleEvents.get(["pTrk", "pnam"], of: "com.apple.Music")
    check(ArisAppleEvents.text(get.eventClass) + ArisAppleEvents.text(get.eventID) == "coregetd"
          && FakeEvents.path(get.paramDescriptor(forKeyword: keyDirectObject)) == "pTrk.pnam", "music: a read is get of name of current track")
    let art = ArisAppleEvents.get(["pTrk"], element: "cArt", index: 1, property: "pRaw", of: "com.apple.Music")
    check(FakeEvents.path(art.paramDescriptor(forKeyword: keyDirectObject)) == "pTrk.#1.pRaw", "music: raw data of artwork 1 of current track")
}

private func qaMusicClientTests() async {
    let fake = FakeEvents()
    fake.values = ["pPlS": NSAppleEventDescriptor(enumCode: ArisAppleEvents.code("kPSP")), "pTrk.pnam": NSAppleEventDescriptor(string: "Hello, World"),
                   "pTrk.pArt": NSAppleEventDescriptor(string: "아이유"), "pTrk.pAlb": NSAppleEventDescriptor(string: "Real"),
                   "pTrk.pDur": NSAppleEventDescriptor(int32: 240_000), "pPos": NSAppleEventDescriptor(double: 12.5)]
    let client = ArisAppleEventClient(bundle: "com.spotify.client", sender: fake)
    let read = try? await ArisMusicEvents.read(client, durationUnit: 0.001, at: Date())
    check(read?.isPlaying == true && read?.title == "Hello, World" && read?.artist == "아이유" && read?.album == "Real" && read?.duration == 240
          && read?.elapsed == 12.5, "music: the state read as raw events (a comma in a title stays)")
    check(fake.asks == [false], "music: permission checked once before the first send, and a read never asks the user")
    _ = try? await client.send(ask: true, { ArisAppleEvents.command("spfyPlay", to: $0) }, read: { _ in true })
    check(fake.asks == [false] && fake.sent.last == "spfyPlay", "music: once granted, sends go without asking again")

    let stopped = FakeEvents()
    stopped.values = ["pPlS": NSAppleEventDescriptor(enumCode: ArisAppleEvents.code("kPSS"))]
    let idle = try? await ArisMusicEvents.read(ArisAppleEventClient(bundle: "com.apple.Music", sender: stopped), durationUnit: 1, at: Date())
    check(idle?.title == "" && idle?.isPlaying == false && stopped.sent.count == 1, "music: stopped is read in one event")

    let denied = FakeEvents()
    denied.permissionAnswer = ArisAppleEventError.notPermitted
    do {
        _ = try await ArisAppleEventClient(bundle: "com.spotify.client", sender: denied).send(ask: true, { ArisAppleEvents.command("spfyPlay", to: $0) }, read: { _ in true })
        check(false, "music: no Automation permission: nothing sent, an error")
    } catch let error as ArisAppleEventError {
        check(error.isPermission && denied.sent.isEmpty && denied.asks == [true], "music: no Automation permission: nothing sent, an error (a command may ask)")
    } catch { check(false, "music: no Automation permission: nothing sent, an error") }

    let refused = FakeEvents()
    refused.errorNumber = Int32(ArisAppleEventError.privilege)
    do {
        _ = try await ArisAppleEventClient(bundle: "com.spotify.client", sender: refused).send(ask: true, { ArisAppleEvents.command("spfyPlay", to: $0) }, read: { _ in true })
        check(false, "music: the app's error in its reply is a failure (-10004)")
    } catch let error as ArisAppleEventError {
        check(error.number == ArisAppleEventError.privilege, "music: the app's error in its reply is a failure (-10004)")
    } catch { check(false, "music: the app's error in its reply is a failure (-10004)") }

    let start = Date()
    check(ArisAppleEventClient.bounded(0.2) { Thread.sleep(forTimeInterval: 2); return 0 } == nil && Date().timeIntervalSince(start) < 1,
          "music: a permission check that hangs is given up at its limit")
    // A real raw send to an app that isn't running: an error at once, no script, no hang.
    let live = Date()
    do {
        _ = try ArisLiveAppleEvents().send(ArisAppleEvents.command("spfyPlay", to: "com.lumenjsn.aris.no-such-app"), timeout: 2)
        check(false, "music: a raw send to no app fails at once")
    } catch {
        check(Date().timeIntervalSince(live) < 3, "music: a raw send to no app fails at once (\(error.localizedDescription))")
    }
}

private func qaMusicRepliesTests() {
    for media in [ArisIntent.Media.play, .pause, .next, .previous] {
        for korean in [true, false] {
            let failed = media.reply(done: false, korean: korean)
            check(!failed.contains("게요") && !failed.isEmpty && failed != media.reply(done: true, korean: korean)
                  && media.reply(done: true, korean: korean) == ArisIntent.media(media).acknowledgement(korean: korean),
                  "music: a failed \(media) says so, never what it would do: \(failed)")
        }
    }
    for asks in ["지금 무슨 노래야?", "이 노래 뭐야", "지금 나오는 곡 제목 알려줘", "무슨 노래야", "what's playing", "What song is this?", "what am i listening to"] {
        check(ArisIntent.parse(asks) == .whatsPlaying, "music: \(asks) is answered from what's playing")
    }
    for not in ["무슨 노래 틀어 줄까", "이 노래 가사 알려줘", "무슨 노래 좋아해?", "노래 틀어줘", "아이유 노래 추천해 줘", "유튜브에서 이 노래 찾아 줘"] {
        check(ArisIntent.parse(not) != .whatsPlaying, "music: \(not) isn't")
    }
    check(ArisIntent.nowPlayingLine(title: "좋은 날", artist: "아이유", playing: true, korean: true) == "지금 나오는 곡은 ‘좋은 날’, 아이유 노래예요."
          && ArisIntent.nowPlayingLine(title: "", artist: "", playing: false, korean: true) == "지금 재생 중인 음악이 없어요."
          && ArisIntent.nowPlayingLine(title: "Blue", artist: "", playing: false, korean: false) == "Paused: “Blue”.",
          "music: the song's line")
}

private func qaMusicReadGateTests() {
    var gate = ArisMusicReadGate()
    check(gate.wants(now: 0, announced: false) && !gate.wants(now: 0.1, announced: false), "music: one read at a time")
    check(!gate.wants(now: 0.2, announced: true), "music: an announcement during a read waits")
    let first = gate.finished(now: 0.5, ok: false)
    check(first.logFailure && first.readAgain, "music: the first failure is logged, and the announced change is read after")
    check(gate.wants(now: 0.6, announced: true) && gate.finished(now: 0.7, ok: false).logFailure == false, "music: a failure in a row isn't logged again")
    check(!gate.wants(now: 1.0, announced: false), "music: an unannounced refresh soon after reuses the last (no poll per turn)")
    check(gate.wants(now: 2.5, announced: false) && !gate.finished(now: 2.6, ok: true).logFailure, "music: later it reads again")
    _ = gate.wants(now: 5, announced: false)
    check(gate.finished(now: 5.1, ok: false).logFailure, "music: after a good read, a failure is logged again")
}

private func qaMusicWiringTests() {
    let player = musicSource("Music/ArisScriptedPlayer.swift")
    check(!player.contains("ArisAppleScript") && player.contains("ArisAppleEventClient(bundle: app.bundleID"), "music: the player sends raw events, never a script")
    let controller = musicSource("Aris/ArisController.swift")
    check(controller.contains("reply = media.reply(done: done, korean: korean)") && controller.contains("case .whatsPlaying = intent"),
          "music: the voice command's line comes from the result, and the song question is answered here")
}
