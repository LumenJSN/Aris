//
//  ArisGrounding.swift
//  Shared/Core (aris-agent, tests)
//
//  What "grounded in the owner's words" means, concretely, for the provenance tracker: text folded the same way
//  everywhere, the World snapshot's names (contacts and their addresses, apps and their nicknames, folder words, what
//  is in front), the words that point at content ("이 메일", "this page"), and the verbs that ask for each effect.
//  Matching is plain substring matching on folded text, so Korean particles ("민수한테") need no grammar. A value
//  shorter than two characters never matches anything. Pure.
//

import Foundation

/// The World snapshot as the tracker needs it (jv-world builds the real one; tests write their own).
struct ArisWorldFacts: Equatable, Sendable {
    struct Contact: Equatable, Sendable {
        let name: String
        var aliases: [String] = []
        var addresses: [String] = []
    }

    var contacts: [Contact] = []
    /// An app's name → its nicknames ("Safari": ["사파리"]).
    var apps: [String: [String]] = [:]
    var frontApp: String?
    /// What the owner is looking at when he speaks (jv-focus supplies it): the only thing a bare "이거" / "this" points at.
    var focus: ArisFocusObject?
    /// The owner's own addresses (sending to oneself).
    var ownerAddresses: [String] = []
    /// Folder words → paths ("다운로드": "~/Downloads"). The common ones are built in (ArisGrounding.folderWords).
    var folders: [String: String] = [:]
    /// The owner's home folder, which "~" and the folder words stand for.
    var home: String = NSHomeDirectory()

    init(contacts: [Contact] = [], apps: [String: [String]] = [:], frontApp: String? = nil, focus: ArisFocusObject? = nil,
         ownerAddresses: [String] = [], folders: [String: String] = [:], home: String = NSHomeDirectory()) {
        self.home = home
        self.contacts = contacts
        self.apps = apps
        self.frontApp = frontApp
        self.focus = focus
        self.ownerAddresses = ownerAddresses
        self.folders = folders
    }
}

/// The focus object: what the owner is looking at as he speaks (the selected mail, the front page, the selected file or
/// text), from the World snapshot. A typed hook: jv-focus fills it; nothing else may.
struct ArisFocusObject: Equatable, Sendable {
    let source: ArisContentSource
    /// A message's sender (a reply goes to them).
    var sender: String?
    /// Its text when the snapshot has it (a selection).
    var text: String?
    /// The person the focus resolver resolved for the words of the turn it was read for ("이 사람", "this person"):
    /// only a sender the app's own structure marks (the same as `sender`), never a name read from text. Nil when the
    /// words named no person or no trusted person was found.
    var resolvedPerson: String?
    /// The words of the turn the focus was resolved for: `resolvedPerson` counts only in that very turn.
    var resolvedFor: String?

    init(source: ArisContentSource, sender: String? = nil, text: String? = nil, resolvedPerson: String? = nil, resolvedFor: String? = nil) {
        self.source = source
        self.sender = sender
        self.text = text
        self.resolvedPerson = resolvedPerson
        self.resolvedFor = resolvedFor
    }

    /// The resolved person, when `turn` is the turn the focus was resolved for (the same words; one may hold the
    /// other, as a transcript and the look's words can differ by what surrounds them). Anything else: nil.
    func person(forTurn turn: String) -> String? {
        guard let person = resolvedPerson, let words = resolvedFor else { return nil }
        let said = ArisGrounding.fold(turn), resolved = ArisGrounding.fold(words)
        guard !said.isEmpty, !resolved.isEmpty, said.contains(resolved) || resolved.contains(said) else { return nil }
        return person
    }
}

