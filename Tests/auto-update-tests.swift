// Tests for auto-update: Sparkle 2 behind the notice pill. Version compare, the updater off for every build but
// the public one (and with no feed or key), the idle gate an automatic install waits for, the pill's state machine and
// its notices, the helper restarted after an update, the appcast a release writes (a dry run: a fixed signature, no
// key, no network), the settings rows, and the wiring (no Sparkle window, the plist keys only in the public export).
// Called from main.swift; uses its check().
import Foundation

private let updateRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func updateSource(_ path: String) -> String { (try? String(contentsOf: updateRoot.appendingPathComponent(path), encoding: .utf8)) ?? "" }

func runAutoUpdateTests() {
    updateVersionTests()
    updatePolicyTests()
    updateIdleTests()
    updatePillTests()
    updateNoticeTests()
    updateRelaunchTests()
    updateAppcastTests()
    updateSettingsTests()
    updateWiringTests()
}

// MARK: - Versions

private func updateVersionTests() {
    typealias V = ArisUpdateVersion
    check(V.parts("1.2.10") == [1, 2, 10] && V.parts("v1.3") == [1, 3] && V.parts("1.3.0-beta.1") == [1, 3, 0] && V.parts("") == [],
          "update version: parts are the leading numbers, a v dropped, a suffix ignored")
    check(V.isNewer("1.2.10", than: "1.2.9") && !V.isNewer("1.2.9", than: "1.2.10"), "update version: 1.2.10 is newer than 1.2.9 (numbers, not text)")
    check(V.compare("1.3", "1.3.0") == .orderedSame && V.compare("1.3.0.1", "1.3") == .orderedDescending, "update version: a missing part is 0")
    check(V.isNewer("2.0.0", than: "1.99.99") && V.isNewer("1.2.99", than: "1.2.98") && !V.isNewer("1.2.0", than: "1.2.0"),
          "update version: majors first; equal is not newer")
    check(V.compare("v1.2.1", "1.2.1") == .orderedSame, "update version: a tag's v is the same version")
}

// MARK: - Which build updates itself

private let goodKey = Data(repeating: 7, count: 32).base64EncodedString()
private let goodInfo: [String: Any] = [ArisUpdatePolicy.feedKey: ArisAppcast.feed, ArisUpdatePolicy.publicKeyKey: goodKey]

private func updatePolicyTests() {
    typealias P = ArisUpdatePolicy
    check(P.isOn(bundleId: P.publicBundleId, info: goodInfo), "update policy: the public build with its feed and key updates itself")
    // The owner's own build (whatever its id is renamed to in the public export, it is never the public one here).
    if ArisAgentInstall.appId != P.publicBundleId {
        check(!P.isOn(bundleId: ArisAgentInstall.appId, info: goodInfo), "update policy: the private bundle id is off, even with a feed and key")
    }
    check(!P.isOn(bundleId: "com.example.aris", info: goodInfo) && !P.isOn(bundleId: nil, info: goodInfo),
          "update policy: any other bundle id is off")
    check(!P.isOn(bundleId: P.publicBundleId, info: [:]), "update policy: no feed and no key (a build made without the export): off")
    check(!P.isOn(bundleId: P.publicBundleId, info: [P.feedKey: ArisAppcast.feed]), "update policy: a feed without a key is off")
    check(!P.isOn(bundleId: P.publicBundleId, info: [P.feedKey: "http://github.com/x/appcast.xml", P.publicKeyKey: goodKey]),
          "update policy: a plain-http feed is off")
    check(!P.isOn(bundleId: P.publicBundleId, info: [P.feedKey: ArisAppcast.feed, P.publicKeyKey: "c2hvcnQ="]), "update policy: a key that isn't 32 bytes is off")
    check(P.feed(info: goodInfo, testFeed: nil) == ArisAppcast.feed, "update feed: the Info.plist's")
    check(P.feed(info: goodInfo, testFeed: "http://127.0.0.1:8123/appcast.xml") == "http://127.0.0.1:8123/appcast.xml"
          && P.feed(info: goodInfo, testFeed: "http://localhost:9/a.xml") == "http://localhost:9/a.xml",
          "update feed: a test feed on this Mac is taken")
    check(P.feed(info: goodInfo, testFeed: "https://evil.example/appcast.xml") == ArisAppcast.feed
          && P.feed(info: goodInfo, testFeed: "http://127.0.0.1.evil.example/a.xml") == ArisAppcast.feed
          && P.feed(info: goodInfo, testFeed: "file:///tmp/a.xml") == ArisAppcast.feed,
          "update feed: a test feed anywhere else is ignored")
    check(P.checkInterval == 86_400, "update: checked every 24 hours")
    check(ArisAppcast.feed == "https://github.com/LumenJSN/Aris/releases/latest/download/appcast.xml", "update feed: the latest release's appcast.xml")
}

