//
//  ArisQuickShare.swift
//  Aris
//
//  Quick Share: the share tile's provider (AirDrop by default), found among the system's sharing services for a
//  file and a link, plus the system share menu.
//

import AppKit
import Combine
import Defaults

struct QuickShareProvider: Identifiable, Hashable {
    /// The service's title ("AirDrop", "Messages", …), or the system share menu.
    let id: String
    let image: NSImage?

    static let systemShareMenuId = ArisQuickShareDefault.systemShareMenu
}

@MainActor
final class QuickShareService: ObservableObject {
    static let shared = QuickShareService()

    @Published private(set) var availableProviders: [QuickShareProvider] = []
    private var services: [String: NSSharingService] = [:]

    private init() {
        Task { await discoverAvailableProviders() }
    }

    /// The services the system offers for a file and a link, plus the share menu itself.
    func discoverAvailableProviders() async {
        let sample = FileManager.default.temporaryDirectory.appendingPathComponent("aris-share-sample.txt")
        try? Data("Aris".utf8).write(to: sample)
        defer { try? FileManager.default.removeItem(at: sample) }
        var found: [String: NSSharingService] = [:]
        var order: [QuickShareProvider] = []
        for service in NSSharingService.sharingServices(forItems: [sample, URL(string: "https://example.com")!])
        where found[service.title] == nil {
            found[service.title] = service
            order.append(QuickShareProvider(id: service.title, image: service.image))
        }
        services = found
        availableProviders = order + [QuickShareProvider(id: QuickShareProvider.systemShareMenuId, image: nil)]
    }

    var selected: QuickShareProvider {
        let id = Defaults[.quickShareProvider]
        return availableProviders.first { $0.id == id } ?? QuickShareProvider(id: id, image: nil)
    }

    /// Shares through the chosen provider; the share menu (or an unknown provider) shows the picker under `view`.
    func share(_ items: [Any], from view: NSView, onEnd: (() -> Void)? = nil) {
        let id = Defaults[.quickShareProvider]
        if let service = id == ArisQuickShareDefault.airDrop ? NSSharingService(named: .sendViaAirDrop) : services[id] {
            SharingStateManager.shared.perform(service, items: items, onEnd: onEnd)
        } else {
            SharingStateManager.shared.showPicker(for: items, relativeTo: view, onEnd: onEnd)
        }
    }
}
