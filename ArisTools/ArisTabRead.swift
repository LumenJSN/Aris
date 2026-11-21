//
//  ArisTabRead.swift
//  aris-tools (jv-prompts)
//
//  `aris-tools tab` reads the front tab's address and title through Accessibility, as the focus reader and the app
//  engine do (a web area's AXURL, else the address field when it shows a whole link), so no browser needs Aris's
//  Automation grant and macOS's "Aris wants to control Safari" never comes for it. The browser's own scripting is
//  used only when Accessibility gives no address and Aris may already control that browser. Pure: the live tree is
//  behind two closures.
//

import Foundation

/// One element as the tab reader sees it.
struct ArisTabElement: Equatable {
    var role: String?
    var url: String?
    var value: String?
    var identifier: String?
    var title: String?
}

enum ArisTabRead {
    /// The most elements one read looks at (a page's tree can be large; the web area is near the top).
    static let limit = 800

    /// Safari's address field; Chromium's omnibox has no identifier and is found by its description below.
    static let addressIdentifiers: Set<String> = ["WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD"]

    /// The first web area's page (breadth first under `root`, at most `limit` elements), else the address field's text
    /// when it is a whole web link; nil when neither is there.
    static func address<Element>(root: Element, read: (Element) -> ArisTabElement?, children: (Element) -> [Element],
                                 limit: Int = limit) -> (url: String, title: String?)? {
        var queue = [root], index = 0, field: String?
        while index < queue.count, index < limit {
            let element = queue[index]
            index += 1
            guard let seen = read(element) else { continue }
            if seen.role == "AXWebArea", let url = seen.url, isPage(url) { return (url, seen.title.flatMap(nonEmpty)) }
            if field == nil, seen.role == "AXTextField", isAddressField(seen), let value = seen.value?.trimmingCharacters(in: .whitespaces),
               isPage(value) {
                field = value
            }
            queue.append(contentsOf: children(element))
        }
        return field.map { ($0, nil) }
    }

    static func isAddressField(_ element: ArisTabElement) -> Bool {
        if let identifier = element.identifier, addressIdentifiers.contains(identifier) { return true }
        let title = (element.title ?? "").lowercased()
        return title.contains("address") || title.contains("주소")
    }

    /// A whole http(s) link with a host.
    static func isPage(_ text: String) -> Bool {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "https" || scheme == "http") && url.host != nil
    }

    /// What `tab` prints: the address and the title the way the browsers' scripting printed {URL, title}.
    static func line(url: String, title: String?) -> String { "\(url), \(title ?? "")" }

    private static func nonEmpty(_ text: String) -> String? { text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : text }
}
