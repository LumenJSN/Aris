//
//  ArisDisplayPick.swift
//  Aris
//
//  Which displays a screen turn shoots (the owner, 2026-11-14: "다른 화면에 있다" got "제가 볼 수 있는 건 지금 이 화면뿐"): the
//  display that holds the named app's window (every display with one of its windows, its front window's first), else
//  the one under the pointer; and when the user says another screen, or the app's window can't be placed, the others too.
//  At most three, each within the turn's own image budget, in memory only (nothing is drawn on his screens). What the
//  brain reads next to each image says which display it is. Pure, so the tests run it.
//

import CoreGraphics
import Foundation

enum ArisDisplayPick {
    static let maxDisplays = 3
    /// A window smaller than this either way (a menu-bar item, a floating dot) doesn't place an app.
    static let minWindowSide: CGFloat = 80

    /// A display in the screens' coordinates (Cocoa: the origin at the main display's bottom left).
    struct Display: Equatable {
        let id: CGDirectDisplayID
        let frame: CGRect
    }

    /// An app's window on screen, front to back, in the screens' coordinates.
    struct Window: Equatable {
        let app: String
        let frame: CGRect
    }

    enum Role: Equatable {
        case pointer
        case app(String)
        case other
    }

    struct Pick: Equatable {
        let id: CGDirectDisplayID
        let role: Role
    }

    /// The displays to shoot, in order (the first is the one the turn is most likely about).
    static func pick(displays: [Display], pointer: CGPoint, windows: [Window], want: ArisScreenNeed.Want) -> [Pick] {
        guard let under = ArisCaptureRules.display(containing: pointer, in: displays.map { (id: $0.id, frame: $0.frame) }) else { return [] }
        var picks: [Pick] = []
        func add(_ id: CGDirectDisplayID, _ role: Role) {
            guard picks.count < maxDisplays, !picks.contains(where: { $0.id == id }) else { return }
            picks.append(Pick(id: id, role: role))
        }
        for window in windows where want.apps.contains(window.app) {
            if let id = holder(of: window.frame, in: displays) { add(id, .app(window.app)) }
        }
        let placed = !picks.isEmpty
        if !placed { add(under, .pointer) }
        if want.others || (!want.apps.isEmpty && !placed) {
            add(under, .pointer)
            for display in displays { add(display.id, .other) }
        }
        return picks
    }

    /// The display a window is mostly on; nil for a sliver or a window on none.
    static func holder(of window: CGRect, in displays: [Display]) -> CGDirectDisplayID? {
        guard window.width >= minWindowSide, window.height >= minWindowSide else { return nil }
        let best = displays.max { area(window.intersection($0.frame)) < area(window.intersection($1.frame)) }
        guard let best, area(window.intersection(best.frame)) > 0 else { return nil }
        return best.id
    }

    private static func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }

    /// CGWindowList's bounds (origin at the main display's top left, y down) in the screens' coordinates.
    static func cocoa(fromWindowBounds bounds: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height)
    }

    /// The file name Aris gives the image of the `index`th display (1-based).
    static func imageName(_ index: Int) -> String { index <= 1 ? "cursor-screen.png" : "screen-\(index).png" }

    /// What the brain reads about the `index`th of `count` displays: which one it is and why it was taken.
    static func description(role: Role, index: Int, count: Int, frame: CGRect, main: CGRect) -> String {
        let place: String
        if count == 1 || frame == main {
            place = ""
        } else if frame.midX < main.minX {
            place = " (왼쪽)"
        } else if frame.midX > main.maxX {
            place = " (오른쪽)"
        } else {
            place = frame.midY > main.midY ? " (위)" : " (아래)"
        }
        let why: String
        switch role {
        case .pointer: why = "마우스가 있는 화면"
        case .app(let name): why = "\(name) 창이 있는 화면"
        case .other: why = "다른 화면"
        }
        return "화면 \(index)/\(count)\(place) · \(why)"
    }
}
