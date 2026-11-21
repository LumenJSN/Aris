//
//  ArisHTMLFileText.swift
//  aris-tools
//
//  An HTML file's or a web archive's text for `files read`, with nothing fetched: AppKit's HTML import (WebKit) loads
//  the page's remote images, styles and frames as it reads, so a file from anywhere could make the Mac fetch addresses
//  of its choosing (a beacon saying it was opened, or a local address). Here the bytes are read as they are, in their
//  own charset (ArisTextDecoding), and turned into text the way `web fetch` does a page (ArisWebFetch.text). A web
//  archive gives its main page's bytes and encoding from its own property list; its other resources are never read.
//

import Foundation

enum ArisHTMLFileText {
    static let types: Set<String> = ["html", "htm", "xhtml", "webarchive"]

    static func handles(_ path: String) -> Bool { types.contains((path as NSString).pathExtension.lowercased()) }

    /// The file's text; nil when it can't be read (or a web archive has no main page).
    static func text(path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        if (path as NSString).pathExtension.lowercased() == "webarchive" {
            guard let page = mainResource(ofArchive: data) else { return nil }
            return text(html: page.data, encodingName: page.encoding)
        }
        return text(html: data, encodingName: nil)
    }

    /// The text of an HTML document's bytes; `encodingName`: the charset its container named, when it did.
    static func text(html data: Data, encodingName: String?) -> String {
        ArisWebFetch.text(fromHTML: ArisTextDecoding.decode(data, contentType: encodingName.map { "text/html; charset=\($0)" } ?? ""), limit: .max)
    }

    /// A web archive's main page: WebMainResource's WebResourceData and WebResourceTextEncodingName.
    static func mainResource(ofArchive data: Data) -> (data: Data, encoding: String?)? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let main = plist["WebMainResource"] as? [String: Any], let page = main["WebResourceData"] as? Data else { return nil }
        return (page, main["WebResourceTextEncodingName"] as? String)
    }
}
