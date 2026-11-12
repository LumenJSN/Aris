// Acceptance tests for the clean-room shelf (cleanroom-specs/07-shelf.md, 06 item loading).
import AppKit
import Foundation

private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

func runShelfTestsBlocking() {
    let done = Box(false)
    Task { @MainActor in
        shelfCodingTests()
        shelfNameTests()
        selectionTests()
        debounceTests()
        await itemLoadingTests()
        await intakeTests()
        storeTests()
        await shareTimeoutTests()
        sharingTests()
        done.value = true
    }
    while !done.value { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
}

private let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("aris-shelf-tests-\(UUID().uuidString)")

private func shelfCodingTests() {
    let fixture = """
    [
      { "id" : "6F0E4B1C-3D2A-4E5F-9A8B-1C2D3E4F5A6B", "isTemporary" : false, "kind" : { "type" : "text", "value" : "  hello  " } },
      { "id" : "7A1B2C3D-4E5F-4A6B-8C9D-0E1F2A3B4C5D", "isTemporary" : false, "kind" : { "type" : "link", "value" : "https:\\/\\/example.com\\/a" } },
      { "id" : "8B2C3D4E-5F6A-4B7C-9D0E-1F2A3B4C5D6E", "isTemporary" : true, "kind" : { "type" : "file", "value" : "AAECAw==" } }
    ]
    """
    let items = try? JSONDecoder().decode([ShelfItem].self, from: Data(fixture.utf8))
    check(items?.count == 3 && items?[0].kind == .text("  hello  ") && items?[1].kind == .link(URL(string: "https://example.com/a")!)
          && items?[2].kind == .file(bookmark: Data([0, 1, 2, 3])) && items?[2].isTemporary == true,
          "shelf items: the stored items.json shape decodes (text, link, file as base64 bookmark)")
    let encoded = items.flatMap { try? JSONEncoder().encode($0) }
    let again = encoded.flatMap { try? JSONDecoder().decode([ShelfItem].self, from: $0) }
    check(again == items, "shelf items: encode / decode round-trip")
    let object = encoded.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] }
    let kind = object?[2]["kind"] as? [String: Any]
    check(kind?["type"] as? String == "file" && kind?["value"] as? String == "AAECAw==" && object?[2]["isTemporary"] as? Bool == true,
          "shelf items: written in the same shape")
    let archive = ArisShelfArchive(file: scratch.appendingPathComponent("Shelf/items.json"))
    check(archive.load().isEmpty, "shelf archive: a missing file is an empty shelf")
    archive.save(items ?? [])
    check(archive.load() == items, "shelf archive: saved and loaded")
    let mixed = """
    [ { "id" : "6F0E4B1C-3D2A-4E5F-9A8B-1C2D3E4F5A6B", "isTemporary" : false, "kind" : { "type" : "text", "value" : "kept" } },
      { "id" : "not-a-uuid", "kind" : { "type" : "text", "value" : "bad id" } },
      { "id" : "7A1B2C3D-4E5F-4A6B-8C9D-0E1F2A3B4C5D", "isTemporary" : false, "kind" : { "type" : "mystery", "value" : 1 } },
      { "id" : "8B2C3D4E-5F6A-4B7C-9D0E-1F2A3B4C5D6E", "isTemporary" : false, "kind" : { "type" : "link", "value" : "https:\\/\\/a.b" } } ]
    """
    try? Data(mixed.utf8).write(to: archive.file)
    let partial = archive.read()
    check(partial.intact && partial.items.map(\.kind) == [.text("kept"), .link(URL(string: "https://a.b")!)],
          "shelf archive: bad items are skipped, the good ones load")
    try? Data("not json".utf8).write(to: archive.file)
    let broken = archive.read()
    check(!broken.intact && broken.items.isEmpty && (try? Data(contentsOf: archive.corruptCopy)) == Data("not json".utf8),
          "shelf archive: an unreadable file loads as empty, reported, with a .corrupt copy kept")
}