// MARK: - The idle gate

private func updateIdleTests() {
    typealias I = ArisUpdateIdle
    let quiet = I.Activity()
    check(I.isIdle(quiet), "update idle: nothing running is idle")
    for (name, busy) in [("a turn", I.Activity(turn: true)), ("a job", I.Activity(job: true)), ("a dictation", I.Activity(dictation: true)),
                         ("the setup", I.Activity(onboarding: true))] {
        check(!I.isIdle(busy), "update idle: \(name) is not idle")
        check(!I.mayInstall(busy, idleSince: Date(timeIntervalSince1970: 0), now: Date()), "update idle: never installs during \(name)")
    }
    let now = Date(timeIntervalSince1970: 1_000_000)
    check(!I.mayInstall(quiet, idleSince: nil, now: now), "update idle: not before idleness is seen")
    check(!I.mayInstall(quiet, idleSince: now.addingTimeInterval(-I.settle + 1), now: now), "update idle: not until it has held \(Int(I.settle)) s")
    check(I.mayInstall(quiet, idleSince: now.addingTimeInterval(-I.settle), now: now), "update idle: once it has held, it installs")
    check(I.jobBusy([.queued]) && I.jobBusy([.done("x"), .running(step: "s")]) && I.jobBusy([.awaitingApproval(id: "a")]),
          "update idle: a queued, running or approval-waiting job is busy")
    check(!I.jobBusy([.done("x"), .failed("y"), .cancelled]) && !I.jobBusy([]), "update idle: finished jobs are not")
}

// MARK: - The pill's state machine

private func updatePillTests() {
    var p = ArisUpdatePill()
    check(p.phase == .none, "update pill: nothing up at first")
    check(p.on(.checkStarted(userInitiated: false)).phase == .none, "update pill: a background check shows nothing")
    p = p.on(.checkStarted(userInitiated: true))
    check(p.phase == .checking, "update pill: a check the user asked for is under way")
    check(p.on(.notFound(userInitiated: true)).phase == .upToDate && p.on(.notFound(userInitiated: false)).phase == .none,
          "update pill: nothing newer: 최신 버전이에요 only when asked")
    p = p.on(.found(version: "1.3.0"))
    check(p.phase == .available && p.version == "1.3.0", "update pill: a new version is offered")
    check(p.on(.dismissed) == ArisUpdatePill(), "update pill: 나중에 takes it down")
    p = p.on(.downloadStarted)
    check(p.phase == .downloading(nil) && p.version == "1.3.0", "update pill: 지금 업데이트 → downloading, length unknown yet")
    p = p.on(.expectedLength(1_000))
    check(p.phase == .downloading(0), "update pill: the length known, the bar starts at 0")
    p = p.on(.received(250)).on(.received(250))
    check(p.phase == .downloading(0.5), "update pill: half received, half the bar")
    p = p.on(.received(900))
    check(p.phase == .downloading(1), "update pill: the bar never goes past full")
    let unknown = ArisUpdatePill(phase: .available, version: "1.3.0").on(.downloadStarted).on(.received(500))
    check(unknown.phase == .downloading(nil), "update pill: without a length the bar stays empty (nothing pulses)")
    p = p.on(.extracting)
    check(p.phase == .installing, "update pill: unpacking → installing")
    check(p.on(.installing).phase == .installing, "update pill: installing stays installing until Aris opens again")
    let failed = p.on(.failed(.install))
    check(failed.phase == .failed(.install) && failed.version == "1.3.0", "update pill: an error is one line")
    check(failed.on(.checkStarted(userInitiated: true)).phase == .checking, "update pill: a new check after an error")
    check(ArisUpdatePill(phase: .available, version: "1.3.0").on(.checkStarted(userInitiated: true)).phase == .available,
          "update pill: an offer already up stays up through another check")
    check(ArisUpdateFailure.of(domain: NSURLErrorDomain, code: -1009) == .network
          && ArisUpdateFailure.of(domain: "SUSparkleErrorDomain", code: 2001) == .network
          && ArisUpdateFailure.of(domain: "SUSparkleErrorDomain", code: 3001) == .signature
          && ArisUpdateFailure.of(domain: "SUSparkleErrorDomain", code: 4005) == .install
          && ArisUpdateFailure.of(domain: "Other", code: 1) == .other, "update pill: errors sorted into four lines")
}

