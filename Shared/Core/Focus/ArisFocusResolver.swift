//
//  ArisFocusResolver.swift
//  Shared/Core/Focus (aris-agent, app, tests)
//
//  "이거 / 여기 / 이 사람 / this" to one concrete focus. Every candidate the window offers is read the generic way, for
//  any app, from its Accessibility tree:
//    1. the region circled during this turn (the most deliberate pointing there is)
//    2. the selection: selected text, else selected rows (files, a mail message, an event, a chat, other items)
//    3. the focused field or editor (for "이거" only an editor with words in it; for "여기" any field that takes text)
//    4. the front window's document or page (AXDocument, a web area's AXURL, the browser's tab)
//    5. the element under the pointer
//    6. the front window itself
//  The words then pick (ArisFocusWords): "이거" takes that order as it is; "여기" puts the place to act first (the
//  selection, the focused field, the pointer, then the document); "마우스 가리키는 거" puts the pointer first; "이 사람"
//  takes the first candidate with a person in it and says so when there is none; a named kind ("이 메일", "these
//  files") takes the first candidate of that kind. Every focus of the window gets the same landing: the editable place
//  a reply or a rewrite goes (the selection in an editable field, the focused field, a chat's message field). Pure.
//

import Foundation

enum ArisFocusResolver {
    static let textLimit = 4_000
    static let itemsLimit = 50

    /// The candidates, by their place in the generic order.
    enum Slot: Int, Comparable, CaseIterable {
        case region, text, rows, field, document, pointer, window
        static func < (a: Slot, b: Slot) -> Bool { a.rawValue < b.rawValue }
    }

    struct Candidate: Equatable {
        var slot: Slot
        var focus: ArisFocus
        /// A field that counts for "이거" (an editor with words), not only for "여기".
        var thingField = true
    }

    static func resolve(_ words: String, _ observation: ArisFocusObservation) -> ArisFocusResolution {
        resolve(ArisFocusWords.parse(words), observation)
    }

    static func resolve(_ pointing: ArisFocusWords.Pointing, _ observation: ArisFocusObservation) -> ArisFocusResolution {
        let landing = self.landing(observation)
        let all = candidates(observation).map { candidate -> Candidate in
            var candidate = candidate
            candidate.focus.landing = landing
            return candidate
        }
        let ordered = order(all, aim: pointing.aim)
        var resolution = ArisFocusResolution(pointing: pointing)
        var chosen: Candidate?
        if let want = pointing.wants {
            chosen = ordered.first { kinds(for: want).contains($0.focus.kind) }
            if chosen == nil { resolution.missingKind = want }
        }
        if chosen == nil, pointing.aim == .person || pointing.person {
            // A trusted person first, else a name the screen only shows (a hint: an outward act to it still asks).
            chosen = ordered.first { $0.focus.person != nil } ?? ordered.first { $0.focus.mentioned != nil }
            if chosen == nil { resolution.missingPerson = true }
        }
        chosen = chosen ?? ordered.first
        resolution.focus = chosen?.focus
        var seen: Set<ArisFocus.Kind> = chosen.map { [$0.focus.kind] } ?? []
        resolution.others = ordered.filter { $0 != chosen }.compactMap { candidate in
            seen.insert(candidate.focus.kind).inserted ? candidate.focus : nil
        }.prefix(3).map { $0 }
        return resolution
    }

    /// The kinds a named kind accepts.
    static func kinds(for want: ArisFocusWords.Want) -> Set<ArisFocus.Kind> {
        switch want {
        case .mail: [.mail]
        case .file: [.files, .document]
        case .page: [.page]
        case .event: [.event]
        case .chat: [.chat]
        case .text: [.text, .region, .field, .document, .page, .pointer, .mail, .chat]
        case .image: [.region, .pointer]
        case .field: [.field]
        }
    }

    /// The candidates in the order the aim gives.
    static func order(_ candidates: [Candidate], aim: ArisFocusWords.Aim) -> [Candidate] {
        let rank: [Slot]
        switch aim {
        case .thing, .region, .person: rank = [.region, .text, .rows, .field, .document, .pointer, .window]
        case .place: rank = [.region, .text, .field, .pointer, .document, .rows, .window]
        case .pointer: rank = [.pointer, .region, .text, .rows, .field, .document, .window]
        }
        let usable = candidates.filter { aim == .place || aim == .pointer || $0.slot != .field || $0.thingField }
        return rank.flatMap { slot in usable.filter { $0.slot == slot } }
    }

    // MARK: - Candidates

