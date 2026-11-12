//
//  ArisFieldFocus.swift
//  Aris
//
//  Giving a SwiftUI field in one of Aris's panels the keyboard in the same act as the press that brought it up (the
//  request editor after its pencil: the second upgrade VM run, B12, where typing went nowhere until a second click into
//  the card). A focus request made as the field appears can come before the field is in the window or the panel is
//  key, and miss; here an invisible anchor laid out behind the field says when it is in the window, and the field over
//  it is found there by where it sits and made the panel's first responder (ArisPromptEditor asks again, a frame
//  apart, until it is).
//

import AppKit
import SwiftUI

/// An invisible view laid out behind a field: it knows the window it is in and where it sits, so the field over it
/// can be found in that window and given the keyboard (ArisFieldLocator). It takes no clicks.
struct ArisFieldAnchor: NSViewRepresentable {
    /// Holds the anchor's view for whoever placed it.
    final class Seat {
        weak var view: NSView?
    }

    let seat: Seat
    /// Told once the anchor is in a window, after that layout pass.
    let placed: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = Anchor()
        view.placed = placed
        seat.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? Anchor)?.placed = placed
        seat.view = view
    }

    final class Anchor: NSView {
        var placed: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window === window else { return }
                self.placed?(window)
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// Finds the editable text field laid out over an anchor, among every field of the anchor's window: the one whose
/// frame covers the most of it (SwiftUI's fields are not the anchor's relatives in the view tree, only its neighbours
/// on screen).
@MainActor
enum ArisFieldLocator {
    static func field(over anchor: NSView) -> NSView? {
        guard let content = anchor.window?.contentView else { return nil }
        let target = anchor.convert(anchor.bounds, to: nil)
        var best: (field: NSView, area: CGFloat)?
        func visit(_ view: NSView) {
            if let field = editable(view) {
                let shared = field.convert(field.bounds, to: nil).intersection(target)
                let area = shared.isNull ? 0 : shared.width * shared.height
                if area > (best?.area ?? 0) { best = (field, area) }
            }
            view.subviews.forEach(visit)
        }
        visit(content)
        return best?.field
    }

    /// An editable text field or text view (never a field's own editor).
    static func editable(_ view: NSView) -> NSView? {
        if let text = view as? NSTextView { return text.isEditable && !text.isFieldEditor ? text : nil }
        if let field = view as? NSTextField { return field.isEditable ? field : nil }
        return nil
    }

    /// The responder is the field or its field editor.
    static func holds(_ responder: NSResponder?, _ field: NSView) -> Bool {
        guard let responder else { return false }
        if responder === field { return true }
        if let editor = responder as? NSTextView, editor.isFieldEditor, editor.delegate as? NSView === field { return true }
        return false
    }
}
