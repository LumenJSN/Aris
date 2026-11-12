//
//  ArisDesktopPrivacy.swift
//  aris-agent
//
//  What never reaches a brain from another app's window, whatever the app (the benchmark leaked the home folder's name
//  once): the Apple menu and its Recent Items, every app's Open Recent, the Services list, a file browser's sidebar of
//  places (Finder, open and save panels), the home folder's path and name and the user's own name. They are dropped or
//  redacted from every observation, listing and result before the engine fences it. Pure.
//

import CoreGraphics
import Foundation
import ImageIO

/// The user, as the filter redacts them (ArisDesktopLiveIdentity reads the Mac's own).
struct ArisDesktopIdentity: Equatable {
    let userName: String
    let fullName: String
    let home: String

    static let placeholder = "‹user›"
}

enum ArisDesktopPrivacy {
    /// Menus whose items are the user's own history (dropped with everything under them).
    static let recentMenus: Set<String> = ["Apple", "\u{F8FF}", "최근 사용 항목", "Recent Items", "Open Recent", "최근 사용 항목 열기", "최근 항목 열기",
                                           "Services", "서비스", "Recent Documents", "최근 문서", "Recent Files", "최근 파일", "Recent Places",
                                           "Recent Folders", "최근 폴더", "최근 사용한 항목", "Recently Opened", "최근에 연 항목", "Open Recent File",
                                           "최근 사용 문서", "Recent Projects", "최근 프로젝트", "Reopen Closed"]

    /// A file browser's sidebar names (Finder, open and save panels): a sidebar holding any of these is the user's places.
    static let places: Set<String> = ["즐겨찾기", "Favorites", "최근 항목", "Recents", "위치", "Locations", "태그", "Tags", "iCloud", "iCloud Drive",
                                      "공유", "Shared", "AirDrop", "응용 프로그램", "Applications", "데스크탑", "Desktop", "문서", "Documents",
                                      "다운로드", "Downloads", "네트워크", "Network", "휴지통", "Trash"]
    static let sidebarNames: Set<String> = ["Sidebar", "사이드바", "sidebar"]
    static let hiddenLine = "(a sidebar of the user's own places is hidden)"

    /// The text with the home folder's path, then the user's names, taken out.
    static func redact(_ text: String, _ identity: ArisDesktopIdentity) -> String {
        var out = text
        if identity.home.count > 1 { out = out.replacingOccurrences(of: identity.home, with: "~") }
        for name in [identity.fullName, identity.userName] where name.count >= 3 {
            out = out.replacingOccurrences(of: name, with: ArisDesktopIdentity.placeholder, options: .caseInsensitive)
        }
        return out
    }

    /// A label the user would recognise as their own place or name.
    static func isPersonal(_ label: String, _ identity: ArisDesktopIdentity) -> Bool {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        if places.contains(trimmed) { return true }
        let home = (identity.home as NSString).lastPathComponent
        return [identity.userName, identity.fullName, home].contains { $0.count >= 3 && trimmed.caseInsensitiveCompare($0) == .orderedSame }
    }

    /// A see's elements without the menu bar and without a sidebar of the user's places; every label and value
    /// redacted. `hidden`: something was dropped for privacy; `regions`: the sidebars dropped (text read from the screen
    /// there is dropped too).
    static func filter(_ elements: [ArisDesktopElement], _ identity: ArisDesktopIdentity) -> (elements: [ArisDesktopElement], hidden: Bool, regions: [CGRect]) {
        let content = elements.filter { !$0.isMenuBar && !recentMenus.contains($0.label) }
        let sidebars = content.filter { sidebarNames.contains($0.label) && $0.bounds.width > 0 && $0.bounds.height > 0 }.map(\.bounds)
        // A row the sidebar's scroll clips (partly outside its frame) is still one of its rows (M2).
        let inside = { (element: ArisDesktopElement, region: CGRect) in
            region.insetBy(dx: -1, dy: -1).contains(element.bounds) || (element.bounds.intersects(region) && element.bounds.minX >= region.minX - 1 && element.bounds.maxX <= region.maxX + 1)
        }
        let personal = sidebars.filter { region in content.contains { inside($0, region) && isPersonal($0.label, identity) } }
        var hidden = false
        let kept = content.filter { element in
            guard !personal.contains(where: { inside(element, $0) }) else { hidden = true; return false }
            return true
        }
        return (kept.map { redacted($0, identity) }, hidden, personal)
    }

