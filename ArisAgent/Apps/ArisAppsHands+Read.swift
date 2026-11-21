//
//  ArisAppsHands+Read.swift
//  aris-agent (Core 2 app layer, jv-apps)
//
//  app.read (a window as structured text with element ids, from the engine's Accessibility look; a picture of the
//  window only when the tree is empty), the calls that act on what it read (app.type, app.click, app.press,
//  app.select, app.scroll: all through the engine, in the background where the app allows), and app.recipe.
//

import Foundation

extension ArisAppsHands {
    /// A value, or the outcome to answer instead.
    enum Got<Value> {
        case ok(Value)
        case stop(ArisApps.Outcome)
    }

    /// A running app's window to read or act in: the call's `window`, else its front window, else its first.
    func readyWindow(_ arguments: ArisApps.JSON, context: Context, effect: ArisApps.Effect) -> Got<(Target, WindowInfo)> {
        var target: Target
        switch resolve(arguments["app"]?.string, effect: effect) {
        case .app(let found): target = found
        case .answer(let outcome): return .stop(outcome)
        }
        if target.running == nil {
            _ = system.open(ArisAppsOpenRequest(bundle: target.bundle, path: nil, url: nil, front: false))
            _ = waitFor { self.running(target.bundle) != nil && !self.windows(of: target.bundle).isEmpty }
            target.running = running(target.bundle)
        }
        let list = windows(of: target.bundle)
        let chosen = arguments["window"]?.int.flatMap { id in list.first { $0.id == id } } ?? list.first(where: \.front) ?? list.first
        guard let window = chosen else { return .stop(.failure("\(target.name) has no window open", effect: effect)) }
        return .ok((target, window))
    }

    /// A fresh look at the window through the engine, kept as the app's last read.
    func look(_ target: Target, _ window: WindowInfo, context: Context) -> (LastRead?, ArisApps.JSON, String) {
        let reply = Self.envelope(engine.run(["see", "--window-id", String(window.id)], background: context.background))
        guard reply.ok, let snapshot = reply.data["snapshot_id"]?.string else { return (nil, reply.data, reply.message) }
        let elements = (reply.data["ui_elements"]?.array ?? []).compactMap(ArisApps.ReadElement.init)
        let last = LastRead(snapshot: snapshot, window: window.id, elements: elements)
        lock.withLock { reads[target.bundle.lowercased()] = last }
        return (last, reply.data, "")
    }

    func read(_ arguments: ArisApps.JSON, context: Context) -> ArisApps.Outcome {
        let target: Target, window: WindowInfo
        switch readyWindow(arguments, context: context, effect: .observe) {
        case .ok(let ready): (target, window) = ready
        case .stop(let outcome): return outcome
        }
        let (last, data, problem) = look(target, window, context: context)
        guard let last else { return .failure("couldn't read \(target.name)'s window: \(problem)", effect: .observe) }
        let part = ArisApps.Read.Part(rawValue: arguments["part"]?.string ?? "all") ?? .all
        if last.elements.isEmpty {
            // Nothing in the tree: a picture of the window is the last way to see it.
            let file = NSTemporaryDirectory() + "aris-apps-\(window.id)-\(UUID().uuidString.prefix(6)).png"
            let shot = Self.envelope(engine.run(["see", "--window-id", String(window.id), "--path", file], background: context.background))
            let image = shot.data["screenshot_raw"]?.string
            return ArisApps.Outcome(ok: image != nil, did: image != nil ? "\(target.name)'s window shows nothing to Accessibility; took a picture of it" : "\(target.name)'s window shows nothing to Accessibility",
                                    now: "", data: .object(["window": .string(window.title), "image": image.map(ArisApps.JSON.string) ?? .null]),
                                    effect: .observe, channel: "vision")
        }
        let focused = data["focused_element"]?["frame"]?.array?.first?.array.flatMap { pair -> (Double, Double)? in
            guard pair.count == 2, let x = pair[0].number, let y = pair[1].number else { return nil }
            return (x, y)
        }
        let picked = ArisApps.Read.matching(arguments["find"]?.string, in: ArisApps.Read.pick(part, from: last.elements, focusedFrame: focused))
        let page = ArisApps.Read.page(picked, offset: max(0, arguments["offset"]?.int ?? 0), limit: max(500, min(20_000, arguments["limit"]?.int ?? 6_000)))
        var object: [String: ArisApps.JSON] = ["app": .string(target.name), "window": .string(data["window_title"]?.string ?? window.title),
                                               "part": .string(part.rawValue), "text": .string(page.text), "shown": .number(Double(page.shown)),
                                               "total": .number(Double(page.total))]
        if let next = page.next { object["next"] = .number(Double(next)) }
        return ArisApps.Outcome(ok: true, did: "read \(page.shown) of \(page.total) elements of \(target.name)’s “\(window.title)”" + (page.next != nil ? " (more: offset \(page.next!))" : ""),
                                now: "", data: .object(object), effect: .observe, channel: "ax", verified: true)
    }

