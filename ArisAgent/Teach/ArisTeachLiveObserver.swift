//
//  ArisTeachLiveObserver.swift
//  aris-agent
//
//  What the owner does, while he shows Aris something (F3), read as Accessibility notifications, never pixels and never
//  a screen recording: the app in front (NSWorkspace), and per app an AXObserver for focus, value changes, menu items
//  chosen, windows created and selections; a click is read as the element under it (a listen-only mouse tap, nothing
//  swallowed); keys only with a modifier, or Return and Esc, and only when the key tap is already allowed
//  (CGPreflightListenEventAccess: no new prompt is ever caused; without it shortcuts are left out). Only the app in
//  front counts, and a value change or a selection only right after the owner's own key or click there (the
//  hardware's idle times, which no program's synthetic events reset; the recorder holds the rule). Nothing is read
//  from a secure field or a password app, and nothing from Aris's own processes. It runs only between start and stop,
//  on the main run loop the helper already runs. Not run by the tests (they feed ArisTeachDesk fake events).
//  Which app a key went to is the app that has the keyboard at that instant, as Accessibility says (ArisFrontLive), never
//  the app whose menu bar shows: Aris's notch and composer take the keyboard without taking the menu bar, so in the
//  second VM run the stop phrase and the composer's ⌘A, ⌘V and Return were saved as TextEdit's steps. Keys, clicks and
//  focus in Aris itself go to the recorder as Aris's (it keeps nothing while Aris has the keyboard); a key whose app
//  can't be told is dropped. A click is the owner's on the app it lands in, also one that takes the keyboard back from
//  Aris; a click on a pop-up is kept, so its choice can be told from a value the app set by itself.
//  Third VM run, D1: TextEdit, launched through Spotlight during the lesson, was never observed (its AXObserver was made
//  while it was still starting, every registration failed unseen, and it was never tried again), so the line typed
//  into its new window was lost; and File › New chosen with the mouse was dropped, because Aris's composer still had
//  the keyboard while the mouse used TextEdit's menu bar. Now: an app is observed only once its registrations took,
//  else tried again shortly; the app in front is also asked for every moment (this helper gets no AppKit activation
//  notices it can rely on); a text element his keys go into is read again when the lesson ends, so what he typed is
//  kept even when no change of it was reported; a menu item is chosen by his mouse let go on it (or Return on the item
//  highlighted), whoever has the keyboard, and a shortcut is told as the menu command with that key equivalent.
//  Fourth VM run, D2: the value a stretch of typing is told against was read at his first key (a listen-only tap sees
//  it after the app may have taken it) or not before a change came; and a shortcut's menu walk held the main thread
//  while he typed, so every later read was late ("quick note" kept the document's line as his, "줄 덧붙이기" lost its
//  Return). Now a text element's value is read when nothing of his can be in it yet (the app attached, the element
//  focused, his click into it), the menu bars are read once off the main thread, and a selection he types over is told.
//

import AppKit
import ApplicationServices
import Foundation

final class ArisTeachLiveObserver: ArisTeachObserving, @unchecked Sendable {
    private var sink: ((ArisTeachEvent) -> Void)?
    private var observers: [pid_t: AXObserver] = [:]
    private var activation: NSObjectProtocol?
    private var mouseTap: CFMachPort?
    private var mouseSource: CFRunLoopSource?
    private var keyTap: CFMachPort?
    private var keySource: CFRunLoopSource?
    private let own = getpid()
    /// Polls the app in front while a lesson runs, and tries again the apps whose registrations didn't take yet.
    private var frontTimer: Timer?
    private var lastFront: pid_t?
    /// Apps whose observer couldn't register yet (an app still starting), with how many times it was tried.
    private var pending: [pid_t: Int] = [:]
    /// Each text element's last value read (at its focus, at his first key in it, or its last change), for `before`.
    private var lastValues: [(element: AXUIElement, value: String)] = []
    /// The text elements his own keys went into, read again when the lesson ends.
    private var typedInto: [Typed] = []
    /// The menu item last highlighted (AXMenuItemSelected fires as the pointer or the arrows move over items).
    private var highlighted: (pid: pid_t, item: AXUIElement, at: Date)?
    /// Each text element's selection length as last read while its value was unchanged (the selection before his next
    /// key): a change that follows a non-empty one typed over or deleted text he selected (fourth VM run, D1).
    private var selections: [(element: AXUIElement, length: Int)] = []
    /// Each observed app's menu bar commands with a key equivalent, read once off the main thread when it is attached
    /// (fourth VM run, D2: the walk ran on the main thread at his ⌘↓, and the keys and changes he typed meanwhile were
    /// read late, so the line already in the field was taken for his).
    private let menus = ArisLocked<[pid_t: [ArisTeachMenuKeys.Item]]>([:])
    private static let menuQueue = DispatchQueue(label: "aris.teach.menus", qos: .utility)