private func updateNoticeTests() {
    let id = UUID()
    let offer = ArisUpdatePill(phase: .available, version: "1.3").notice(id: id, current: "1.2.1", english: false)
    check(offer?.title == "새 버전 1.3이 나왔어요" && offer?.key == ArisUpdateWords.key && offer?.id == id,
          "update notice: 새 버전 1.3이 나왔어요 (the particle follows the number)")
    check(ArisUpdatePill(phase: .available, version: "1.2").notice(current: "1.2.1", english: false)?.title == "새 버전 1.2가 나왔어요",
          "update notice: 새 버전 1.2가 나왔어요")
    check(offer?.orderedActions.map(\.title) == ["나중에", "지금 업데이트"] && offer?.orderedActions.last?.primary == true
          && offer?.orderedActions.map(\.role) == [.laterUpdate, .installUpdate], "update notice: on hover, 나중에 then 지금 업데이트 (the main one)")
    check(offer?.progress == nil && offer?.showsFor == nil, "update notice: the offer has no bar and stays until answered")
    let english = ArisUpdatePill(phase: .available, version: "1.3").notice(current: "1.2.1", english: true)
    check(english?.title == "Aris 1.3 is available" && english?.orderedActions.map(\.title) == ["Later", "Update now"], "update notice: English")
    let down = ArisUpdatePill(phase: .downloading(0.42), version: "1.3").notice(id: id, current: "1.2.1", english: false)
    check(down?.progress == 0.42 && down?.actions.isEmpty == true && down?.id == id && down?.title == "새 버전 1.3 받는 중",
          "update notice: downloading: the same notice, a bar, no buttons")
    check(ArisNoticePillRules.trailing(down!, now: Date(), english: false) == .progress(0.42), "update notice: the bar stands where the time does")
    check(ArisNoticePillFit.trailingWidth(.progress(0.4)) == ArisNoticePillLayout.progressWidth, "update notice: the line's width counts the bar")
    check(ArisUpdatePill(phase: .downloading(nil), version: "1.3").notice(current: "1", english: false)?.progress == 0, "update notice: unknown length: an empty bar")
    check(ArisNotice(kind: .system, title: "t", body: "", progress: 3).progress == 1 && ArisNotice(kind: .system, title: "t", body: "", progress: -1).progress == 0,
          "update notice: progress is kept within 0…1")
    let installing = ArisUpdatePill(phase: .installing, version: "1.3").notice(current: "1.2.1", english: false)
    check(installing?.progress == 1 && installing?.body == "곧 다시 열려요.", "update notice: installing, then it opens again")
    let latest = ArisUpdatePill(phase: .upToDate).notice(current: "1.2.1", english: false)
    check(latest?.title == "최신 버전이에요" && latest?.body == "버전 1.2.1" && latest?.showsFor != nil, "update notice: up to date goes by itself")
    let error = ArisUpdatePill(phase: .failed(.network), version: "1.3").notice(current: "1.2.1", english: false)
    check(error?.kind == .problem && error?.title == "업데이트하지 못했어요" && error?.body.contains("\n") == false && error?.showsFor != nil,
          "update notice: an error is one line that goes by itself")
    check(ArisUpdatePill().notice(current: "1", english: false) == nil && ArisUpdatePill(phase: .checking).notice(current: "1", english: false) == nil,
          "update notice: nothing for no update or a check under way")
    for why in [ArisUpdateFailure.network, .signature, .install, .other] {
        check(!ArisUpdateWords.failure(why, english: false).isEmpty && !ArisUpdateWords.failure(why, english: true).isEmpty, "update notice: \(why) has its line in both languages")
    }
}