    /// The element a call names, from the app's last read (read again when it isn't there). `exact`: a taught press's
    /// control, found only by exactly that label (fourth VM run, D5: no near match may press another control).
    func element(_ said: String, target: Target, window: WindowInfo, part: ArisApps.Read.Part?, context: Context, prefer: Set<String> = [],
                 exact: String? = nil) -> Got<(LastRead, ArisApps.ReadElement)> {
        func find(_ last: LastRead) -> ArisApps.Read.Located {
            if let exact { return ArisApps.Exact.controls(exact, in: last.elements, prefer: prefer) }
            let pool = part.map { ArisApps.Read.pick($0, from: last.elements) } ?? last.elements
            let located = ArisApps.Read.locate(said, in: pool, prefer: prefer)
            if case .none = located, part != nil { return ArisApps.Read.locate(said, in: last.elements, prefer: prefer) }
            return located
        }
        var last = lock.withLock { reads[target.bundle.lowercased()] }
        if last?.window != window.id { last = nil }
        var located = last.map(find) ?? .none
        if case .none = located, let fresh = look(target, window, context: context).0 {
            last = fresh
            located = find(fresh)
        }
        switch located {
        case .one(let found): return .ok((last!, found))
        case .several(let many):
            var outcome = ArisApps.Outcome.failure("‘\(said)’ matches \(many.count) things in \(target.name)", effect: .changeReversible,
                                                   data: .object(["matches": .array(many.map { .string($0.line()) })]))
            outcome.question = "‘\(said)’: " + many.map { $0.label.isEmpty ? $0.role : $0.label }.joined(separator: ", ") + " 중 어느 것인가요?"
            return .stop(outcome)
        case .none:
            if let exact {
                // What the app shows that is most like it, said, never pressed.
                let near = last.flatMap { ArisApps.Exact.nearest(exact, in: $0.elements) }
                return .stop(.failure(ArisApps.Exact.missingControl(exact, near: near, app: target.name), effect: .changeReversible))
            }
            return .stop(.failure("nothing called ‘\(said)’ in \(target.name)’s window (app.read shows what is there)", effect: .changeReversible))
        }
    }

    /// `app`'s text field `target` as a look taken now shows it, never the app's last read (security review of jv-quick:
    /// a read kept from before a Select All said nothing was selected, and one kept from before an edit showed a
    /// replace's card text that was no longer there). Nil when it can't be read: the app isn't running, the look
    /// fails, no such text field, or `target` is an element id, which names a kept read's element. Nothing is opened,
    /// clicked or typed.
    /// `replacing`: the field a replace means (ArisApps.Read.replaceField: an id found again by what the read printed
    /// for it, `seen`; a description that names nothing falls back to the window's one document or field).
    func freshField(app: String, target said: String?, seen: ArisApps.Grounding.Seen? = nil, replacing: Bool = false) -> ArisApps.ReadElement? {
        guard case .app(let target) = resolve(app, effect: .observe), target.running != nil else { return nil }
        let list = windows(of: target.bundle)
        if replacing {
            guard let window = list.first(where: \.front) ?? list.first else { return nil }
            let (last, data, _) = look(target, window, context: Context(background: true))
            return last.flatMap { ArisApps.Read.replaceField(said, seen: seen, in: $0.elements, focusedFrame: ArisApps.Read.focusedFrame(data)) }
        }
        // No field named (the model's own call, tenth VM run, item 4): the one app.type will take
        // (ArisApps.Read.defaultTextField), from a look taken now as well.
        guard let said, !said.isEmpty else {
            guard let window = list.first(where: \.front) ?? list.first else { return nil }
            let (last, data, _) = look(target, window, context: Context(background: true))
            return last.flatMap { ArisApps.Read.defaultTextField(in: $0.elements, focusedFrame: ArisApps.Read.focusedFrame(data)) }
        }
        if said.hasPrefix("e"), Int(said.dropFirst()) != nil { return nil }
        guard let window = list.first(where: \.front) ?? list.first,
              let fresh = look(target, window, context: Context(background: true)).0,
              case .one(let element) = ArisApps.Read.locate(said, in: fresh.elements, prefer: ArisApps.ReadElement.textRoles),
              element.isText else { return nil }
        return element
    }

