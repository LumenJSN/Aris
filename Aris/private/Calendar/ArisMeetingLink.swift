//
//  ArisMeetingLink.swift
//  Aris
//
//  The video-call link of an event, so a tap can join it. Only links on the known providers' hosts count; nothing
//  else is guessed.
//

import Foundation

struct ArisMeetingLink: Codable, Hashable, Sendable {
    enum Provider: String, Codable, CaseIterable, Sendable {
        case googleMeet, zoom, teams, webex, whereby, jitsi

        var name: String {
            switch self {
            case .googleMeet: "Google Meet"
            case .zoom: "Zoom"
            case .teams: "Microsoft Teams"
            case .webex: "Webex"
            case .whereby: "Whereby"
            case .jitsi: "Jitsi"
            }
        }

        var hosts: [String] {
            switch self {
            case .googleMeet: ["meet.google.com", "hangouts.google.com"]
            case .zoom: ["zoom.us", "zoomgov.com"]
            case .teams: ["teams.microsoft.com", "teams.live.com"]
            case .webex: ["webex.com"]
            case .whereby: ["whereby.com"]
            case .jitsi: ["meet.jit.si"]
            }
        }
    }

    let provider: Provider
    let url: URL

    /// The provider whose host this web URL is on (the host itself or a subdomain of it).
    static func provider(for url: URL) -> Provider? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased() else { return nil }
        return Provider.allCases.first { provider in
            provider.hosts.contains { host == $0 || host.hasSuffix("." + $0) }
        }
    }

    /// The first meeting link in the URL field, then the location, then the notes.
    static func find(url: URL?, location: String?, notes: String?) -> ArisMeetingLink? {
        if let url, let provider = provider(for: url) { return ArisMeetingLink(provider: provider, url: url) }
        for text in [location, notes].compactMap({ $0 }) {
            if let link = first(in: text) { return link }
        }
        return nil
    }

    /// The first link in free text that's on a provider's host.
    static func first(in text: String) -> ArisMeetingLink? {
        guard !text.isEmpty, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: range) {
            if let url = match.url, let provider = provider(for: url) { return ArisMeetingLink(provider: provider, url: url) }
        }
        return nil
    }
}