    static func redacted(_ element: ArisDesktopElement, _ identity: ArisDesktopIdentity) -> ArisDesktopElement {
        // The raw value stays as the app holds it (Aris's own comparison and write-back), never shown to a brain (C2).
        var copy = ArisDesktopElement(id: element.id, role: element.role, label: redact(element.label, identity),
                                      value: element.isSecure ? nil : element.value.map { redact($0, identity) },
                                      bounds: element.bounds, enabled: element.enabled, actionable: element.actionable,
                                      rawValue: element.isSecure ? nil : element.rawValue, rawCapped: element.isSecure || element.rawCapped,
                                      axRole: element.axRole, roleDescription: element.roleDescription)
        copy.identifier = element.identifier
        copy.selected = element.selected
        // The caret or selection is kept (it was dropped here, so no look ever carried one: a caret key could only be
        // told as "sent", and a select-all never read back); never a password field's, whose length it would tell.
        copy.selectedRange = element.isSecure ? nil : element.selectedRange
        if let value = copy.value, value.count > 400 { copy.value = String(value.prefix(400)) + "…" }
        return copy
    }

    /// A window's screenshot with these boxes (top-left origin, unit square) painted black, before a vision brain sees
    /// it; nil when it couldn't be done (then the image doesn't go).
    static func blackout(png: Data, boxes: [CGRect]) -> Data? {
        guard !boxes.isEmpty else { return png }
        guard let source = CGImageSourceCreateWithData(png as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let width = CGFloat(image.width), height = CGFloat(image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        // The context's origin is at the bottom left.
        for box in boxes { context.fill(CGRect(x: box.minX * width, y: (1 - box.maxY) * height, width: box.width * width, height: box.height * height)) }
        let out = NSMutableData()
        guard let painted = context.makeImage(), let destination = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, painted, nil)
        return CGImageDestinationFinalize(destination) ? out as Data : nil
    }

    /// `menu list`'s menu_structure without the Apple menu, Recent Items, Open Recent and Services, redacted.
    static func menus(_ structure: [[String: Any]], _ identity: ArisDesktopIdentity) -> [[String: Any]] {
        structure.compactMap { item -> [String: Any]? in
            let title = item["title"] as? String ?? ""
            guard !recentMenus.contains(title) else { return nil }
            var copy: [String: Any] = ["title": redact(title, identity)]
            if let shortcut = item["shortcut"] as? String { copy["shortcut"] = shortcut }
            if item["enabled"] as? Bool == false { copy["enabled"] = false }
            if let items = item["items"] as? [[String: Any]] { copy["items"] = menus(items, identity) }
            return copy
        }
    }

    /// Any other listing (a dialog's): every string redacted, and a string that names one of the user's places dropped.
    static func scrub(_ value: Any, _ identity: ArisDesktopIdentity, depth: Int = 0) -> Any? {
        guard depth < 24 else { return nil }
        switch value {
        case let text as String: return isPersonal(text, identity) ? nil : redact(text, identity)
        case let list as [Any]: return list.compactMap { scrub($0, identity, depth: depth + 1) }
        case let object as [String: Any]:
            var out: [String: Any] = [:]
            for (key, item) in object where key != "debug_logs" { if let kept = scrub(item, identity, depth: depth + 1) { out[key] = kept } }
            return out
        default: return value
        }
    }
}