    /// What app.type's replace would erase in `app`'s field `target` now: its text; nil when it can't be read.
    /// `seen`: what this turn's read printed for the id the call names (the read was taken in another process).
    func peekField(app: String, target said: String?, seen: ArisApps.Grounding.Seen? = nil) -> String? {
        freshField(app: app, target: said, seen: seen, replacing: true).map { $0.value ?? "" }
    }

    /// The field typing into `app` would go into, as a replace finds it, with what is selected in it now: for typing
    /// that follows a Select All (ArisSelectAllWatch). Nil when no such field can be read.
    func peekTyping(app: String, target said: String?, seen: ArisApps.Grounding.Seen? = nil) -> (text: String, selected: String?)? {
        freshField(app: app, target: said, seen: seen, replacing: true).map {
            ($0.value ?? "", ArisApps.ReadElement.selected(in: $0.value, range: $0.selectionRange))
        }
    }

    /// What typing into `app`'s field `target` would go over now: its selected text, "" when nothing is selected; nil
    /// when that can't be read (as `freshField`, or no selection range or text to cut it from).
    func peekSelection(app: String, target said: String?) -> String? {
        // Only a named field: with none named the typing goes where the focus is, which the look can't promise is the
        // field it would pick, so the selection counts as unread (the strict case).
        guard let said, !said.isEmpty else { return nil }
        return freshField(app: app, target: said).flatMap { ArisApps.ReadElement.selected(in: $0.value, range: $0.selectionRange) }
    }