enum ArisGrounding {
    /// Folded for matching: compatibility forms, lowercase, whitespace collapsed to one space.
    static func fold(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping.lowercased()
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// `value` occurs in `text` (both folded), also with the spaces taken out of both ("김 민수" in "김민수한테").
    static func contains(_ text: String, _ value: String) -> Bool {
        let needle = fold(value)
        guard needle.count >= 2 else { return false }
        let haystack = fold(text)
        if haystack.contains(needle) { return true }
        let tight = needle.replacingOccurrences(of: " ", with: "")
        return tight.count >= 2 && haystack.replacingOccurrences(of: " ", with: "").contains(tight)
    }

    // MARK: - Words

    static let folderWords: [String: String] = [
        "다운로드": "~/Downloads", "downloads": "~/Downloads", "바탕화면": "~/Desktop", "데스크탑": "~/Desktop", "desktop": "~/Desktop",
        "문서": "~/Documents", "documents": "~/Documents", "사진": "~/Pictures", "pictures": "~/Pictures", "음악": "~/Music",
        "music": "~/Music", "동영상": "~/Movies", "movies": "~/Movies", "홈 폴더": "~", "home folder": "~",
    ]

    /// Whole-word demonstratives that point only when a noun of a kind follows ("이 메일", "that page", "the README").
    static let demonstratives: Set<String> = ["이", "그", "저", "요", "this", "that", "these", "those", "the"]
    /// Words that point at the focus object alone ("이거 요약해", "선택한 거", "what I'm looking at").
    static let focusWords: Set<String> = ["이거", "이것", "이걸", "이건", "이게", "저거", "저것", "저걸", "그거", "그것", "그걸", "여기", "선택한",
                                          "선택된", "고른", "보고", "this", "that", "it", "here", "selected", "selection"]
    /// The focus words that point at a person ("이 사람한테 답장해 줘", "이 분께", "reply to this person", "answer them").
    /// They point only at the person the focus resolver resolved for this turn with a sender the app marks
    /// (ArisFocusObject.person(forTurn:)): never at the rest of the focus, never at a name read from text. "이 분 뒤"
    /// (two minutes later) is time, not a person.
    static let focusPersonWords = ["이 사람", "이 분", "this person", "them"]

    /// Whether a recipient is exactly the resolved person, compared exactly, never by containment: one recipient (no
    /// list, no second address, no display text but the person's own name), its address equal to the person's
    /// address or to an address of that person's contact (`contacts`); when the person has no address (a chat's
    /// conversation), the same name, or an address of the contact of that name. Empty or one-character values: no.
    static func isSamePerson(_ value: String, person: String, contacts: [ArisWorldFacts.Contact] = []) -> Bool {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines), person = person.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 2, person.count >= 2, !value.contains(where: { ",;\n\r".contains($0) }) else { return false }
        let given = addresses(in: value), own = addresses(in: person)
        guard given.count <= 1, own.count <= 1 else { return false }
        let personName = fold(displayName(person))
        let contactAddresses = contacts.filter { contact in
            let names = ([contact.name] + contact.aliases).map(fold)
            return (!personName.isEmpty && names.contains(personName)) || (own.first.map { contact.addresses.map(fold).contains($0) } ?? false)
        }.flatMap { $0.addresses.map(fold) }
        guard let address = given.first else {
            // A name alone: only when the person is a name alone too, and exactly that name.
            return own.isEmpty && fold(value) == fold(person)
        }
        // Nothing but the address, or the person's own name and the address ("김민수 <minsu@example.com>").
        let shown = fold(displayName(value))
        guard shown.isEmpty || (!personName.isEmpty && shown == personName) else { return false }
        return own.first == address || contactAddresses.contains(address)
    }

    /// The email addresses in a text, folded.
    static func addresses(in text: String) -> [String] {
        let pattern = #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { fold(String(text[$0])) } }
    }

    /// A text with its addresses and their brackets taken out: the display name ("김민수 <minsu@example.com>" → 김민수).
    static func displayName(_ text: String) -> String {
        var name = text
        for address in addresses(in: text) {
            name = name.replacingOccurrences(of: address, with: " ", options: .caseInsensitive)
        }
        return name.trimmingCharacters(in: CharacterSet(charactersIn: " \t<>()\"'"))
            .replacingOccurrences(of: "<>", with: "").trimmingCharacters(in: .whitespaces)
    }

    /// Whether the words point at a person (one of `focusPersonWords`, whole: "이 사람한테", "이분께", "them", never
    /// "이 분 뒤에" or "themselves").
    static func pointsAtPerson(_ text: String) -> Bool {
        let korean = #"(?<![가-힣])이\s?(사람|분)(?!\s*(뒤|후|전|동안|만에|간|짜리|정도|쯤|이내|남|지나|있다가))(한테|에게|께서|께|이|은|는|을|를|의|도|이랑|하고|들)?(?![가-힣])"#
        let english = #"(?i)\bthis person\b|\bthem\b"#
        return text.range(of: korean, options: .regularExpression) != nil || text.range(of: english, options: .regularExpression) != nil
    }