private func updateRelaunchTests() {
    typealias R = ArisUpdateRelaunch
    check(!R.restartsHelper(last: nil, current: "1.2.1"), "update relaunch: a first launch restarts nothing")
    check(!R.restartsHelper(last: "1.2.1", current: "1.2.1"), "update relaunch: the same version restarts nothing")
    check(R.restartsHelper(last: "1.2.98", current: "1.2.99"), "update relaunch: a new version restarts the helper")
}

// MARK: - The appcast (dry run: a fixed signature, no key, no network)

private func updateAppcastTests() {
    let signature = Data(repeating: 0xAB, count: 64).base64EncodedString()
    let line = "sparkle:edSignature=\"\(signature)\" length=\"12345678\""
    let parsed = ArisAppcast.parseSignUpdate(line)
    check(parsed?.signature == signature && parsed?.length == 12_345_678, "appcast: sign_update's line read")
    check(ArisAppcast.parseSignUpdate("sparkle:edSignature=\"c2hvcnQ=\" length=\"1\"") == nil && ArisAppcast.parseSignUpdate("error") == nil
          && ArisAppcast.parseSignUpdate("sparkle:edSignature=\"\(signature)\" length=\"0\"") == nil, "appcast: anything else is refused")
    check(ArisAppcast.downloadURL(version: "1.3.0") == "https://github.com/LumenJSN/Aris/releases/download/v1.3.0/Aris-1.3.0.zip",
          "appcast: the zip on its release")
    let item = ArisAppcast.Item(version: "1.3.0", shortVersion: "1.3.0", url: ArisAppcast.downloadURL(version: "1.3.0"), length: 12_345_678,
                                edSignature: signature, minimumSystemVersion: "14.0", date: Date(timeIntervalSince1970: 1_763_300_000))
    let xml = ArisAppcast.xml(items: [item])
    guard let doc = try? XMLDocument(xmlString: xml, options: []), let root = doc.rootElement() else { return check(false, "appcast: is XML") }
    check(root.name == "rss" && root.attribute(forName: "version")?.stringValue == "2.0"
          && root.namespace(forPrefix: "sparkle")?.stringValue == ArisAppcast.sparkleNamespace, "appcast: RSS 2.0 with Sparkle's namespace")
    let value = { (path: String) in (try? doc.nodes(forXPath: path))?.first?.stringValue }
    check(value("/rss/channel/item/title") == "Aris 1.3" && value("/rss/channel/item/sparkle:version") == "1.3.0"
          && value("/rss/channel/item/sparkle:shortVersionString") == "1.3.0" && value("/rss/channel/item/sparkle:minimumSystemVersion") == "14.0",
          "appcast: title, version and macOS 14")
    check(value("/rss/channel/item/enclosure/@url") == item.url && value("/rss/channel/item/enclosure/@length") == "12345678"
          && value("/rss/channel/item/enclosure/@sparkle:edSignature") == signature, "appcast: the enclosure carries the zip, its length and signature")
    check(value("/rss/channel/item/pubDate") == "Sun, 16 Nov 2025 13:33:20 +0000", "appcast: an RFC 822 date in UTC")
    check(ArisAppcast.escape("a&b<\"c\">") == "a&amp;b&lt;&quot;c&quot;&gt;", "appcast: text escaped")
}

// MARK: - Settings