    func type(_ arguments: ArisApps.JSON, context: Context, effect: ArisApps.Effect) -> ArisApps.Outcome {
        guard arguments["text"]?.string?.isEmpty == false else { return .failure("app.type needs the text", effect: effect) }
        let target: Target, window: WindowInfo
        switch readyWindow(arguments, context: context, effect: effect) {
        case .ok(let ready): (target, window) = ready
        case .stop(let outcome): return outcome
        }
        var field: (LastRead, ArisApps.ReadElement)?
        if let said = arguments["target"]?.string, !said.isEmpty {
            // The field as it is now, never an earlier read's: its value is what the undo is made against (fifth VM run,
            // D5: a value read before the window or the text changed made no undo at all). An element id ("e3") names
            // the last read's element, which is kept for it.
            if !(said.hasPrefix("e") && Int(said.dropFirst()) != nil) { lock.withLock { reads[target.bundle.lowercased()] = nil } }
            switch element(said, target: target, window: window, part: nil, context: context, prefer: ArisApps.ReadElement.textRoles) {
            case .ok(let found): field = found
            case .stop(let outcome):
                // A described field that isn't there: the focused one takes the text (a recipe's "message field").
                if outcome.question != nil || said.hasPrefix("e") && Int(said.dropFirst()) != nil { return outcome }
            }
        }
        // No field named (the model's own call): the one it plainly means is watched, so what is there is read first, a
        // replace keeps its copy and the typing has its undo, as a named field's does (tenth VM run, item 4). It is not
        // clicked and the caret is not moved for it: the text goes where the app's focus is, and what the field holds
        // after is read back.
        var watched = field
        let replacing = arguments["replace"]?.bool == true
        let named = arguments["target"]?.string ?? ""
        let byId = named.hasPrefix("e") && Int(named.dropFirst()) != nil
        // Whether `watched` is from a look taken just now (an id's element is a kept read's).
        var freshlyRead = !byId
        if field == nil, named.isEmpty {
            let (last, data, _) = look(target, window, context: context)
            if let last, let found = ArisApps.Read.defaultTextField(in: last.elements, focusedFrame: ArisApps.Read.focusedFrame(data)) { watched = (last, found) }
        }
        // A replace sets one text field it has read just now, or nothing (eleventh VM run, C3: with a field named that
        // wasn't found the text was typed at the caret, "중간에 바뀐 글교체된 내용"; with an id the kept read's element
        // was set unchecked, over "카드 뒤에 바뀐 글"). An id's element is found again by what it is in a look taken
        // now; a description that names nothing means the window's one document or field.
        // Marked typing by an id is checked against the field as it is now too; when it can't be found again the mark
        // stops it as before (a selection that can't be read).
        if !replacing, byId, arguments[ArisApps.TypeOver.argument]?.string != nil, let (_, kept) = field, kept.isText,
           let now = look(target, window, context: context).0, let same = Self.sameField(kept, in: now.elements) {
            field = (now, same)
            watched = field
            freshlyRead = true
        }
        if replacing {
            if byId, let (_, kept) = field {
                guard let now = look(target, window, context: context).0, let same = Self.sameField(kept, in: now.elements) else {
                    return .failure(ArisApps.TypeOver.noFieldRefusal, effect: effect)
                }
                field = (now, same)
                watched = field
                freshlyRead = true
            } else if field == nil, !named.isEmpty {
                let (last, data, _) = look(target, window, context: context)
                if let last, let found = ArisApps.Read.replaceField(named, seen: nil, in: last.elements, focusedFrame: ArisApps.Read.focusedFrame(data)) { watched = (last, found) }
            }
            guard let (_, element) = watched, element.isText, element.role != "secureTextField" else {
                return .failure(ArisApps.TypeOver.noFieldRefusal, effect: effect)
            }
        }
        // at=end goes only into a text element: a described list, button or canvas is refused before anything is done.
        if Self.addsAtEnd(arguments), let (_, element) = field, !element.isText {
            return .failure("at=end puts text into a text field or document, and \(element.line()) is a \(element.role): nothing was typed", effect: effect)
        }
        // A replay's typing marked with the selection its decision saw (ArisApps.TypeOver): the field as read just now
        // (never an earlier read's: an element id can't tell) must show exactly that, or nothing is typed.
        // What typing goes over, read just now: kept first when it is erased, so the undo can put it back.
        var typedOver: String?
        do {
            let fresh = freshlyRead ? watched?.1 : nil
            if replacing {
                let holds = fresh.flatMap { $0.isText ? $0.value ?? "" : nil }
                // His yes was to a card that couldn't show the text: text that is there now stops it (he never saw it).
                if ArisApps.TypeOver.unseen(arguments, now: holds) { return .failure(ArisApps.TypeOver.unseenRefusal, effect: effect) }
                // A marked replace: the text the field holds now must be the text its card showed as erased.
                if ArisApps.TypeOver.refusesReplace(arguments, holds: holds) {
                    return .failure(ArisApps.TypeOver.replaceRefusal, effect: effect)
                }
            } else {
                let selected = fresh.flatMap { ArisApps.ReadElement.selected(in: $0.value, range: $0.selectionRange) }
                if ArisApps.TypeOver.unseen(arguments, now: selected) { return .failure(ArisApps.TypeOver.unseenRefusal, effect: effect) }
                if ArisApps.TypeOver.refuses(arguments, selected: selected) { return .failure(ArisApps.TypeOver.refusal, effect: effect) }
                if let selected, !selected.isEmpty { typedOver = fresh?.value }
            }
        }
        // A taught text that began a line: its leading line break (rated with the text) is typed only into a text area whose
        // text, as just read, doesn't already end a line; anywhere else it is left out, never added.
        let text = ArisApps.NewLine.typed(arguments, field: field?.1)
        guard !text.isEmpty else { return .failure("app.type needs the text", effect: effect) }
        var delivery = ""
        // A replace keeps what it erases first (a verified copy in the undo store), so it can be put back.
        var erasedCopy: String?
        // Typing over a selection erases it: the field's text as it was is kept the same way (every path that erases has its undo).
        let overCopy = typedOver.flatMap { $0.isEmpty ? nil : keepText?($0) }
        if let (last, element) = watched, replacing, element.isText {
            erasedCopy = (element.value ?? "").isEmpty ? nil : keepText?(element.value ?? "")
            let reply = Self.envelope(engine.run(["set-value", "--snapshot", last.snapshot, "--on", element.id, "--value", text], background: context.background))
            guard reply.ok else { return .failure("couldn't set \(element.line()): \(reply.message)", effect: effect) }
            delivery = "set"
        } else {
            if let (last, element) = field {
                let focus = Self.envelope(engine.run(["click", "--snapshot", last.snapshot, "--on", element.id], background: context.background))
                guard focus.ok else { return .failure("couldn't reach \(element.line()): \(focus.message)", effect: effect) }
            }
            // at=end: the caret goes to the end of the text first, so the text is added after what is there (VM run 2, D4:
            // "TextEdit에 … 써 줘" became select-all, a delete card, ⌘↓, type). Through Accessibility, on a text element only.
            if Self.addsAtEnd(arguments), let refusal = toEnd(field: field?.1, target: target, window: window, context: context, effect: effect) {
                return refusal
            }
            // A document's text area named with neither at nor replace: added at the end too (third VM run, D2), its caret
            // moved through Accessibility only; when it won't move, the text goes where the click left the caret.
            if Self.insertsByDefault(arguments, field: field?.1), let pid = target.running?.pid ?? running(target.bundle)?.pid {
                let point = field?.1.frame.map { (x: $0.x + $0.width / 2, y: $0.y + $0.height / 2) }
                _ = ax.caretToEnd(pid: pid, at: point)
            }
            let reply = Self.envelope(engine.run(["type", "--text", text, "--window-id", String(window.id)], background: context.background))
            guard reply.ok else { return .failure("couldn't type into \(target.name): \(reply.message)", effect: effect) }
            delivery = reply.data["delivery"]?.string ?? "typed"
        }
        // What the field holds now, read back: the undo is made from what it really holds, never from what was sent.
        var now = "", verified = false, undo: ArisUndoRecipe?
        // The field found again by what it is, looked at until it shows the text (sixth VM run, item 1: ArisAppsHands+TypeCheck).
        let holds = { (value: String) in
            value.contains(text) || value.localizedCaseInsensitiveContains(text)
                || (delivery != "set" && ArisApps.TextUndo.insertion(before: watched?.1.value ?? "", after: value) != nil)
        }
        let read = watched.flatMap { readBack(target, window, field: $0.1, context: context, settled: holds) }
        if watched != nil, read == nil { now = Self.unreadAfterTyping }
        // No field could be read at all: said, so nobody claims where the text is (tenth VM run, item 11).
        if watched == nil { now = ArisApps.TypedPlace.unread }
        if let (_, element) = watched, let (_, value) = read {
            // An empty field reads as no value (fourth VM run, D7: a new document's typing had no undo at all).
            let before = element.value ?? ""
            let added = delivery == "set" ? nil : ArisApps.TextUndo.insertion(before: before, after: value)
            // The app may correct what was typed as it goes in ("added line" became "Added line").
            verified = value.contains(text) || value.localizedCaseInsensitiveContains(text) || added != nil
            now = verified ? "the field holds the text" : "the field reads “\(value.prefix(120))”"
            // Where it landed: on a line of its own, or on a line with what was there (item 11: "첫 줄우유" was called a new line).
            if delivery != "set", let place = ArisApps.TypedPlace.note(before: before, after: value) { now += "; " + place }
            if delivery == "set" {
                if let erasedCopy {
                    undo = ArisApps.TextUndo.replaced(app: target.name, bundle: target.bundle, role: element.role, label: element.label, before: before,
                                                      after: value, copy: erasedCopy)
                } else if !before.isEmpty {
                    now += "; what it held couldn't be kept, so this can't be undone"
                }
            } else {
                // Text put in can be taken back by its own range (third VM run, D3), found again by the field's whole value
                // as read back right now: only when everything that was there is still there.
                undo = ArisApps.TextUndo.recipe(app: target.name, bundle: target.bundle, role: element.role, label: element.label, before: before, after: value)
                // It went over a selection, so it is no plain insertion: the undo puts back the text as it was.
                if undo == nil, typedOver != nil {
                    if let overCopy {
                        undo = ArisApps.TextUndo.replaced(app: target.name, bundle: target.bundle, role: element.role, label: element.label, before: before,
                                                          after: value, copy: overCopy)
                    } else {
                        now += "; what was selected was typed over and couldn't be kept, so this can't be undone"
                    }
                }
            }
        }
        var outcome = ArisApps.Outcome(ok: true, did: "\(delivery == "set" ? "set" : "typed") \(text.count) characters in \(target.name)" + (field.map { " (\($0.1.label.isEmpty ? $0.1.role : $0.1.label))" } ?? ""),
                                       now: now, effect: effect, channel: "engine", verified: verified)
        outcome.undo = undo
        return outcome
    }