    /// Words for each kind of content, for "이 메일" / "this page".
    static let kindWords: [String: [String]] = [
        "mail": ["메일", "이메일", "mail", "email"],
        "web": ["페이지", "사이트", "웹", "링크", "기사", "탭", "page", "site", "link", "article", "tab"],
        "file": ["파일", "문서", "폴더", "readme", "file", "document", "pdf", "folder"],
        "messages": ["메시지", "문자", "카톡", "message", "text"],
        "notes": ["메모", "노트", "note"],
        "screen": ["화면", "screen"],
        "shell": ["출력", "결과", "output", "result"],
        "app": ["화면", "창", "앱", "window", "app"],
        "service": ["메일", "메시지", "이슈", "문서", "message", "issue", "doc"],
    ]

    /// Verbs that ask for an outward action.
    static let outwardVerbs = ["보내", "보낼", "전송", "답장", "회신", "답해", "전달", "공유", "올려", "게시", "포스팅", "결제", "송금", "이체", "주문",
                               "구매", "사 줘", "사줘", "메일해", "문자해", "톡해", "알려 줘 ", "send", "reply", "respond", "forward", "share", "post",
                               "publish", "pay", "buy", "order", "email", "text ", "message ", "tweet", "upload", "invite", "초대"]
    /// Verbs that ask for something that can't be taken back.
    static let permanentVerbs = ["지워", "지우", "삭제", "없애", "비워", "덮어", "실행", "돌려", "종료", "재시작", "꺼 줘", "꺼줘", "끄고", "포맷", "제거",
                                 "delete", "remove", "erase", "wipe", "overwrite", "run", "execute", "kill", "quit", "restart", "shut down",
                                 "uninstall", "empty", "clean up", "purge", "install", "설치",
                                 // Throwing away is asking to delete (tenth VM run, item 11: "휴지통에 버려 줘" counted as no
                                 // request at all, so the card said a Finder window had suggested it).
                                 "버려", "버리", "휴지통", "trash", "discard", "throw away", "throw out"]
    /// Verbs that ask to replace what is written (a field's whole text). They count only for a capability that does
    /// exactly that (`replacingCapabilities`): "이름 바꿔 줘" never asks for anything else that can't be taken back.
    static let replaceVerbs = ["바꿔", "바꾸", "교체", "대체", "고쳐 써", "다시 써", "replace", "rewrite", "change", "swap"]
    static let replacingCapabilities: Set<String> = ["app.type"]

    /// The owner's words ask for this effect of this capability: `asksFor(effect, in:)`, and for a capability that
    /// replaces text, his asking to replace or change it.
    static func asksFor(_ effect: ArisEffectClass, capability: String, in text: String) -> Bool {
        if asksFor(effect, in: text) { return true }
        return effect == .changePermanent && replacingCapabilities.contains(capability) && has(replaceVerbs, in: text)
    }
    /// Words that ask for an undo.
    static let undoVerbs = ["되돌려", "되돌리", "돌려놔", "돌려 놔", "원래대로", "원상복구", "취소해", "없던 일로", "undo", "revert", "put it back",
                            "put that back", "roll back", "rollback", "take it back", "take that back"]
    /// Verbs that ask to pay (a payment's amount or payee may then be read from what the owner points at).
    static let payVerbs = ["결제", "송금", "이체", "지불", "계산해", "구매", "구입", "주문", "사 줘", "사줘", "납부", "pay", "buy", "purchase", "order",
                           "checkout", "check out", "transfer"]
    static let replyVerbs = ["답장", "회신", "답해", "답 해", "reply", "respond", "answer"]
    /// Words that hand over the content itself ("…라고", "saying …", quotes).
    static let contentMarkers = ["라고", "이라고", "다고", "냐고", "자고", "고 해", "고 전해", "\"", "“", "‘", "'", "saying", "that says", "say ", "tell ", "전해"]

    static func asksFor(_ effect: ArisEffectClass, in text: String) -> Bool {
        switch effect {
        case .observe, .changeReversible: return true
        case .changePermanent: return has(permanentVerbs, in: text)
        case .outward: return has(outwardVerbs, in: text)
        case .never: return false
        }
    }

    /// Any of `verbs` in the text: a Korean one anywhere (particles and endings follow it), an English one only at the
    /// start of a word ("run", never "brunch").
    static func has(_ verbs: [String], in text: String) -> Bool {
        let folded = " " + fold(text) + " "
        return verbs.contains { verb in
            verb.unicodeScalars.first.map { $0.isASCII } == true ? folded.contains(" " + verb) : folded.contains(verb)
        }
    }

