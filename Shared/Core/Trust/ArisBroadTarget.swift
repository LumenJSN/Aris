//
//  ArisBroadTarget.swift
//  Shared/Core (aris-agent, tests)
//
//  A guard on what a file action removes, moves or overwrites that does not depend on the model (tenth VM run, item 2:
//  "바탕화면 vmcheck10 폴더 안의 초안.txt 파일 휴지통에 버려 줘" came to the gate as a delete of ~/Desktop/vmcheck10, the
//  whole folder, on an ordinary card). The gate reads what each target is at that moment (a file, a folder and how many
//  items it holds, nothing there, or unreadable) and this decides, after every other rule and only ever stricter:
//    · a path with nothing there, or in a home that isn't this Mac's user's: refused ("그런 경로는 없어요").
//    · a file: as decided.
//    · home, Desktop, Documents, Downloads and home's other everyday folders, a volume's root, or anything that holds
//      them: refused.
//    · a folder (or a target whose kind couldn't be read: the strict case) when the owner's words name a file, or don't
//      name that folder as a folder: refused, with what it is and how many items it holds.
//    · a folder the owner's own words name, by its name and as a folder: a card of its own every time, that says it is
//      the whole folder with N items (never a countdown, never covered by an earlier yes, never kept as "always").
//  Which calls are guarded is an allowlist of the ones known not to remove anything; a call nobody listed is guarded.
//  Pure.
//

import Foundation

/// What a path is, read at the moment of the decision.
enum ArisPathKind: Equatable, Sendable {
    case file
    /// `items`: how many things are directly inside; nil when they couldn't be counted.
    case folder(items: Int?)
    /// Nothing is there.
    case missing
    /// It couldn't be read.
    case unknown

    /// The card's word for it.
    var word: String {
        switch self {
        case .file: "파일"
        case .folder(let items): items.map { "폴더 (항목 \($0)개)" } ?? "폴더 (항목 수를 읽지 못했어요)"
        case .missing: "없는 경로"
        case .unknown: "종류를 읽지 못했어요"
        }
    }

    var isFile: Bool { self == .file }
}

struct ArisPathTarget: Equatable, Sendable {
    let path: String
    let kind: ArisPathKind

    var name: String { (path as NSString).lastPathComponent }
}

enum ArisBroadTarget {
    enum Verdict: Equatable, Sendable {
        case fine
        /// The owner named this folder as a folder: its own, stronger card.
        case wholeFolder(ArisPathTarget)
        case refuse(String)
    }

    /// aris-tools commands that never remove, move or overwrite what their paths name (they open, read, or make new
    /// files beside the originals), and the helper's own capabilities that have their own rules for it (a file written
    /// with its copy kept, a shell line by its command).
    static let harmlessCommands: Set<String> = ["folder", "open", "files", "convert", "merge", "split", "compress", "maps", "note", "link", "app"]
    static let harmlessCapabilities: Set<String> = ["file.read", "file.search", "file.write", "file.edit", "shell.run", "app.open", "app.find", "app.read",
                                                    "web.fetch", "web.search"]
    /// aris-tools commands whose first path is what moves and whose last is only where it goes.
    static let movingCommands: Set<String> = ["move", "rename"]

    /// The paths of a call this guard looks at; empty for a look, and for a call known not to remove anything.
    static func guarded(capability: String, effect: ArisEffectClass, argv: [String]?, paths: [String]) -> [String] {
        guard effect == .changeReversible || effect == .changePermanent else { return [] }
        if let argv {
            guard let command = argv.first else { return paths }
            if harmlessCommands.contains(command) { return [] }
            let plain = argv.dropFirst().filter { !$0.hasPrefix("--") }
            if movingCommands.contains(command) { return plain.first.map { [$0] } ?? paths }
            if command == "trash" { return Array(plain) }
            return paths
        }
        if harmlessCapabilities.contains(capability) || capability.hasPrefix("app.") || capability.hasPrefix("window.") { return [] }
        return paths
    }

    static let folderWords = ["폴더", "디렉터리", "디렉토리", "folder", "directory"]
    static let fileWords = ["파일", "문서", "file", "document"]