    /// The keys that put the caret at the end of a text view or field without selecting anything: only ever pressed into
    /// a focused text element that wouldn't take its caret moved through Accessibility (app.type's assessment counts it).
    static let endKeys = ArisApps.Specs.endKeys.split(separator: " ").map(String.init)

    /// at=end's caret: the described field (it must be a text one), else the focused element (Accessibility tells),
    /// moved to its end by its selected text range. Keys only into that same element, focused and text, that refused.
    /// Nil when the caret is at the end; else why nothing was typed.
    private func toEnd(field: ArisApps.ReadElement?, target: Target, window: WindowInfo, context: Context, effect: ArisApps.Effect) -> ArisApps.Outcome? {
        guard let pid = target.running?.pid ?? running(target.bundle)?.pid else {
            return .failure("\(target.name) isn't running, so there is no text to add to: nothing was typed", effect: effect)
        }
        let point = field?.frame.map { (x: $0.x + $0.width / 2, y: $0.y + $0.height / 2) }
        switch ax.caretToEnd(pid: pid, at: point) {
        case .moved:
            return nil
        case .notText:
            return .failure("at=end puts text into a text field or document, and \(field.map { $0.line() } ?? "what has the focus in \(target.name)") isn't one "
                            + "(app.read shows the fields): nothing was typed", effect: effect)
        case .refused(focused: true):
            let moved = Self.envelope(engine.run(["press"] + Self.endKeys + ["--window-id", String(window.id)], background: context.background))
            return moved.ok ? nil : .failure("couldn't move to the end of the text in \(target.name): \(moved.message); nothing was typed", effect: effect)
        case .refused(focused: false):
            return .failure("\(target.name) didn't let the caret move to the end of that text, and it doesn't have the keyboard focus: nothing was typed",
                            effect: effect)
        }
    }