    static func candidates(_ o: ArisFocusObservation) -> [Candidate] {
        let family = ArisFocusApps.family(o.app.bundleID)
        let base = ArisFocus(kind: .window, app: o.app, windowTitle: o.windowTitle, windowID: o.windowID, how: "")
        var found: [Candidate] = []
        if let region = region(o, base: base) { found.append(region) }
        guard let tree = o.tree else {
            if o.windowTitle != nil || !o.app.name.isEmpty {
                var window = base
                window.how = "the front window (Accessibility showed nothing inside it)"
                found.append(Candidate(slot: .window, focus: window))
            }
            return found
        }
        if let text = selectedText(tree, base: base) { found.append(text) }
        if let rows = selectedRows(tree, o: o, family: family, base: base) { found.append(rows) }
        if let field = focusedField(tree, base: base) { found.append(field) }
        if let document = document(tree, o: o, family: family, base: base) { found.append(document) }
        if let pointer = pointer(tree, o: o, base: base) { found.append(pointer) }
        found.append(window(tree, o: o, family: family, base: base))
        return found
    }

    static func anchor(_ tree: ArisAXNode, _ path: [Int]) -> ArisFocus.Anchor? {
        guard let node = tree.node(at: path) else { return nil }
        return ArisFocus.Anchor(path: path, role: node.role, label: node.title ?? node.label, identifier: node.identifier,
                                frame: node.frame, editable: node.editable && !node.isSecure)
    }

    private static func cut(_ text: String?, _ limit: Int = textLimit) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    static func region(_ o: ArisFocusObservation, base: ArisFocus) -> Candidate? {
        guard !o.regions.isEmpty else { return nil }
        var focus = base
        focus.kind = .region
        var texts: [String] = []
        var first: [Int]?
        if let tree = o.tree {
            for rect in o.regions {
                let paths = tree.paths(inside: rect)
                if first == nil { first = paths.first }
                texts += paths.compactMap { tree.node(at: $0)?.text(limit: textLimit) }
            }
        }
        focus.text = cut(texts.joined(separator: "\n"))
        if let first, let tree = o.tree { focus.anchor = anchor(tree, first) }
        focus.mentioned = focus.text.flatMap(ArisFocusApps.person(in:))
        focus.how = focus.text == nil ? "circled (no words inside it that Accessibility shows: the circled picture goes with the turn)" : "circled"
        return Candidate(slot: .region, focus: focus)
    }