private func updateSettingsTests() {
    var s = ArisSettingsSnapshot()
    check(!ArisSettingsBuilder.sections(.about, s).contains { $0.id == "about.update" }, "update settings: no 업데이트 section in a build without an updater")
    s.updates = true
    s.appVersion = "1.2.1"
    let rows = ArisSettingsBuilder.sections(.about, s).first { $0.id == "about.update" }?.rows ?? []
    check(rows.map(\.id) == ["about.autoUpdate", "about.checkUpdate"], "update settings: 자동으로 업데이트, then 업데이트 확인")
    check(rows.first?.title == "자동으로 업데이트" && rows.first?.control == .toggle(.autoUpdate, true), "update settings: 자동으로 업데이트 is on by default")
    s.autoUpdate = false
    check(ArisSettingsBuilder.sections(.about, s).flatMap(\.rows).first { $0.id == "about.autoUpdate" }?.control == .toggle(.autoUpdate, false),
          "update settings: the switch shows what is stored")
    check(rows.last?.title == "업데이트 확인" && rows.last?.desc == "지금 버전 1.2.1"
          && rows.last?.control == .buttons([ArisSettingButton(title: "확인하기", action: .checkUpdate)]), "update settings: 업데이트 확인 with the current version")
    check(ArisSettingsIndex.entry("about.autoUpdate") != nil && ArisSettingsIndex.entry("about.checkUpdate") != nil
          && ArisSettingsIndex.search("업데이트").contains { $0.id == "about.checkUpdate" }, "update settings: both rows are in the search")
    check(ArisSettingsBuilder.sections(.about, s).filter { $0.id == "about.update" }.count == 1, "update settings: one row per setting, one section")
    let catalog = updateSource("Aris/components/Settings/Settings.xcstrings")
    for korean in ["업데이트", "자동으로 업데이트", "새 버전을 받아 두었다가 Aris가 쉴 때 설치하고 다시 열어요.", "업데이트 확인", "지금 버전 %@", "확인하기"] {
        check(catalog.contains("\"\(korean)\": {"), "update settings: \"\(korean)\" has its English")
    }
}

// MARK: - Wiring

private func updateWiringTests() {
    let updater = updateSource("Aris/private/Aris/Update/ArisUpdater.swift")
    check(updater.contains("guard isOn else { return log.notice(") && updater.range(of: "guard isOn")!.lowerBound < updater.range(of: "SPUUpdater(hostBundle")!.lowerBound,
          "update wiring: no SPUUpdater is made in a build that is off")
    check(!updater.contains("SPUStandardUpdaterController") && !updater.contains("SPUStandardUserDriver") && updater.contains("final class ArisUpdateDriver: NSObject, SPUUserDriver"),
          "update wiring: Sparkle's own windows are never used: Aris's user driver")
    check(updater.contains("ArisUpdatePolicy.feed(info: Bundle.main.infoDictionary") && updater.contains("func feedURLString(for updater: SPUUpdater)"),
          "update wiring: the feed always comes from the delegate (a stray SUFeedURL default is never read)")
    check(updater.contains("willInstallUpdateOnQuit") && updater.contains("installWhenIdle(version: item.displayVersionString, immediateInstallHandler)")
          && updater.contains("ArisUpdateIdle.mayInstall(activity, idleSince: idleSince, now: now)"), "update wiring: an automatic update installs when Aris is idle")
    check(updater.contains("ArisHelperClient.shared.restartArisAgent()") && updater.contains("ArisUpdateRelaunch.restartsHelper(last: last, current: currentVersion)"),
          "update wiring: the helper starts again on the new version")
    check(updater.contains("updater.automaticallyDownloadsUpdates = Defaults[.arisAutoUpdate]") && updater.contains("Key<Bool>(\"arisAutoUpdate\", default: true)"),
          "update wiring: 자동으로 업데이트 (on by default) is Sparkle's background download")
    let entry = updateSource("Aris/private/App/ArisEntry.swift")
    check(entry.contains("ArisUpdater.shared.start()"), "update wiring: started at launch")
    let center = updateSource("Aris/private/Aris/Notice/ArisNoticeCenter.swift")
    check(center.contains("return ArisUpdater.shared.installNow()") && center.contains("return ArisUpdater.shared.later()")
          && center.contains("ArisUpdater.shared.noticeClosed()"), "update wiring: the pill's buttons and ✕ answer the updater")
    let plist = updateSource("Aris/Info.plist") + updateSource("Aris/Aris.entitlements")
    check(plist.contains("SUFeedURL") && plist.contains("SUPublicEDKey") && plist.contains("-spks"),
          "update wiring: the public build's Info.plist and entitlements carry the feed, the key and the installer exception")
    let project = updateSource("Aris.xcodeproj/project.pbxproj")
    check(project.contains("repositoryURL = \"https://github.com/sparkle-project/Sparkle\";") && project.contains("kind = exactVersion;\n\t\t\t\tversion = 2.10.1;"),
          "update wiring: Sparkle 2.10.1, pinned exactly")
    let view = updateSource("Aris/private/Aris/Notice/ArisNoticePillView.swift")
    check(view.contains("struct ArisNoticeProgressBar: View") && !view.contains("repeatForever"), "update wiring: the bar is its own view, and nothing repeats")
}