    /// app.type adds its text at the end (`at` "end"), and doesn't replace the field.
    static func addsAtEnd(_ arguments: ArisApps.JSON) -> Bool {
        arguments["at"]?.string == "end" && arguments["replace"]?.bool != true
    }

    /// A document's text area with neither `at` nor `replace`: inserting at its end is the default, never its whole value
    /// set and never wherever a click in its middle left the caret (third VM run, D2).
    static func insertsByDefault(_ arguments: ArisApps.JSON, field: ArisApps.ReadElement?) -> Bool {
        arguments["at"] == nil && arguments["replace"]?.bool != true && field?.role == "textArea"
    }

    func click(_ arguments: ArisApps.JSON, context: Context, effect: ArisApps.Effect) -> ArisApps.Outcome {
        guard let said = arguments["target"]?.string, !said.isEmpty else { return .failure("app.click needs the target", effect: effect) }
        let target: Target, window: WindowInfo
        switch readyWindow(arguments, context: context, effect: effect) {
        case .ok(let ready): (target, window) = ready
        case .stop(let outcome): return outcome
        }
        // Exactness is only ever the mark on the target that was rated ("=Pay now"), never an argument beside it.
        if let refused = ArisApps.Exact.refusedArguments.first(where: { arguments[$0] != nil }) {
            return .failure("app.click takes no ‘\(refused)’: nothing was pressed", effect: effect)
        }
        let named = ArisApps.Exact.parse(said)
        let part = arguments["part"]?.string.flatMap(ArisApps.Read.Part.init(rawValue:))
        let found: (LastRead, ArisApps.ReadElement)
        switch element(named.text, target: target, window: window, part: part, context: context, exact: named.exact ? named.text : nil) {
        case .ok(let located): found = located
        case .stop(let outcome): return outcome
        }
        var argv = ["click", "--snapshot", found.0.snapshot, "--on", found.1.id]
        if arguments["double"]?.bool == true { argv.append("--double") }
        let reply = Self.envelope(engine.run(argv, background: context.background))
        guard reply.ok else { return .failure("couldn't press \(found.1.line()): \(reply.message)", effect: effect) }
        return ArisApps.Outcome(ok: true, did: "pressed \(found.1.line()) in \(target.name)", now: "", data: .object(["delivery": reply.data["delivery"] ?? .null]),
                                effect: effect, channel: "engine")
    }

