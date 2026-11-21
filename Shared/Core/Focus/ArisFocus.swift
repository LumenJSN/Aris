//
//  ArisFocus.swift
//  Shared/Core/Focus (aris-agent, app, tests)
//
//  F4 "act on what I am looking at" (ARCHITECTURE Part 3, jv-focus): the typed focus object. What the owner's "이거",
//  "여기", "이 사람", "this" points at when a turn starts: the circled region, the selection (text, files, a mail
//  message, a calendar event, a chat), the focused field, the front window's document or page, the thing under the
//  pointer, or the front window itself, each with the app and window it is in. It rides with the turn as content the
//  owner pointed at (ArisFocusContext: outside text, never instructions), fills the trust tracker's focus hook
//  (ArisFocusObject), and keeps an anchor and a landing so the follow-up lands back in the same place. Foundation only.
//

import Foundation

struct ArisFocusApp: Equatable, Sendable, Codable {
    var name: String
    var bundleID: String?
    var pid: Int32?

    init(name: String, bundleID: String? = nil, pid: Int32? = nil) {
        self.name = name
        self.bundleID = bundleID
        self.pid = pid
    }
}

/// What a turn's focus is read from: the app the owner was in, its front window as a tree, where the pointer is, and
/// what was circled during the turn. The helper fills it live; the tests write it.
struct ArisFocusObservation: Equatable, Sendable {
    var app: ArisFocusApp
    var windowTitle: String?
    /// The window server's number for the window read.
    var windowID: Int?
    /// The window as Accessibility shows it (nil: no Accessibility, or the app showed nothing).
    var tree: ArisAXNode?
    var pointer: ArisFocusPoint?
    /// The regions circled during this turn (the gesture), in global points.
    var regions: [ArisFocusRect] = []
    /// A browser's front tab, when the app layer read it.
    var tabURL: String?
    /// The read stopped at its limit (an app that answers slowly, a huge page).
    var cut = false

    init(app: ArisFocusApp, windowTitle: String? = nil, windowID: Int? = nil, tree: ArisAXNode? = nil, pointer: ArisFocusPoint? = nil,
         regions: [ArisFocusRect] = [], tabURL: String? = nil, cut: Bool = false) {
        self.app = app
        self.windowTitle = windowTitle
        self.windowID = windowID
        self.tree = tree
        self.pointer = pointer
        self.regions = regions
        self.tabURL = tabURL
        self.cut = cut
    }
}

struct ArisFocus: Equatable, Sendable, Codable {
    enum Kind: String, Sendable, Codable, CaseIterable {
        /// What was circled.
        case region
        /// Selected text.
        case text
        /// Files selected in a file browser.
        case files
        /// A mail message (selected in the list, or open).
        case mail
        /// A calendar event.
        case event
        /// A chat conversation (its other person, its messages).
        case chat
        /// Selected rows of any other list.
        case items
        /// The focused field or editor.
        case field
        /// A web page.
        case page
        /// A document file.
        case document
        /// The element under the pointer.
        case pointer
        /// The front window as a whole.
        case window

        /// Said to the owner (Korean first) and to the model.
        var korean: String {
            switch self {
            case .region: "동그라미 친 부분"
            case .text: "선택한 글"
            case .files: "선택한 파일"
            case .mail: "메일"
            case .event: "일정"
            case .chat: "대화"
            case .items: "선택한 항목"
            case .field: "입력 칸"
            case .page: "웹 페이지"
            case .document: "문서"
            case .pointer: "포인터 아래"
            case .window: "앞에 있는 창"
            }
        }

        var english: String {
            switch self {
            case .region: "the circled region"
            case .text: "the selected text"
            case .files: "the selected files"
            case .mail: "a mail message"
            case .event: "a calendar event"
            case .chat: "a chat conversation"
            case .items: "the selected items"
            case .field: "the focused field"
            case .page: "a web page"
            case .document: "a document"
            case .pointer: "the element under the pointer"
            case .window: "the front window"
            }
        }
    }

    /// Where in the window the focus is: the element's place in the tree and what identifies it again.
    struct Anchor: Equatable, Sendable, Codable {
        var path: [Int]
        var role: String
        var label: String?
        var identifier: String?
        var frame: ArisFocusRect?
        var editable = false
    }

    /// Where text for the focus goes (a reply, a rewrite): an editable element of the same window.
    struct Landing: Equatable, Sendable, Codable {
        enum Mode: String, Sendable, Codable {
            /// Typed over the selection.
            case replaceSelection
            /// Typed at the caret of the focused field.
            case insertAtCaret
            /// Into a field that isn't focused (a chat's message field): it has to be focused first.
            case intoField
        }

        var anchor: Anchor
        var mode: Mode
        /// The field already has the keyboard (typing lands there with nothing clicked first).
        var focused: Bool
    }

    var kind: Kind
    var app: ArisFocusApp
    var windowTitle: String?
    var windowID: Int?
    /// The words of what is pointed at (other people's words: outside text).
    var text: String?
    /// The person in it, from the app's own structure only: a mail's sender (its row's sender field, or the header
    /// element outside the message's body), a chat's conversation. Never from words in a body, a page, a selection or
    /// a circle, which anyone can write (those are `mentioned`). Judgment's focus hook takes only this as the sender.
    var person: String?
    /// A person named in the focus's words ("From: …" in a page, an address in a selection): a hint for the model,
    /// outside text, never a recipient anyone grounded.
    var mentioned: String?
    /// A mail's subject, an event's title, a page's or document's title.
    var title: String?
    /// A document's file path.
    var path: String?
    /// A page's address.
    var url: String?
    /// The names of selected items (files, rows).
    var items: [String] = []
    /// Selected files' full paths, in the order of `items`, as far as the file browser showed them (each item's AXURL,
    /// else its name in the window's folder): what file capabilities take, so nothing asks Finder by script.
    var paths: [String] = []
    var anchor: Anchor?
    var landing: Landing?
    /// How it was found, for the log and the model ("selected in the message list").
    var how: String

    init(kind: Kind, app: ArisFocusApp, windowTitle: String? = nil, windowID: Int? = nil, text: String? = nil, person: String? = nil,
         title: String? = nil, path: String? = nil, url: String? = nil, items: [String] = [], anchor: Anchor? = nil,
         landing: Landing? = nil, how: String) {
        self.kind = kind
        self.app = app
        self.windowTitle = windowTitle
        self.windowID = windowID
        self.text = text
        self.person = person
        self.title = title
        self.path = path
        self.url = url
        self.items = items
        self.anchor = anchor
        self.landing = landing
        self.how = how
    }
}

/// What resolution came to: the focus, the other things the words could have meant (for "그거 말고"), what the words
/// asked for that wasn't found ("이 사람" with nobody on screen).
struct ArisFocusResolution: Equatable, Sendable {
    var pointing: ArisFocusWords.Pointing
    var focus: ArisFocus?
    var others: [ArisFocus] = []
    /// The words named a person and none was found.
    var missingPerson = false
    /// The words named a kind ("이 메일") and nothing of that kind was found: the focus is the best other thing.
    var missingKind: ArisFocusWords.Want?
}
