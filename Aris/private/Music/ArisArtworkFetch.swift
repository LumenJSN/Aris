//
//  ArisArtworkFetch.swift
//  Aris
//
//  Downloads artwork and search results over http(s) with a session of its own: a 50 MB memory / 100 MB disk cache
//  named "artwork_cache", 15 s per request and 30 s per resource, no cookies. The first time it is created it
//  empties the shared URL cache once (older builds filled it with artwork).
//

import Defaults
import Foundation

final class ArisArtworkFetch: Sendable {
    static let shared = ArisArtworkFetch()

    private let session: URLSession

    private init() {
        if !Defaults[.didClearLegacyURLCacheV1] {
            URLCache.shared.removeAllCachedResponses()
            Defaults[.didClearLegacyURLCacheV1] = true
        }
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 100 * 1024 * 1024,
                                          directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
                                              .appendingPathComponent("artwork_cache", isDirectory: true))
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration)
    }

    /// The body at `url`, whatever the HTTP status. Throws for other schemes and for network errors.
    func data(from url: URL) async throws -> Data {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw URLError(.unsupportedURL)
        }
        return try await session.data(from: url).0
    }
}