private func shelfNameTests() {
    check(ArisShelfNames.text("\n  A note \n") == "A note", "shelf names: text is trimmed")
    check(ArisShelfNames.link(URL(string: "https://www.apple.com/macos")!) == "www.apple.com/macos"
          && ArisShelfNames.link(URL(string: "http://a.b")!) == "a.b" && ArisShelfNames.link(URL(string: "ftp://a.b")!) == "ftp://a.b",
          "shelf names: links lose https:// or http://")
    let long = String(repeating: "x", count: 60)
    check(ArisShelfNames.textBlock(Data(#"{"content":"first\nsecond","title":"Title"}"#.utf8)) == "Title"
          && ArisShelfNames.textBlock(Data(#"{"content":"first\nsecond","title":""}"#.utf8)) == "first"
          && ArisShelfNames.textBlock(Data("{\"content\":\"\(long)\"}".utf8)) == String(repeating: "x", count: 47) + "..."
          && ArisShelfNames.textBlock(Data("{\"content\":\"\(String(repeating: "y", count: 50))\"}".utf8)) == String(repeating: "y", count: 50)
          && ArisShelfNames.textBlock(Data(#"{"title":"no content"}"#.utf8)) == nil, "shelf names: TextBlocks title, else first line (47 + ... past 50)")
    let titled = try! PropertyListSerialization.data(fromPropertyList: ["URL": "https://a.b", "Title": "A"], format: .xml, options: 0)
    let bare = try! PropertyListSerialization.data(fromPropertyList: ["URL": "https://a.b"], format: .binary, options: 0)
    check(ArisShelfNames.webLoc(titled) == "A" && ArisShelfNames.webLoc(bare) == "https://a.b" && ArisShelfNames.webLoc(Data("x".utf8)) == nil,
          "shelf names: WebLocs title, else URL")
    try? FileManager.default.createDirectory(at: scratch.appendingPathComponent("TextBlocks"), withIntermediateDirectories: true)
    let block = scratch.appendingPathComponent("TextBlocks/b.json")
    try? Data(#"{"content":"Shopping list\nmilk"}"#.utf8).write(to: block)
    let plain = scratch.appendingPathComponent("Report.pdf")
    try? Data().write(to: plain)
    check(ArisShelfNames.file(block) == "Shopping list" && ArisShelfNames.file(plain).hasPrefix("Report"), "shelf names: files")
}

private func selectionTests() {
    let ids = (0..<5).map { _ in UUID() }
    var selection = ArisShelfSelection()
    selection.click(ids[1], shift: false, command: false, order: ids)
    check(selection.selected == [ids[1]], "selection: a click selects one")
    selection.click(ids[3], shift: true, command: false, order: ids)
    check(selection.selected == Set(ids[1...3]), "selection: ⇧-click extends from the anchor")
    selection.click(ids[0], shift: true, command: false, order: ids)
    check(selection.selected == Set(ids[0...1]), "selection: ⇧-click the other way, from the same anchor")
    selection.click(ids[4], shift: false, command: true, order: ids)
    check(selection.selected == Set([ids[0], ids[1], ids[4]]), "selection: ⌘-click adds")
    selection.click(ids[0], shift: false, command: true, order: ids)
    check(selection.selected == Set([ids[1], ids[4]]), "selection: ⌘-click removes")
    selection.focus(ids[4])
    check(selection.selected == Set([ids[1], ids[4]]), "selection: right-clicking a selected tile keeps the selection")
    selection.focus(ids[2])
    check(selection.selected == [ids[2]], "selection: right-clicking another tile selects just it")
}

private func debounceTests() {
    var scheduled: [() -> Void] = []
    var saves = 0
    let debouncer = ArisDebouncer(delay: 1) { _, work in scheduled.append(work) }
    debouncer.call { saves += 1 }
    debouncer.call { saves += 1 }
    debouncer.call { saves += 1 }
    scheduled.forEach { $0() }
    check(saves == 1, "shelf save: three changes within the delay save once")
    debouncer.call { saves += 1 }
    debouncer.flush()
    check(saves == 2, "shelf save: a flush saves at once")
    scheduled.removeAll()
    debouncer.call { saves += 1 }
    debouncer.flush()
    scheduled.forEach { $0() }
    check(saves == 3, "shelf save: a flushed save isn't repeated when its timer fires")
}

private func itemLoadingTests() async {
    let file = scratch.appendingPathComponent("doc.txt")
    try? Data("x".utf8).write(to: file)
    let bookmark = try? file.bookmarkData()
    typealias R = ArisItemResolution
    check(R.url(from: file) == file && R.url(from: Data("https://a.b/c".utf8)) == URL(string: "https://a.b/c")
          && R.url(from: "/tmp/x") == URL(fileURLWithPath: "/tmp/x") && R.url(from: Data("/tmp/y".utf8)) == URL(fileURLWithPath: "/tmp/y")
          && R.url(from: bookmark)?.standardizedFileURL.path == file.standardizedFileURL.path
          && R.url(from: Data([0xFF, 0xFE, 0x00])) == nil && R.url(from: 42) == nil, "item loading: URL, URL text, path, bookmark, garbage")
    check(R.url(fromText: "example") == nil, "item loading: a web URL needs a scheme")
    let promises = scratch.appendingPathComponent("\(R.promiseFolderMarker)/abc")
    try? FileManager.default.createDirectory(at: promises, withIntermediateDirectories: true)
    let promised = promises.appendingPathComponent("photo.jpg")
    try? Data([1, 2, 3]).write(to: promised)
    check(R.takePromisedData(at: promised) == Data([1, 2, 3]) && !FileManager.default.fileExists(atPath: promised.path)
          && !FileManager.default.fileExists(atPath: promises.path), "item loading: a promised file is read, then it and its empty folder go")
    check(R.takePromisedData(at: file) == nil && FileManager.default.fileExists(atPath: file.path), "item loading: other files are not read")
    let provider = NSItemProvider()
    provider.registerDataRepresentation(forTypeIdentifier: "public.plain-text", visibility: .all) { $0(Data("plain".utf8), nil); return nil }
    provider.registerDataRepresentation(forTypeIdentifier: "public.utf8-plain-text", visibility: .all) { $0(Data("utf8".utf8), nil); return nil }
    let text = await provider.extractText()
    check(text == "utf8", "item loading: UTF-8 text first")
}

private struct FakeSource: ArisShelfSource {
    var file: URL?, web: URL?, string: String?, bytes: (Data, String?)?, any: URL?
    func fileURL() async -> URL? { file }
    func webURL() async -> URL? { web }
    func text() async -> String? { string }
    func data() async -> (data: Data, name: String?)? { bytes }
    func anyItem() async -> URL? { any }
}

private func intakeTests() async {
    let temp = ArisShelfTempFiles(root: scratch.appendingPathComponent("temp"))
    try? FileManager.default.createDirectory(at: temp.root, withIntermediateDirectories: true)
    let file = scratch.appendingPathComponent("doc.txt")
    let web = URL(string: "https://example.com")!
    let first = await ArisShelfIntake.item(from: FakeSource(file: file, web: web, string: "t"), temp: temp)
    check(first.map { if case .file = $0.kind { $0.fileURL?.lastPathComponent == "doc.txt" } else { false } } == true,
          "intake: a file URL wins")
    let link = await ArisShelfIntake.item(from: FakeSource(web: web, string: "t"), temp: temp)
    check(link?.kind == .link(web), "intake: then a web URL (a link)")
    let viaURL = await ArisShelfIntake.item(from: FakeSource(web: file, string: "t"), temp: temp)
    check(viaURL.map { if case .file = $0.kind { true } else { false } } == true, "intake: a file: URL among URLs is a file")
    let text = await ArisShelfIntake.item(from: FakeSource(string: "words", bytes: (Data([1]), nil)), temp: temp)
    check(text?.kind == .text("words"), "intake: then text")
    let data = await ArisShelfIntake.item(from: FakeSource(bytes: (Data([1, 2]), "pic.png")), temp: temp)
    let written = data?.fileURL
    check(data?.isTemporary == true && written?.lastPathComponent == "pic.png" && written.map { temp.owns($0) } == true,
          "intake: then data, written to a temporary file under its suggested name")
    let any = await ArisShelfIntake.item(from: FakeSource(any: file), temp: temp)
    check(any.map { if case .file = $0.kind { true } else { false } } == true, "intake: last, any item resolving to a file")
    check(await ArisShelfIntake.item(from: FakeSource(), temp: temp) == nil, "intake: nothing usable, no item")
    let note = temp.text("hello")
    let site = temp.link(URL(string: "https://www.example.org/x")!)
    let plist = site.flatMap { try? Data(contentsOf: $0) }.flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: String] }
    check(note?.pathExtension == "txt" && site?.lastPathComponent == "www.example.org.webloc" && plist == ["URL": "https://www.example.org/x"],
          "temp files: text as .txt, links as a .webloc named after the host")
    if let written { temp.remove(written) }
    check(written.map { !FileManager.default.fileExists(atPath: $0.deletingLastPathComponent().path) } == true,
          "temp files: removing deletes the file and its folder")
    temp.remove(file)
    check(FileManager.default.fileExists(atPath: file.path), "temp files: files outside the temporary folder are left alone")
}

@MainActor
private func storeTests() {
    let archive = ArisShelfArchive(file: scratch.appendingPathComponent("store/items.json"))
    var scheduled: [() -> Void] = []
    let temp = ArisShelfTempFiles(root: scratch.appendingPathComponent("temp"))
    let store = ShelfStateViewModel(archive: archive, temp: temp, saver: ArisDebouncer(delay: 1) { _, work in scheduled.append(work) })
    let a = ShelfItem(kind: .text("a")), b = ShelfItem(kind: .link(URL(string: "https://b.c")!)), again = ShelfItem(kind: .text("a"))
    store.add([a, b, again])
    check(store.items.map(\.id) == [a.id, b.id] && !store.isEmpty, "store: duplicates (same identity) are added once, in order")
    check(store.ordered(reversed: true).map(\.id) == [b.id, a.id], "store: reverse ordering")
    check(archive.load().isEmpty, "store: saving waits for the debounce")
    scheduled.forEach { $0() }
    check(archive.load().map(\.id) == [a.id, b.id], "store: then saves")
    let data = ShelfItem(kind: .file(bookmark: ArisBookmark.make(for: temp.data(Data([9]), named: "t.bin")!)!.data), isTemporary: true)
    let folder = data.fileURL?.deletingLastPathComponent()
    store.add([data])
    store.remove(data)
    check(folder.map { !FileManager.default.fileExists(atPath: $0.path) } == true, "store: removing a temporary item deletes its file")
    store.remove(a)
    store.flushSync()
    check(archive.load().map(\.id) == [b.id], "store: flush saves at once")

    let damaged = ArisShelfArchive(file: scratch.appendingPathComponent("damaged/items.json"))
    try? FileManager.default.createDirectory(at: damaged.file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? Data("{ half a file".utf8).write(to: damaged.file)
    let guarded = ShelfStateViewModel(archive: damaged, temp: temp, saver: ArisDebouncer(delay: 1) { _, work in work() })
    guarded.flushSync()
    check(guarded.isEmpty && (try? Data(contentsOf: damaged.file)) == Data("{ half a file".utf8),
          "store: an unreadable items.json isn't overwritten at quit")
    guarded.add([ShelfItem(kind: .text("new"))])
    guarded.flushSync()
    check(damaged.read().items.map(\.kind) == [.text("new")], "store: a change by the user saves over it")

    let note = ArisShelfTempFiles().text("scratch")!
    ArisShelfTempFiles.markScratch(note)
    ArisShelfTempFiles.removeScratch()
    check(!FileManager.default.fileExists(atPath: note.deletingLastPathComponent().path), "temp files: scratch files go at quit")

    let file = scratch.appendingPathComponent("doc.txt")
    let bookmark = ArisBookmark.make(for: file)!
    check(ArisBookmarkCache.shared.url(for: bookmark)?.lastPathComponent == "doc.txt"
          && bookmark.resolvedURL() == ArisBookmarkCache.shared.url(for: bookmark), "bookmarks: resolved once, then from the cache")
}

@MainActor
private func shareTimeoutTests() async {
    let sharing = SharingStateManager()
    let ended = Box(0)
    let watcher = ArisShareWatcher(sharing: sharing, timeout: 0.1) { ended.value += 1 }
    sharing.begin(keeping: watcher)
    let silent = NSSharingService(title: "Silent", image: NSImage(), alternateImage: nil) {}
    watcher.chose(silent)
    check(sharing.preventNotchClose, "share timeout: the chosen service holds the notch open")
    try? await Task.sleep(for: .milliseconds(400))
    check(!sharing.preventNotchClose && ended.value == 1, "share timeout: a service that never reports back is finished after the timeout")
    watcher.finish()
    check(ended.value == 1, "share timeout: finishing again changes nothing")
    check(ArisShareWatcher.serviceTimeout == 2, "share timeout: 2 s")
}

@MainActor
private func sharingTests() {
    let sharing = SharingStateManager()
    var posted = 0
    let token = NotificationCenter.default.addObserver(forName: .sharingDidFinish, object: nil, queue: nil) { _ in posted += 1 }
    sharing.begin()
    sharing.begin(keeping: NSObject())
    check(sharing.preventNotchClose, "sharing: the notch may not close while a share is open")
    sharing.end()
    check(sharing.preventNotchClose && posted == 0, "sharing: nested shares are counted")
    sharing.end()
    check(!sharing.preventNotchClose && posted == 1, "sharing: the last one ending posts sharingDidFinish once")
    sharing.end()
    check(posted == 1, "sharing: an extra end changes nothing")
    NotificationCenter.default.removeObserver(token)
    try? FileManager.default.removeItem(at: scratch)
}