    func press(_ arguments: ArisApps.JSON, context: Context, effect: ArisApps.Effect) -> ArisApps.Outcome {
        let keys = (arguments["keys"]?.string ?? "").split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !keys.isEmpty, keys.count <= 20 else { return .failure("app.press needs keys (at most 20)", effect: effect) }
        let target: Target, window: WindowInfo
        switch readyWindow(arguments, context: context, effect: effect) {
        case .ok(let ready): (target, window) = ready
        case .stop(let outcome): return outcome
        }
        let reply = Self.envelope(engine.run(["press"] + keys + ["--window-id", String(window.id)], background: context.background))
        guard reply.ok else { return .failure("couldn't press \(keys.joined(separator: " ")) in \(target.name): \(reply.message)", effect: effect) }
        return ArisApps.Outcome(ok: true, did: "pressed \(keys.joined(separator: " ")) in \(target.name)", now: "", effect: effect, channel: "engine")
    }

    /// What app.select chooses among: lists, tables, tabs, pop-ups and menus (a button is pressed with app.click, where
    /// its label decides the effect).
    static let selectable: Set<String> = ["row", "cell", "outlineRow", "listItem", "popUpButton", "menuButton", "comboBox", "menuItem", "radioButton",
                                          "tab", "tabGroup", "list", "outline", "table", "staticText", "image", "disclosureTriangle"]

    func select(_ arguments: ArisApps.JSON, context: Context, effect: ArisApps.Effect) -> ArisApps.Outcome {
        guard let said = arguments["target"]?.string, !said.isEmpty else { return .failure("app.select needs the target", effect: effect) }
        let target: Target, window: WindowInfo
        switch readyWindow(arguments, context: context, effect: effect) {
        case .ok(let ready): (target, window) = ready
        case .stop(let outcome): return outcome
        }
        if let refused = ArisApps.Exact.refusedArguments.first(where: { arguments[$0] != nil }) {
            return .failure("app.select takes no ‘\(refused)’: nothing was chosen", effect: effect)
        }
        let named = ArisApps.Exact.parse(said)
        let found: (LastRead, ArisApps.ReadElement)
        switch element(named.text, target: target, window: window, part: nil, context: context, prefer: Self.selectable, exact: named.exact ? named.text : nil) {
        case .ok(let located): found = located
        case .stop(let outcome): return outcome
        }
        guard Self.selectable.contains(found.1.role) else {
            return .failure("\(found.1.line()) is a \(found.1.role), not a list, tab, menu or pop-up: press it with app.click", effect: effect)
        }
        let first = Self.envelope(engine.run(["click", "--snapshot", found.0.snapshot, "--on", found.1.id], background: context.background))
        guard first.ok else { return .failure("couldn't select \(found.1.line()): \(first.message)", effect: effect) }
        guard let option = arguments["option"]?.string, !option.isEmpty else {
            return ArisApps.Outcome(ok: true, did: "selected \(found.1.line()) in \(target.name)", now: "", effect: effect, channel: "engine")
        }
        // A pop-up's options show once it is open: read again and press the one asked for (only a menu item or row).
        // A taught choice: that option exactly, never a near one (fourth VM run, D5).
        let exact = named.exact
        guard let fresh = look(target, window, context: context).0,
              case .one(let item) = exact ? ArisApps.Exact.controls(option, in: fresh.elements, prefer: ["menuItem"]) : ArisApps.Read.locate(option, in: fresh.elements, prefer: ["menuItem"]),
              Self.selectable.contains(item.role) else {
            _ = engine.run(["press", "escape", "--window-id", String(window.id)], background: context.background)
            return .failure("opened ‘\(said)’ but found no option ‘\(option)’", effect: effect)
        }
        let reply = Self.envelope(engine.run(["click", "--snapshot", fresh.snapshot, "--on", item.id], background: context.background))
        return reply.ok ? ArisApps.Outcome(ok: true, did: "chose “\(item.label)” in ‘\(said)’", now: "", effect: effect, channel: "engine")
            : .failure("couldn't choose ‘\(option)’: \(reply.message)", effect: effect)
    }

