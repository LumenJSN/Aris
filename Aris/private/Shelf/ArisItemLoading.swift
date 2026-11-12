//
//  ArisItemLoading.swift
//  Aris
//
//  Getting what a drag carries out of an NSItemProvider (cleanroom-specs/06): a file URL, a web URL, text, or bytes.
//  Never throws; nil when the provider has nothing of that kind.
//

import Foundation
import UniformTypeIdentifiers

enum ArisItemResolution {
    /// A loaded item as a URL: a URL as is; data as a UTF-8 URL string, an absolute path or a bookmark; a string as
    /// a URL string or an absolute path.
    static func url(from item: Any?) -> URL? {
        switch item {
        case let url as URL: return url
        case let url as NSURL: return url as URL
        case let data as Data:
            if let text = String(data: data, encoding: .utf8), let url = url(fromText: text) { return url }
            var stale = false
            return (try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale))
                ?? (try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale))
        case let text as String: return url(fromText: text)
        default: return nil
        }
    }

    static func url(fromText text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        if trimmed.hasPrefix("/") { return URL(fileURLWithPath: trimmed) }
        guard let url = URL(string: trimmed), url.scheme != nil else { return nil }
        return url
    }

    /// SwiftUI's file promises land in a folder with this in its path; only those files are read as dropped data.
    static let promiseFolderMarker = "com.apple.SwiftUI.filePromises"

    /// The bytes of a promised file, deleting it (and its folder once empty). Any other URL is refused.
    static func takePromisedData(at url: URL) -> Data? {
        guard url.isFileURL, url.path.contains(promiseFolderMarker), let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        let folder = url.deletingLastPathComponent()
        if let rest = try? FileManager.default.contentsOfDirectory(atPath: folder.path), rest.isEmpty {
            try? FileManager.default.removeItem(at: folder)
        }
        return data
    }
}

extension NSItemProvider {
    private func loadItem(_ type: UTType) async -> Any? {
        guard hasItemConformingToTypeIdentifier(type.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            loadItem(forTypeIdentifier: type.identifier, options: nil) { item, _ in
                nonisolated(unsafe) let item = item
                continuation.resume(returning: item)
            }
        }
    }

    /// The file the provider carries as a file URL.
    func extractFileURL() async -> URL? {
        ArisItemResolution.url(from: await loadItem(.fileURL))
    }

    /// Any item resolvable to a URL (files from apps that don't offer a file URL).
    func extractItem() async -> URL? {
        ArisItemResolution.url(from: await loadItem(.item))
    }

    /// A URL with a scheme.
    func extractURL() async -> URL? {
        guard let url = ArisItemResolution.url(from: await loadItem(.url)), url.scheme != nil else { return nil }
        return url
    }

    /// UTF-8 plain text first, then plain text.
    func extractText() async -> String? {
        for type in [UTType.utf8PlainText, .plainText] {
            switch await loadItem(type) {
            case let text as String: return text
            case let text as NSString: return text as String
            case let data as Data: if let text = String(data: data, encoding: .utf8) { return text }
            default: continue
            }
        }
        return nil
    }

    /// Raw bytes, or a SwiftUI file promise's bytes (its name becomes the suggested name if there is none).
    func loadData() async -> Data? {
        switch await loadItem(.data) {
        case let data as Data: return data
        case let url as URL:
            guard let data = ArisItemResolution.takePromisedData(at: url) else { return nil }
            if suggestedName == nil { suggestedName = url.lastPathComponent }
            return data
        default: return nil
        }
    }
}