    /// The text's words: folded, split at spaces and punctuation.
    static func words(_ text: String) -> [String] {
        fold(text).split(whereSeparator: { $0.isWhitespace || ",.;:!?()[]{}\"'“”‘’".contains($0) }).map(String.init)
    }

    /// A demonstrative tied to a noun of `kind` ("이 메일에", "this page", "the README"): the demonstrative a whole
    /// word, the next word starting with one of the kind's nouns.
    static func pointsAtKind(_ kind: String, in text: String) -> Bool {
        let tokens = words(text), nouns = kindWords[kind] ?? [kind]
        return zip(tokens, tokens.dropFirst()).contains { first, next in demonstratives.contains(first) && nouns.contains(where: next.hasPrefix) }
    }

    /// A word that points at the focus object ("이거", "this", "선택한"), whole.
    static func pointsAtFocus(_ text: String) -> Bool {
        words(text).contains { word in focusWords.contains(word) || ["이거", "이걸", "이건", "저거", "그거"].contains(where: word.hasPrefix) }
    }

    /// Any pointing (for an app in front: "여기서 열어").
    static func points(_ text: String) -> Bool {
        pointsAtFocus(text) || kindWords.keys.contains { pointsAtKind($0, in: text) }
    }

    static func namesKind(_ kind: String, in text: String) -> Bool {
        (kindWords[kind] ?? [kind]).contains { fold(text).contains($0) }
    }

    /// The source's own name as the owner would say it: a file's name, a page's host, an app's name.
    static func names(of source: ArisContentSource) -> [String] {
        var names: [String] = []
        let last = (source.source as NSString).lastPathComponent
        if source.kind == "file" || source.source.hasPrefix("/") {
            names.append(last)
            let stem = (last as NSString).deletingPathExtension
            if stem.count >= 3 { names.append(stem) }
        }
        if let host = URL(string: source.source)?.host {
            names.append(host)
            let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            names.append(bare)
            if let first = bare.split(separator: ".").first, first.count >= 4 { names.append(String(first)) }
        }
        if source.kind == "app" || source.kind == "service" { names.append(source.source) }
        return names.filter { $0.count >= 3 }
    }

    // MARK: - Paths

    /// A path as the owner might have said it: its name, its name without the extension, and its folders' names.
    static func pathWords(_ path: String) -> [String] {
        let parts = (path as NSString).pathComponents.filter { $0 != "/" && $0 != "~" }
        guard let last = parts.last else { return [] }
        let stem = (last as NSString).deletingPathExtension
        return [last, stem].filter { $0.count >= 2 }
    }

    static func folderNames(_ path: String) -> [String] {
        (path as NSString).pathComponents.dropLast().filter { $0 != "/" && $0 != "~" && $0.count >= 3 && $0 != "Users" }
    }

    /// The folders the owner's words name (by a folder word, or a written path).
    static func namedFolders(in text: String, world: ArisWorldFacts) -> [String] {
        let folded = fold(text)
        var found = folderWords.merging(world.folders) { _, own in own }.filter { folded.contains(fold($0.key)) }.map(\.value)
        found += text.split(whereSeparator: { $0.isWhitespace }).map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "'\".,")) }
            .filter { $0.hasPrefix("/") || $0.hasPrefix("~/") }
        return found
    }

    // MARK: - Overlap

    /// The distinctive pieces of a text: words of four or more characters, numbers of three or more digits, and every
    /// address-like token (an email, a link, a path).
    static func distinctive(_ text: String) -> Set<String> {
        Set(fold(text).split(whereSeparator: { $0.isWhitespace || ",.;:!?()[]{}<>\"'“”‘’".contains($0) }).map(String.init).filter { word in
            word.count >= 4 || (word.count >= 3 && word.allSatisfy(\.isNumber)) || word.contains("@") || word.contains("/")
        })
    }

    /// How much of `body` came from `source`: the share of the body's distinctive pieces found in the source, and
    /// whether any address-like piece came from it.
    static func overlap(_ body: String, with source: String) -> (share: Double, addresses: Bool) {
        let pieces = distinctive(body)
        guard !pieces.isEmpty else { return (0, false) }
        let haystack = fold(source)
        let found = pieces.filter { haystack.contains($0) }
        return (Double(found.count) / Double(pieces.count), found.contains { $0.contains("@") || $0.contains("://") })
    }
}