    private struct Typed {
        let element: AXUIElement
        let app: ArisTeachApp
        let described: ArisTeachElement
        let before: String?
        var lastKey: Date
    }

    static let appNotifications = [kAXFocusedUIElementChangedNotification, kAXValueChangedNotification, kAXMenuItemSelectedNotification,
                                   kAXWindowCreatedNotification, kAXSelectedChildrenChangedNotification, kAXSelectedRowsChangedNotification,
                                   kAXMenuClosedNotification, kAXSelectedTextChangedNotification]
    /// The registrations an app must take to be observed at all.
    static let needed: Set<String> = [kAXFocusedUIElementChangedNotification, kAXValueChangedNotification]
    static let pollEvery: TimeInterval = 0.3
    static let mostTries = 40

    /// The key tap runs only with Input Monitoring (`start`): then his keys are heard one by one.
    var hearsKeys: Bool { CGPreflightListenEventAccess() }

    func start(sink: @escaping (ArisTeachEvent) -> Void) -> Bool {
        // Never AXIsProcessTrustedWithOptions with a prompt: no permission is asked for here.
        guard AXIsProcessTrusted() else { return false }
        onMain {
            self.sink = sink
            self.activation = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.activated(app)
            }
            if let front = ArisFrontLive.frontPid().flatMap(NSRunningApplication.init(processIdentifier:)) ?? NSWorkspace.shared.frontmostApplication {
                self.activated(front)
            }
            // The app whose menu bar shows while Aris's composer has the keyboard is watched from the start too.
            if let menuBar = NSWorkspace.shared.frontmostApplication?.processIdentifier { self.attach(menuBar) }
            self.startMouseTap()
            if CGPreflightListenEventAccess() { self.startKeyTap() }
            let timer = Timer(timeInterval: Self.pollEvery, repeats: true) { [weak self] _ in self?.poll() }
            RunLoop.main.add(timer, forMode: .common)
            self.frontTimer = timer
        }
        return true
    }

    /// The app in front now (the window server and Accessibility, as asked this moment), and another try for the apps
    /// that weren't ready to be observed.
    private func poll() {
        guard sink != nil else { return }
        if let pid = ArisFrontLive.frontPid(), pid != lastFront, pid != own, let running = NSRunningApplication(processIdentifier: pid) {
            activated(running)
        }
        for pid in Array(pending.keys) { attach(pid) }
    }

    /// What his keys put into text elements, read again as the lesson ends (the recorder keeps it only for a field he
    /// typed into and that nothing was kept of).
    func closing() -> [ArisTeachEvent] {
        var read: [ArisTeachEvent] = []
        let work = {
            for typed in self.typedInto {
                guard !ArisTeachPrivacy.isSecret(typed.described), let value = Self.text(typed.element, kAXValueAttribute) else { continue }
                var event = ArisTeachEvent(.valueChanged, at: typed.lastKey, app: typed.app, element: typed.described, value: value, before: typed.before)
                event.caret = Self.caret(typed.element)
                read.append(event)
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync(execute: work) }
        return read
    }

    func stop() {
        onMain {
            if let activation = self.activation { NSWorkspace.shared.notificationCenter.removeObserver(activation) }
            self.activation = nil
            for (_, observer) in self.observers {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            }
            self.observers = [:]
            self.pending = [:]
            self.frontTimer?.invalidate()
            self.frontTimer = nil
            self.lastFront = nil
            self.lastValues = []
            self.typedInto = []
            self.highlighted = nil
            self.selections = []
            self.menus.withLock { $0 = [:] }
            for (tap, source) in [(self.mouseTap, self.mouseSource), (self.keyTap, self.keySource)] {
                if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
                if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
            }
            self.mouseTap = nil
            self.mouseSource = nil
            self.keyTap = nil
            self.keySource = nil
            self.sink = nil
        }
    }

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    // MARK: - Apps

    private func app(_ pid: pid_t) -> ArisTeachApp? {
        guard pid != own, let running = NSRunningApplication(processIdentifier: pid) else { return nil }
        return ArisTeachApp(bundle: running.bundleIdentifier ?? "pid.\(pid)", name: running.localizedName ?? running.bundleIdentifier ?? "app")
    }

    private func emit(_ event: ArisTeachEvent) { sink?(event) }

    private func activated(_ running: NSRunningApplication) {
        let pid = running.processIdentifier
        guard let app = app(pid) else { return }
        lastFront = pid
        emit(ArisTeachEvent(.appActivated, at: Date(), app: app))
        attach(pid)
    }

    /// Observes `pid`'s notifications once its registrations take; an app still starting refuses them (third VM run,
    /// D1), so it is tried again with the next poll, a few times a second, for a while.
    private func attach(_ pid: pid_t) {
        guard sink != nil, observers[pid] == nil, let app = app(pid) else { return }
        // A password app is never watched inside (its activation alone is enough for the recorder to leave it out), nor
        // the system's launchers, nor Aris itself.
        guard !ArisTeachPrivacy.isPasswordApp(app), !ArisTeachPrivacy.isOwnApp(app), !ArisTeachLaunchers.isSystemUI(app) else { return }
        var created: AXObserver?
        guard AXObserverCreate(pid, arisTeachAXCallback, &created) == .success, let observer = created else { return retry(pid) }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.5)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var took = Set<String>()
        for name in Self.appNotifications {
            let result = AXObserverAddNotification(observer, element, name as CFString, refcon)
            if result == .success || result == .notificationAlreadyRegistered { took.insert(name) }
        }
        guard Self.needed.isSubset(of: took) else {
            for name in took { AXObserverRemoveNotification(observer, element, name as CFString) }
            return retry(pid)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        observers[pid] = observer
        pending[pid] = nil
        // What its focused text element holds now, before any key of his in this lesson could be in it (fourth VM run,
        // D2): the value his typing there is told against, whatever the helper is busy with when he types.
        if let focused = Self.element(Self.attribute(element, kAXFocusedUIElementAttribute)) { baseline(focused) }
        // Its menu bar's key equivalents, read once off the main thread: a shortcut is told as its command at once.
        Self.menuQueue.async { [weak self] in
            let items = Self.menuItems(pid)
            self?.menus.withLock { $0[pid] = items }
        }
    }

    /// A text element's value read at a moment nothing of his can be in it yet (the lesson's start, its focus, his
    /// click into it), unless the lesson already knows it: what his first key there is told against.
    private func baseline(_ element: AXUIElement) {
        guard lastValue(element) == nil else { return }
        let described = Self.describe(element)
        guard described.takesText, !ArisTeachPrivacy.isSecret(described) else { return }
        remember(element, Self.text(element, kAXValueAttribute) ?? "")
        noteSelection(element)
    }

    /// The element's selection length now, kept only while its value is the one last read (a selection that moved
    /// with an edit not reported yet is no selection of his before that edit).
    private func noteSelection(_ element: AXUIElement) {
        guard let range = Self.attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(range) == AXValueGetTypeID() else { return }
        var selected = CFRange(location: 0, length: 0)
        guard AXValueGetValue(range as! AXValue, .cfRange, &selected) else { return }
        guard let known = lastValue(element), known == (Self.text(element, kAXValueAttribute) ?? "") else { return }
        selections.removeAll { CFEqual($0.element, element) }
        selections.append((element, max(0, selected.length)))
        if selections.count > 40 { selections.removeFirst(selections.count - 40) }
    }

    /// The end of the element's selection now (the caret, when nothing is selected), in UTF-16 units as Accessibility
    /// counts; nil when it can't be read. A place only, never any of the text.
    static func caret(_ element: AXUIElement) -> Int? {
        guard let range = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(range) == AXValueGetTypeID() else { return nil }
        var selected = CFRange(location: 0, length: 0)
        guard AXValueGetValue(range as! AXValue, .cfRange, &selected), selected.location >= 0, selected.length >= 0 else { return nil }
        return selected.location + selected.length
    }

    private func selectionLength(_ element: AXUIElement) -> Int {
        selections.last { CFEqual($0.element, element) }?.length ?? 0
    }

    private func retry(_ pid: pid_t) {
        let tries = (pending[pid] ?? 0) + 1
        pending[pid] = tries <= Self.mostTries ? tries : nil
    }

    // MARK: - Elements

    static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    static func text(_ element: AXUIElement, _ name: String) -> String? {
        guard let value = attribute(element, name) else { return nil }
        if let text = value as? String { return text.isEmpty ? nil : text }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    static func element(_ value: AnyObject?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// The element as the recorder takes it; its value is never read here.
    static func describe(_ element: AXUIElement) -> ArisTeachElement {
        let role = ArisTeachElement.shortRole(text(element, kAXRoleAttribute) ?? "")
        let subrole = text(element, kAXSubroleAttribute)
        var label = text(element, kAXTitleAttribute) ?? text(element, kAXDescriptionAttribute) ?? ""
        if label.isEmpty, let titled = Self.element(attribute(element, kAXTitleUIElementAttribute)) {
            label = text(titled, kAXValueAttribute) ?? text(titled, kAXTitleAttribute) ?? ""
        }
        if label.isEmpty, ["row", "cell", "outlineRow"].contains(role) {
            // A row's words: its first cell's text (others' words, kept as data).
            let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
            label = children.prefix(4).lazy.compactMap { text($0, kAXValueAttribute) ?? text($0, kAXTitleAttribute) }.first ?? ""
        }
        return ArisTeachElement(role: role, subrole: subrole, label: String(label.prefix(120)),
                                placeholder: text(element, kAXPlaceholderValueAttribute), identifier: text(element, kAXIdentifierAttribute),
                                secure: subrole == "AXSecureTextField" || role == "secureTextField")
    }

    /// Whether `pid` is the app in front now: the one with the keyboard (Aris's notch is in front while its composer
    /// has it, whatever app's menu bar shows), else the owner of the topmost window.
    private func inFront(_ pid: pid_t) -> Bool { ArisFrontLive.frontPid() == pid }

    /// The app that has the keyboard at this instant (Accessibility), as the recorder takes it; nil when it can't be told.
    private func keyboardApp() -> (pid: pid_t, app: ArisTeachApp)? {
        guard let pid = ArisFrontLive.focusedPid(), let app = app(pid) else { return nil }
        return (pid, app)
    }

    /// The owner's own last key or click, from the hardware's idle times (HID state: a program's synthetic events don't
    /// count, and no key is read), as an input event of the app in front when it was recent enough to matter.
    private func ownerInput(_ app: ArisTeachApp, at now: Date) {
        let key = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
        let click = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .leftMouseDown)
        // Presence only: the idle times can't tell typing from a paste or Return, so they are never a typing hint.
        let ago = min(key, click)
        guard ago <= ArisTeachRecorder.inputWindow else { return }
        emit(ArisTeachEvent(.input, at: now.addingTimeInterval(-ago), app: app, input: .hand))
    }

    func notified(_ element: AXUIElement, _ notification: String) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, let app = app(pid) else { return }
        let now = Date()
        // A menu's items: only remembered as highlighted (the pointer or the arrows over them); his mouse let go on one,
        // or Return, chooses it (`clicked`, `pressed`). Not by who has the keyboard: the menu bar may be used while
        // Aris's composer has it.
        if notification == kAXMenuItemSelectedNotification { return highlighted = (pid, element, now) }
        if notification == kAXMenuClosedNotification { return highlighted = nil }
        // Only the app in front is the owner's: one in the background, or a page that updates itself, is not.
        guard inFront(pid) else { return emit(ArisTeachEvent(.valueChanged, at: now, app: app, frontmost: false)) }
        if [kAXValueChangedNotification, kAXSelectedChildrenChangedNotification, kAXSelectedRowsChangedNotification].contains(notification) {
            ownerInput(app, at: now)
        }
        switch notification {
        case kAXFocusedUIElementChangedNotification:
            let described = Self.describe(element)
            baseline(element)
            emit(ArisTeachEvent(.focused, at: now, app: app, element: described))
        case kAXSelectedTextChangedNotification:
            let described = Self.describe(element)
            if described.takesText, !ArisTeachPrivacy.isSecret(described) { noteSelection(element) }
        case kAXValueChangedNotification:
            let described = Self.describe(element)
            // A secret field's value is never read: the event goes without it, and the recorder leaves the field out.
            let secret = ArisTeachPrivacy.isSecret(described)
            let value = secret ? nil : Self.text(element, kAXValueAttribute)
            let before = secret || !described.takesText ? nil : lastValue(element)
            // A selection of what was there right before this change: he typed over it or deleted it.
            let over = described.takesText && !secret && selectionLength(element) > 0
            if described.takesText, !secret {
                remember(element, value ?? "")
                selections.removeAll { CFEqual($0.element, element) }
            }
            var changed = ArisTeachEvent(.valueChanged, at: now, app: app, element: described, value: value, before: before)
            if over { changed.overSelection = true }
            // Where the caret is after it: where his run of typing ends (ninth VM run, item 1).
            if described.takesText, !secret { changed.caret = Self.caret(element) }
            emit(changed)
        case kAXWindowCreatedNotification:
            emit(ArisTeachEvent(.windowOpened, at: now, app: app, window: Self.text(element, kAXTitleAttribute)))
        case kAXSelectedChildrenChangedNotification, kAXSelectedRowsChangedNotification:
            let selected = (Self.attribute(element, kAXSelectedRowsAttribute) as? [AXUIElement])?.first
                ?? (Self.attribute(element, kAXSelectedChildrenAttribute) as? [AXUIElement])?.first
            guard let selected else { return }
            emit(ArisTeachEvent(.selected, at: now, app: app, element: Self.describe(selected)))
        default:
            break
        }
    }

    // MARK: - Text values

    private func lastValue(_ element: AXUIElement) -> String? {
        lastValues.last { CFEqual($0.element, element) }?.value
    }

    private func remember(_ element: AXUIElement, _ value: String) {
        lastValues.removeAll { CFEqual($0.element, element) }
        lastValues.append((element, String(value.prefix(ArisTeachRecorder.longestKept))))
        if lastValues.count > 40 { lastValues.removeFirst(lastValues.count - 40) }
    }

    /// His character key went into `element` (a text element, not secret): it is read again when the lesson ends.
    private func typed(into element: AXUIElement, app: ArisTeachApp, described: ArisTeachElement, at now: Date) {
        if let index = typedInto.firstIndex(where: { CFEqual($0.element, element) }) {
            typedInto[index].lastKey = now
            return
        }
        guard typedInto.count < 20 else { return }
        // The value before his first key there (a listen-only tap sees the key before the app takes it).
        let before = lastValue(element) ?? Self.text(element, kAXValueAttribute) ?? ""
        if lastValue(element) == nil { remember(element, before) }
        typedInto.append(Typed(element: element, app: app, described: described, before: before, lastKey: now))
    }

    // MARK: - Menus

    /// The menu bar's commands with a key equivalent, read from the app's menu bar (menus, their items, one submenu deep).
    static func menuItems(_ pid: pid_t) -> [ArisTeachMenuKeys.Item] {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.3)
        guard let bar = element(attribute(application, kAXMenuBarAttribute)) else { return [] }
        var items: [ArisTeachMenuKeys.Item] = []
        func walk(_ menu: AXUIElement, path: [String], depth: Int) {
            // A menu, its submenus and theirs (Edit › Find › Use Selection for Find; Format › Font › Bold).
            guard depth < 3, items.count < 600 else { return }
            for item in attribute(menu, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                guard let title = text(item, kAXTitleAttribute), !title.isEmpty else { continue }
                if let submenu = (attribute(item, kAXChildrenAttribute) as? [AXUIElement])?.first {
                    walk(submenu, path: path + [title], depth: depth + 1)
                    continue
                }
                guard let character = text(item, kAXMenuItemCmdCharAttribute) else { continue }
                let modifiers = (attribute(item, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue ?? 0
                let enabled = (attribute(item, kAXEnabledAttribute) as? NSNumber)?.boolValue ?? true
                items.append(ArisTeachMenuKeys.Item(path: path + [title], character: character, modifiers: modifiers, enabled: enabled))
            }
        }
        for top in attribute(bar, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            guard let title = text(top, kAXTitleAttribute), !title.isEmpty, let menu = (attribute(top, kAXChildrenAttribute) as? [AXUIElement])?.first else { continue }
            walk(menu, path: [title], depth: 0)
        }
        return items
    }

    /// Where a menu item is: a command of the menu bar (its path), or an option of a pop-up button.
    private enum MenuPlace {
        case bar([String])
        case popUp(AXUIElement, option: String?)
    }

    private static func place(of item: AXUIElement) -> MenuPlace? {
        var path: [String] = []
        var current: AXUIElement? = item
        for _ in 0..<8 {
            guard let element = current else { break }
            let role = text(element, kAXRoleAttribute) ?? ""
            if role == kAXMenuBarRole as String { return path.isEmpty ? nil : .bar(path.reversed()) }
            if role == kAXMenuItemRole as String || role == kAXMenuBarItemRole as String, let title = text(element, kAXTitleAttribute) {
                path.append(title)
            }
            if role == kAXPopUpButtonRole as String || role == kAXMenuButtonRole as String { return .popUp(element, option: path.first) }
            current = Self.element(attribute(element, kAXParentAttribute))
        }
        return nil
    }

    /// A menu item chosen (his mouse let go on it, or Return on it): a command of the menu bar, or a pop-up's option.
    private func menuChosen(_ item: AXUIElement, app: ArisTeachApp, at now: Date) {
        // An item with a submenu only opens it, and a disabled one does nothing.
        if let children = Self.attribute(item, kAXChildrenAttribute) as? [AXUIElement], !children.isEmpty { return }
        if (Self.attribute(item, kAXEnabledAttribute) as? NSNumber)?.boolValue == false { return }
        switch Self.place(of: item) {
        case .bar(let path)?: emit(ArisTeachEvent(.menuChosen, at: now, app: app, menu: path))
        case .popUp(let button, let option)?: emit(ArisTeachEvent(.selected, at: now, app: app, element: Self.describe(button), value: option))
        case nil: break
        }
    }

    // MARK: - Clicks and keys

    private static let pressable: Set<String> = ["button", "checkBox", "radioButton", "link", "menuButton", "popUpButton", "row", "cell", "outlineRow", "tab",
                                                 "disclosureTriangle"]
    /// A click inside an open menu is part of choosing from it (the choice comes as a menu notification), no new target.
    private static let inMenu: Set<String> = ["menu", "menuItem", "menuBar", "menuBarItem"]

    private func startMouseTap() {
        // The button let go too: a menu item is chosen on the mouse's release over it (a click, or a press dragged there).
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue) | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly, eventsOfInterest: mask,
                                          callback: { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let observer = Unmanaged<ArisTeachLiveObserver>.fromOpaque(info).takeUnretainedValue()
            if type == .leftMouseUp { observer.released(at: event.location) } else if type == .leftMouseDown { observer.clicked(at: event.location) }
            return Unmanaged.passUnretained(event)
        }, userInfo: refcon) else { return }
        mouseTap = tap
        mouseSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), mouseSource, .commonModes)
    }

    private func clicked(at point: CGPoint) {
        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &found) == .success,
              var element = found else { return }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, let app = app(pid), !ArisTeachPrivacy.isPasswordApp(app) else { return }
        // A click a program posted is not the owner's: the hardware saw no click just now.
        guard CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .leftMouseDown) < 1 else { return }
        // A click on Aris itself (the notch, the composer): the recorder keeps nothing until he is back in an app.
        if ArisTeachPrivacy.isOwnApp(app) { return emit(ArisTeachEvent(.input, at: Date(), app: app, input: .click)) }
        let clicked = element
        // A text inside a row or a button: the control it belongs to.
        for _ in 0..<3 {
            let role = ArisTeachElement.shortRole(Self.text(element, kAXRoleAttribute) ?? "")
            // His click on an app's menu bar is his hand in that app, whoever has the keyboard (third VM run, D1: File ›
            // New was lost while Aris's composer still had it). The item chosen comes on the release.
            if role == "menuBar" || role == "menuBarItem" { return emit(ArisTeachEvent(.input, at: Date(), app: app, input: .click)) }
            if Self.inMenu.contains(role) { return }
            if Self.pressable.contains(role) {
                emit(ArisTeachEvent(.pressed, at: Date(), app: app, element: Self.describe(element)))
                return
            }
            guard let parent = Self.element(Self.attribute(element, kAXParentAttribute)) else { break }
            element = parent
        }
        // A click on anything else (a text area, a field, the window): his hand is there, on that element; a text
        // element's value is read now, before his keys go into it.
        baseline(clicked)
        emit(ArisTeachEvent(.input, at: Date(), app: app, element: Self.describe(clicked), input: .click))
    }

    /// The mouse let go: over an item of an open menu (a menu bar command, a pop-up's option), that item is chosen.
    private func released(at point: CGPoint) {
        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &found) == .success,
              var element = found else { return }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, let app = app(pid), !ArisTeachPrivacy.isPasswordApp(app), !ArisTeachPrivacy.isOwnApp(app) else { return }
        // A release a program posted is not the owner's.
        guard CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .leftMouseUp) < 1 else { return }
        for _ in 0..<2 {
            if ArisTeachElement.shortRole(Self.text(element, kAXRoleAttribute) ?? "") == "menuItem" {
                highlighted = nil
                return menuChosen(element, app: app, at: Date())
            }
            guard let parent = Self.element(Self.attribute(element, kAXParentAttribute)) else { return }
            element = parent
        }
    }

    private func startKeyTap() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly, eventsOfInterest: mask,
                                          callback: { _, _, event, info in
            if let info { Unmanaged<ArisTeachLiveObserver>.fromOpaque(info).takeUnretainedValue().pressed(event) }
            return Unmanaged.passUnretained(event)
        }, userInfo: refcon) else { return }
        keyTap = tap
        keySource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), keySource, .commonModes)
    }

    private static let namedKeys: [Int64: String] = [36: "return", 76: "return", 53: "esc", 48: "tab", 49: "space", 51: "delete", 123: "left", 124: "right", 125: "down", 126: "up"]

    /// A key with ⌘, ⌃ or ⌥, or Return or Esc alone; plain typing is never read.
    private func pressed(_ event: CGEvent) {
        let flags = event.flags
        var modifiers: [String] = []
        if flags.contains(.maskCommand) { modifiers.append("cmd") }
        if flags.contains(.maskControl) { modifiers.append("ctrl") }
        if flags.contains(.maskAlternate) { modifiers.append("opt") }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let named = Self.namedKeys[code]
        guard !modifiers.isEmpty || named == "return" || named == "esc" else {
            // A character key alone: which key is never read; only that one was pressed in the focused field (the
            // card's typing hint). Tab and the arrows move, they don't type.
            guard named == nil || named == "space" || named == "delete", let keyboard = keyboardApp(),
                  CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown) < 1 else { return }
            // Typed into Aris's composer: Aris's, which the recorder keeps nothing of. Its field is never read.
            if ArisTeachPrivacy.isOwnApp(keyboard.app) { return emit(ArisTeachEvent(.input, at: Date(), app: keyboard.app, input: .key)) }
            let now = Date()
            // An app his keys go into that isn't observed yet (just launched): try it now.
            if observers[keyboard.pid] == nil { attach(keyboard.pid) }
            let element = Self.element(Self.attribute(AXUIElementCreateApplication(keyboard.pid), kAXFocusedUIElementAttribute))
            let focused = element.map(Self.describe)
            // A text element his keys go into is read again when the lesson ends (its value before them is read now).
            if let element, let described = focused, described.takesText, !ArisTeachPrivacy.isSecret(described), !ArisTeachLaunchers.isSystemUI(keyboard.app) {
                typed(into: element, app: keyboard.app, described: described, at: now)
            }
            emit(ArisTeachEvent(.input, at: now, app: keyboard.app, element: focused, input: .key))
            return
        }
        if flags.contains(.maskShift) { modifiers.append("shift") }
        var key = named
        if key == nil {
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &characters)
            key = String(utf16CodeUnits: characters, count: length).lowercased()
        }
        // The app that has the keyboard at this instant: never the menu bar's (Aris's composer has the keyboard under it).
        guard let key, !key.isEmpty, let keyboard = keyboardApp() else { return }
        guard CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown) < 1 else { return }
        let keys = (modifiers + [key]).joined(separator: "+")
        // Return on the item highlighted in an open menu chooses it (the menu has the keyboard then, Aris's composer
        // or not).
        if key == "return", modifiers.isEmpty, let menu = highlighted, Date().timeIntervalSince(menu.at) < 30,
           (Self.attribute(menu.item, kAXSelectedAttribute) as? NSNumber)?.boolValue == true, let owner = app(menu.pid) {
            highlighted = nil
            return menuChosen(menu.item, app: owner, at: Date())
        }
        if ArisTeachPrivacy.isOwnApp(keyboard.app) { return emit(ArisTeachEvent(.shortcut, at: Date(), app: keyboard.app, keys: keys)) }
        let now = Date()
        // The focused element goes with it, so keys pressed in a secret field are left out with that field.
        let element = Self.element(Self.attribute(AXUIElementCreateApplication(keyboard.pid), kAXFocusedUIElementAttribute))
        let focused = element.map(Self.describe)
        // Return typed into a document's text is part of that text: read again at the end like his other keys there.
        if modifiers.isEmpty || modifiers == ["shift"] || modifiers == ["opt"], key == "return", let element, let described = focused,
           described.role == "textArea", !ArisTeachPrivacy.isSecret(described) {
            typed(into: element, app: keyboard.app, described: described, at: now)
        }
        guard modifiers.contains("cmd"), !ArisTeachLaunchers.keys.contains(ArisTeachGeneralise.normalisedKeys(keys)) else {
            return emit(ArisTeachEvent(.shortcut, at: now, app: keyboard.app, element: focused, keys: keys))
        }
        // A shortcut that is a menu bar command's key equivalent is that command, told at once from the menu bar read
        // when the app was attached (fourth VM run, D2: walking a few hundred items here held the main thread while he
        // typed, and every key and change after it was read late). An app whose menus aren't read yet: the key as it
        // was pressed, and its menus are read for the next one.
        let pid = keyboard.pid, app = keyboard.app
        guard let items = menus.withLock({ $0[pid] }) else {
            Self.menuQueue.async { [weak self] in
                let items = Self.menuItems(pid)
                self?.menus.withLock { $0[pid] = items }
            }
            return emit(ArisTeachEvent(.shortcut, at: now, app: app, element: focused, keys: keys))
        }
        if let path = ArisTeachMenuKeys.command(for: keys, in: items) {
            var chosen = ArisTeachEvent(.menuChosen, at: now, app: app, element: focused, menu: path)
            chosen.keys = keys
            return emit(chosen)
        }
        emit(ArisTeachEvent(.shortcut, at: now, app: app, element: focused, keys: keys))
    }
}

private func arisTeachAXCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    Unmanaged<ArisTeachLiveObserver>.fromOpaque(refcon).takeUnretainedValue().notified(element, notification as String)
}