    func scroll(_ arguments: ArisApps.JSON, context: Context) -> ArisApps.Outcome {
        let target: Target, window: WindowInfo
        switch readyWindow(arguments, context: context, effect: .observe) {
        case .ok(let ready): (target, window) = ready
        case .stop(let outcome): return outcome
        }
        let found: (LastRead, ArisApps.ReadElement)
        if let said = arguments["target"]?.string, !said.isEmpty {
            switch element(said, target: target, window: window, part: nil, context: context) {
            case .ok(let located): found = located
            case .stop(let outcome): return outcome
            }
        } else {
            guard let fresh = look(target, window, context: context).0,
                  let area = fresh.elements.first(where: { ["scrollArea", "table", "outline", "list", "webArea", "textArea"].contains($0.role) })
                    ?? fresh.elements.first(where: { $0.role == "row" }) else {
                return .failure("nothing in \(target.name)’s window scrolls", effect: .observe)
            }
            found = (fresh, area)
        }
        let direction = arguments["direction"]?.string ?? "down"
        let amount = max(1, min(50, arguments["amount"]?.int ?? 5))
        let reply = Self.envelope(engine.run(["scroll", "--snapshot", found.0.snapshot, "--on", found.1.id, "--direction", direction, "--amount", String(amount)],
                                             background: context.background))
        guard reply.ok else { return .failure("couldn't scroll \(found.1.line()): \(reply.message)", effect: .observe) }
        return ArisApps.Outcome(ok: true, did: "scrolled \(direction) in \(target.name) (\(found.1.label.isEmpty ? found.1.role : found.1.label))",
                                now: "app.read shows what is visible now", effect: .observe, channel: "engine")
    }

    func recipe(_ arguments: ArisApps.JSON, context: Context) -> ArisApps.Outcome {
        guard let id = arguments["recipe"]?.string, let recipe = ArisApps.Recipes.recipe(id) else {
            return .failure("no recipe ‘\(arguments["recipe"]?.string ?? "")’; there are \(ArisApps.Recipes.all.map(\.id).joined(separator: ", "))", effect: .observe)
        }
        var inputs: [String: String] = [:]
        for (key, value) in arguments["inputs"]?.object ?? [:] { if let text = value.string { inputs[key] = text } }
        // The task as a whole, as the trust policy saw this call (and asked about at most once): every step is checked
        // against it, and put to the policy as a call of its own when one is handed in.
        let approved = assess("app.recipe", arguments)
        let declared = Dictionary(recipe.parts.flatMap { $0.ways.flatMap { $0 } }.map { ($0.call, $0.effect) }, uniquingKeysWith: max)
        var outcome = ArisApps.Recipes.run(recipe, inputs: inputs) { name, step in
            let assessment = ArisApps.Spec.named(name).map { $0.assess(.object(step), effectContext) }
                ?? .plain(max(declared[name] ?? .changePermanent, .observe), "\(name), outside the app layer")
            let request = ArisAppsGateRequest(call: name, arguments: .object(step), assessment: assessment, recipe: recipe.id, approved: approved,
                                              background: context.background)
            if let why = gate?.refusal(request) ?? ArisApps.Recipes.stepRefusal(assessment, approved: approved) {
                return .failure("not done without the owner's go-ahead: \(why)", effect: assessment.effect)
            }
            if ArisApps.Spec.named(name) != nil { return call(name, .object(step), context: context) }
            if let outcome = external?(name, .object(step)) { return outcome }
            return .failure("\(name) isn't available here", effect: .observe)
        }
        outcome.effect = approved.effect
        return outcome
    }
}