    static func selectedText(_ tree: ArisAXNode, base: ArisFocus) -> Candidate? {
        let paths = tree.paths { !$0.isSecure && !($0.selectedText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let path = paths.first(where: { tree.node(at: $0)?.focused == true }) ?? paths.first, let node = tree.node(at: path) else { return nil }
        var focus = base
        focus.kind = .text
        focus.text = cut(node.selectedText)
        focus.anchor = anchor(tree, path)
        focus.mentioned = focus.text.flatMap(ArisFocusApps.person(in:))
        focus.how = node.editable ? "selected in an editable field" : "selected"
        return Candidate(slot: .text, focus: focus)
    }

    /// A selected row that isn't a sidebar's (the mailbox list, Finder's places): in a chat app the sidebar's row is the
    /// conversation, so it counts there.
    static func selectedRows(_ tree: ArisAXNode, o: ArisFocusObservation, family: ArisFocusApps.Family, base: ArisFocus) -> Candidate? {
        // In a file browser an item is a row (list view) or any element that names a file: Finder's icon view shows its
        // items as AXImages in a group, each with AXFilename and AXURL (VM run 2, H2: a rows-only rule saw none).
        let selectable: (ArisAXNode) -> Bool = { node in
            node.selected && (node.isRow || (family == .files && node.isFileItem)
                              || (family == .calendar && !["AXTab", "AXRadioButton", "AXMenuItem", "AXMenuBarItem", "AXWindow"].contains(node.role)))
        }
        var rows: [[Int]] = []
        for path in tree.paths(where: selectable) where !rows.contains(where: { path.starts(with: $0) }) {
            if family != .chat, inSidebar(tree, path) { continue }
            rows.append(path)
        }
        guard let first = rows.first else { return nil }
        let pieces = rows.prefix(itemsLimit).map { tree.node(at: $0).map(ArisFocusApps.pieces(of:)) ?? [] }
        var focus = base
        focus.anchor = anchor(tree, first)
        focus.items = pieces.compactMap(\.first)
        let rowText = pieces.map { $0.joined(separator: " · ") }.joined(separator: "\n")
        switch family {
        case .files:
            focus.kind = .files
            focus.text = nil
            let nodes = rows.prefix(itemsLimit).compactMap { tree.node(at: $0) }
            let urls = nodes.map(filePath(in:))
            let folder = ArisFocusApps.path(fromDocument: tree.document)
                ?? urls.compactMap { $0 }.first.map { ($0 as NSString).deletingLastPathComponent }
            focus.path = folder
            focus.items = zip(nodes, pieces).compactMap { node, pieces in fileName(in: node) ?? pieces.first }
            focus.paths = zip(urls, focus.items).compactMap { url, name in
                url ?? folder.map { ($0 as NSString).appendingPathComponent(name) }
            }
            focus.how = "selected in \(o.app.name)"
        case .mail:
            focus.kind = .mail
            let row = ArisFocusApps.mailRow(pieces[0])
            let list = listContaining(tree, first)
            let body = largestText(tree, outside: list)
            // A trusted sender only from what the app marks as the sender: its header's sender element, else the row's
            // sender cell. The row's first words and any "From:" in text are only a hint.
            focus.person = headerPerson(tree, outside: list) ?? tree.node(at: first).flatMap(ArisFocusApps.markedSender(in:))
            if focus.person == nil { focus.mentioned = headerHint(tree, outside: list) ?? row.sender }
            focus.title = row.subject
            focus.text = cut(body ?? rowText)
            focus.how = rows.count > 1 ? "\(rows.count) selected in the message list" : "selected in the message list"
        case .calendar:
            focus.kind = .event
            focus.title = pieces[0].first
            focus.text = cut(rowText)
            focus.how = "selected in \(o.app.name)"
        case .chat:
            focus.kind = .chat
            let list = listContaining(tree, first)
            // The conversation's name (the row's first words, the window's title) is a hint: only a cell the app marks as
            // the sender is trusted.
            focus.person = tree.node(at: first).flatMap(ArisFocusApps.markedSender(in:))
            if focus.person == nil {
                focus.mentioned = pieces[0].first.flatMap { looksLikeName($0) ? $0 : nil } ?? ArisFocusApps.chatPartner(title: o.windowTitle, appName: o.app.name)
            }
            focus.text = cut(conversation(tree, outside: list) ?? rowText)
            focus.how = "the open conversation"
        default:
            focus.kind = .items
            focus.text = cut(rowText)
            focus.how = rows.count > 1 ? "\(rows.count) items selected" : "selected"
        }
        return Candidate(slot: .rows, focus: focus)
    }

    static func focusedField(_ tree: ArisAXNode, base: ArisFocus) -> Candidate? {
        guard let path = tree.firstPath(where: { $0.focused && $0.isTextEntry }), let node = tree.node(at: path) else { return nil }
        var focus = base
        focus.kind = .field
        focus.text = cut(node.value)
        focus.title = node.title ?? node.label
        focus.anchor = anchor(tree, path)
        focus.how = node.editable ? "the focused field" : "the focused text"
        // For "이거" a field counts when it is an editor with words in it, never an empty or one-line box (the address
        // bar, a search field, a chat's empty message field).
        let thing = !node.isSingleLine && focus.text != nil
        return Candidate(slot: .field, focus: focus, thingField: thing)
    }

    static func document(_ tree: ArisAXNode, o: ArisFocusObservation, family: ArisFocusApps.Family, base: ArisFocus) -> Candidate? {
        var focus = base
        let webPath = tree.firstPath { $0.role == "AXWebArea" && $0.url != nil } ?? tree.firstPath { $0.role == "AXWebArea" }
        let web = webPath.flatMap { tree.node(at: $0) }
        let url = web?.url ?? (family == .browser ? o.tabURL : nil)
        if let url, !url.hasPrefix("file:") || family == .browser {
            focus.kind = .page
            focus.url = url
            focus.title = web?.title ?? o.windowTitle
            focus.text = cut(web?.text(limit: textLimit))
            focus.anchor = webPath.flatMap { anchor(tree, $0) }
            focus.mentioned = focus.text.flatMap(ArisFocusApps.person(in:))
            focus.how = "the page in front"
            return Candidate(slot: .document, focus: focus)
        }
        let documentPath: [Int]? = tree.document != nil ? [] : tree.firstPath { $0.document != nil }
        guard let documentPath, let node = tree.node(at: documentPath), let path = ArisFocusApps.path(fromDocument: node.document ?? url),
              family != .files else { return nil }
        focus.kind = .document
        focus.path = path
        focus.title = o.windowTitle ?? (path as NSString).lastPathComponent
        focus.text = cut(largestText(tree, outside: nil) ?? tree.text(limit: textLimit))
        focus.anchor = anchor(tree, documentPath)
        focus.how = "the document in front"
        return Candidate(slot: .document, focus: focus)
    }

    static func pointer(_ tree: ArisAXNode, o: ArisFocusObservation, base: ArisFocus) -> Candidate? {
        guard let point = o.pointer, var path = tree.deepestPath(at: point), !path.isEmpty else { return nil }
        // The nearest element with words, at most three steps up.
        for _ in 0..<3 where (tree.node(at: path)?.words ?? []).isEmpty && !path.isEmpty { path.removeLast() }
        guard !path.isEmpty, let node = tree.node(at: path), !node.words.isEmpty || !node.text(limit: 1).isEmpty else { return nil }
        var focus = base
        focus.kind = .pointer
        focus.text = cut(node.text(limit: textLimit))
        focus.title = node.title ?? node.label
        focus.anchor = anchor(tree, path)
        focus.mentioned = focus.text.flatMap(ArisFocusApps.person(in:))
        focus.how = "under the pointer (\(node.role.hasPrefix("AX") ? String(node.role.dropFirst(2)) : node.role))"
        return Candidate(slot: .pointer, focus: focus)
    }

    static func window(_ tree: ArisAXNode, o: ArisFocusObservation, family: ArisFocusApps.Family, base: ArisFocus) -> Candidate {
        var focus = base
        focus.text = cut(tree.text(limit: textLimit))
        focus.how = "the front window"
        switch family {
        case .chat:
            if let partner = ArisFocusApps.chatPartner(title: o.windowTitle, appName: o.app.name) {
                focus.kind = .chat
                focus.mentioned = partner
                focus.text = cut(conversation(tree, outside: nil) ?? tree.text(limit: textLimit))
                focus.how = "the open conversation"
            }
        case .mail:
            // A message open in a window of its own (no message list): the sender only from the element the app marks
            // as the sender; a "From:" line read in its text is a hint.
            if !hasList(tree), let person = headerPerson(tree, outside: nil) ?? headerHint(tree, outside: nil) {
                focus.kind = .mail
                if headerPerson(tree, outside: nil) != nil { focus.person = person } else { focus.mentioned = person }
                focus.title = o.windowTitle
                focus.how = "the message open in front"
            }
        default:
            focus.mentioned = focus.text.flatMap(ArisFocusApps.person(in:))
        }
        return Candidate(slot: .window, focus: focus)
    }

    // MARK: - Landing

    /// Where text for this window's focus goes: the selection in an editable field (typed over), the focused field (at
    /// its caret), or in a chat app its message field (the lowest field that takes text), which has to be focused first.
    static func landing(_ o: ArisFocusObservation) -> ArisFocus.Landing? {
        guard let tree = o.tree else { return nil }
        if let path = tree.firstPath(where: { $0.editable && !$0.isSecure && !($0.selectedText ?? "").isEmpty }), let anchor = anchor(tree, path) {
            return .init(anchor: anchor, mode: .replaceSelection, focused: tree.node(at: path)?.focused ?? false)
        }
        if let path = tree.firstPath(where: { $0.focused && $0.isTextEntry && $0.editable }), let anchor = anchor(tree, path) {
            return .init(anchor: anchor, mode: .insertAtCaret, focused: true)
        }
        if ArisFocusApps.family(o.app.bundleID) == .chat {
            let fields = tree.paths { $0.isTextEntry && $0.editable && $0.role != "AXSearchField" }
            let lowest = fields.max { (tree.node(at: $0)?.frame?.y ?? 0) < (tree.node(at: $1)?.frame?.y ?? 0) }
            if let lowest, let anchor = anchor(tree, lowest) { return .init(anchor: anchor, mode: .intoField, focused: false) }
        }
        return nil
    }

    // MARK: - Pieces

    /// Whether the row is in a sidebar: a source list, or a narrow list at the window's left edge with another list to
    /// its right (Finder's places beside its files; Mail's message list alone at the edge is no sidebar).
    static func inSidebar(_ tree: ArisAXNode, _ path: [Int]) -> Bool {
        let chain = tree.chain(to: path)
        if chain.contains(where: { $0.subrole == "AXSourceList" }) { return true }
        guard let window = tree.frame, window.width > 0, let list = chain.last(where: { ArisAXNode.listRoles.contains($0.role) })?.frame,
              list.x - window.x < max(40, window.width * 0.05), list.width < window.width / 3 else { return false }
        let lists = tree.paths { ArisAXNode.listRoles.contains($0.role) }.compactMap { tree.node(at: $0)?.frame }
        return lists.contains { $0.x >= list.x + list.width - 1 && $0.width > list.width / 2 }
    }

    /// The file a file browser's item is: its own AXURL, else one inside it (a list row's icon), as a path.
    static func filePath(in item: ArisAXNode) -> String? {
        var found: String?
        item.walk { node, _ in if found == nil { found = node.filePath } }
        return found
    }

    /// An item's file name: its AXFilename, else one inside it, else the last part of its URL.
    static func fileName(in item: ArisAXNode) -> String? {
        var found: String?
        item.walk { node, _ in if found == nil, let name = node.filename, !name.isEmpty { found = name } }
        return found ?? filePath(in: item).map { ($0 as NSString).lastPathComponent }
    }

    /// The list (outline, table) a row is in.
    static func listContaining(_ tree: ArisAXNode, _ path: [Int]) -> [Int]? {
        var current = path
        while !current.isEmpty {
            current.removeLast()
            if let node = tree.node(at: current), ArisAXNode.listRoles.contains(node.role) { return current }
        }
        return nil
    }

    /// The longest text block of the window (a message's body, a document's text), outside the given subtree.
    static func largestText(_ tree: ArisAXNode, outside excluded: [Int]?) -> String? {
        var best: String?
        tree.walk { node, path in
            if let excluded, path.starts(with: excluded) { return }
            guard ["AXWebArea", "AXTextArea", "AXScrollArea"].contains(node.role) || (node.role == "AXGroup" && node.children.count > 2) else { return }
            if let excluded, excluded.starts(with: path) { return }
            let text = node.text(limit: textLimit)
            if text.count > (best?.count ?? 40) { best = text }
        }
        return best
    }

    /// A chat's visible messages: the window's words outside the conversation list and its fields, in order.
    static func conversation(_ tree: ArisAXNode, outside list: [Int]?) -> String? {
        var lines: [String] = []
        tree.walk { node, path in
            if let list, path.starts(with: list) { return }
            guard ["AXStaticText", "AXTextArea"].contains(node.role), !node.editable else { return }
            for piece in node.words where lines.last != piece { lines.append(piece) }
        }
        return cut(lines.joined(separator: "\n"))
    }

    /// The trusted sender of a mail app's header: only an element the app itself marks as the sender (its identifier,
    /// or a description that is a sender label and not its own words), in native structure outside every web area (a
    /// message's body: anyone's words), every list and every row, and never one marked subject, to, cc or bcc. Nothing
    /// in an element's value is read for this: a subject whose words are "From: boss@corp.example" is a subject.
    static func headerPerson(_ tree: ArisAXNode, outside list: [Int]?) -> String? {
        var found: String?
        nativeHeader(tree, outside: list) { node in
            if found == nil, ArisFocusApps.labelsSender(node) { found = ArisFocusApps.senderValue(node) }
        }
        return found
    }

    /// A sender read from the header's words ("From: …" / "보낸 사람: …" in native text): a hint for the model, never
    /// trusted.
    static func headerHint(_ tree: ArisAXNode, outside list: [Int]?) -> String? {
        var found: String?
        nativeHeader(tree, outside: list) { node in
            guard found == nil, !ArisFocusApps.labelsOtherField(node) else { return }
            for piece in node.words where found == nil { found = ArisFocusApps.headerSender(piece) }
        }
        return found
    }

    /// The native elements outside web areas, lists, rows and the given subtree.
    private static func nativeHeader(_ tree: ArisAXNode, outside list: [Int]?, _ visit: (ArisAXNode) -> Void) {
        let fenced = tree.paths { $0.role == "AXWebArea" || ArisAXNode.listRoles.contains($0.role) || $0.isRow }
        tree.walk { node, path in
            guard !fenced.contains(where: { path.starts(with: $0) }), list.map({ !path.starts(with: $0) }) ?? true,
                  ["AXStaticText", "AXButton", "AXLink", "AXGroup", "AXTextField"].contains(node.role), !node.editable else { return }
            visit(node)
        }
    }

    /// The tree has a message list (then it isn't one message open in a window of its own).
    static func hasList(_ tree: ArisAXNode) -> Bool { tree.firstPath { ArisAXNode.listRoles.contains($0.role) } != nil }

    /// A row's first piece as a person's name: short, no unread count or time.
    static func looksLikeName(_ text: String) -> Bool {
        text.count <= 40 && !ArisFocusApps.looksLikeTime(text) && Int(text) == nil
    }
}