    /// A word of the owner's that reads as a file's name (something, a dot, a short extension), folded.
    static func fileNames(in said: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"[^\s/'"‘’“”「」(),]+\.[A-Za-z0-9]{1,6}(?![A-Za-z0-9])"#) else { return [] }
        let range = NSRange(said.startIndex..., in: said)
        return regex.matches(in: said, range: range).compactMap { Range($0.range, in: said).map { ArisGrounding.fold(String(said[$0])) } }
    }

    /// Home's own folders, home itself, a volume's root, the system's roots, and anything that holds home. An everyday
    /// folder is known by its last name under any /Users/<name> too (twelfth VM run, D1: the model wrote
    /// `/Users/aris/Documents` for a Mac whose home is /Users/admin, and the guard, comparing with the real home, let it by).
    static func isBroadPlace(_ path: String, home: String) -> Bool {
        let target = ArisNeverList.normalized(path, home: home), folded = ArisNeverList.normalized(home, home: home)
        if target == "/" || target == folded || folded.hasPrefix(target + "/") { return true }
        if target == "/volumes" || (target.hasPrefix("/volumes/") && target.split(separator: "/").count <= 2) { return true }
        if ArisNeverList.systemRoots.contains(where: { $0.lowercased() == target }) { return true }
        if ArisNeverList.everydayFolders.contains(where: { target == folded + "/" + $0.lowercased() }) { return true }
        let parts = target.split(separator: "/")
        return parts.count == 3 && parts[0] == "users" && everydayName(target) != nil
    }

    /// The everyday folder (Documents, Desktop…) a path's last name is, in its own spelling; nil for any other name.
    static func everydayName(_ path: String) -> String? {
        let last = (path.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) as NSString).lastPathComponent.lowercased()
        return ArisNeverList.everydayFolders.first { $0.lowercased() == last }
    }

    /// The owner's own names for home's everyday folders ("도큐멘트 폴더 통째로 지워 줘").
    static let everydayWords: [String: [String]] = [
        "Documents": ["도큐멘트", "문서 폴더", "문서폴더", "documents folder", "my documents"],
        "Desktop": ["바탕화면 폴더", "바탕 화면 폴더", "데스크탑 폴더", "데스크톱 폴더", "desktop folder"],
        "Downloads": ["다운로드 폴더", "다운로드폴더", "downloads folder"],
        "Pictures": ["사진 폴더", "픽처 폴더", "pictures folder"], "Movies": ["동영상 폴더", "무비 폴더", "movies folder"],
        "Music": ["음악 폴더", "뮤직 폴더", "music folder"],
    ]

    /// The owner's words name the everyday folder this path's last name is (wherever the path puts it).
    static func ownerNamesEveryday(_ path: String, said: String) -> Bool {
        guard let name = everydayName(path), let words = everydayWords[name] else { return false }
        return ArisGrounding.has(words, in: said)
    }

    /// `/Users/<name>` when the path is in a home that isn't this Mac's user's (one the model made up), else nil.
    /// /Users/Shared is no one's home.
    static func otherHome(_ path: String, home: String) -> String? {
        let target = ArisNeverList.normalized(path, home: home), folded = ArisNeverList.normalized(home, home: home)
        let parts = target.split(separator: "/")
        guard parts.count >= 2, parts[0] == "users", parts[1] != "shared" else { return nil }
        let owner = "/users/" + parts[1]
        return owner == folded || folded.hasPrefix(owner + "/") ? nil : "/Users/" + parts[1]
    }

    /// What the owner is shown for a protected place: the real home's, for one the model put in a made-up home.
    static func shownPlace(_ path: String, home: String) -> String {
        if otherHome(path, home: home) != nil, let name = everydayName(path) { return "~/" + name }
        return abbreviated(path, home: home)
    }

    /// What the guard says about `targets` (each read just now), given the owner's words of the turn.
    static func judge(_ targets: [ArisPathTarget], said: String, home: String) -> Verdict {
        var whole: ArisPathTarget?
        for target in targets {
            let shown = abbreviated(target.path, home: home)
            if isBroadPlace(target.path, home: home) || ownerNamesEveryday(target.path, said: said) {
                return .refuse(broadPlace(shownPlace(target.path, home: home)))
            }
            // A made-up home, or nothing there: never offered on a card (twelfth VM run, D1/D2).
            if otherHome(target.path, home: home) != nil || target.kind == .missing { return .refuse(noSuchPath(shown, home: home)) }
            if target.kind.isFile { continue }
            let name = ArisGrounding.fold(target.name)
            let others = fileNames(in: said).filter { $0 != name }
            let saysFolder = ArisGrounding.has(folderWords, in: said), saysFile = ArisGrounding.has(fileWords, in: said)
            if !others.isEmpty || (saysFile && !saysFolder) { return .refuse(namesFile(target, shown: shown)) }
            guard saysFolder, ArisGrounding.contains(said, target.name) else { return .refuse(needsName(target, shown: shown)) }
            whole = whole ?? target
        }
        return whole.map(Verdict.wholeFolder) ?? .fine
    }

    /// The decision with the guard's verdict: a refusal stays; the guard's refusal refuses; a whole folder asks.
    static func decide(_ decided: ArisDecision, _ verdict: Verdict) -> ArisDecision {
        if case .refuse = decided { return decided }
        switch verdict {
        case .fine: return decided
        case .refuse(let why): return .refuse(reason: why)
        case .wholeFolder: return .ask
        }
    }

    static func abbreviated(_ path: String, home: String) -> String {
        let expanded = path == "~" ? home : path.hasPrefix("~/") ? home + path.dropFirst(1) : path
        return expanded == home ? "~" : expanded.hasPrefix(home + "/") ? "~" + expanded.dropFirst(home.count) : expanded
    }

    static func holds(_ target: ArisPathTarget) -> String {
        switch target.kind {
        case .folder(let items?): "폴더 전체(항목 \(items)개)"
        case .folder(nil): "폴더 전체(항목 수를 읽지 못했어요)"
        case .missing: "지금 없는 경로"
        case .file, .unknown: "파일인지 폴더인지 읽지 못한 것"
        }
    }

    static func broadPlace(_ shown: String) -> String {
        "\(shown) 전체는 통째로 옮기거나 지우지 않아요. 그 안의 항목을 하나씩 말씀해 주세요. (Aris never moves or deletes that whole place.)"
    }

    static func noSuchPath(_ shown: String, home: String) -> String {
        "그런 경로는 없어요: \(shown). 이 Mac의 홈 폴더 경로: \(home). (No such path; this Mac's home folder is \(home).)"
    }

    static func namesFile(_ target: ArisPathTarget, shown: String) -> String {
        "파일 하나를 말씀하셨는데 대상이 \(shown), \(holds(target))여서 하지 않았어요. (You named one file, but the target was a whole folder: nothing was done.)"
    }

    static func needsName(_ target: ArisPathTarget, shown: String) -> String {
        "\(shown): \(holds(target))예요. 통째로 하려면 ‘\(target.name) 폴더’라고 폴더 이름을 넣어 직접 말씀해 주세요. "
            + "(That is a whole folder; say its name and that you mean the folder.)"
    }
}
