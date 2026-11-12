//
//  ArisSharing.swift
//  Aris
//
//  Sharing from the shelf. While a share picker is open or a sharing service is working, no notch may close
//  (nested shares are counted); when the last one ends, `sharingDidFinish` lets the notch close if the pointer has
//  left.
//

import AppKit
import Combine

@MainActor
final class SharingStateManager: NSObject, ObservableObject {
    static let shared = SharingStateManager()

    @Published private(set) var preventNotchClose = false
    private var active = 0
    private var held: [ObjectIdentifier: AnyObject] = [:]

    /// A share started; `keep` (a delegate) stays alive until `end(_:)`.
    func begin(keeping keep: AnyObject? = nil) {
        active += 1
        if let keep { held[ObjectIdentifier(keep)] = keep }
        preventNotchClose = true
    }

    func end(releasing keep: AnyObject? = nil) {
        if let keep { held[ObjectIdentifier(keep)] = nil }
        active = max(0, active - 1)
        guard active == 0, preventNotchClose else { return }
        preventNotchClose = false
        NotificationCenter.default.post(name: .sharingDidFinish, object: nil)
    }

    /// Shows the system share picker for `items` under `view`; the shelf stays open until it is done.
    func showPicker(for items: [Any], relativeTo view: NSView, onEnd: (() -> Void)? = nil) {
        let picker = NSSharingServicePicker(items: items)
        let watcher = ArisShareWatcher(sharing: self, onEnd: onEnd)
        picker.delegate = watcher
        begin(keeping: watcher)
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    /// Runs one sharing service on `items`, keeping the notch open until it finishes.
    func perform(_ service: NSSharingService, items: [Any], onEnd: (() -> Void)? = nil) {
        let watcher = ArisShareWatcher(sharing: self, onEnd: onEnd)
        begin(keeping: watcher)
        guard service.canPerform(withItems: items) else {
            watcher.finish()
            return
        }
        watcher.chose(service)
        service.perform(withItems: items)
    }
}

/// Ends the share when the picker closes without a choice, or the chosen service finishes or fails — or 2 s after
/// a service was chosen, since some (Copy, Notes, Reminders) never report back.
final class ArisShareWatcher: NSObject, NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    static let serviceTimeout: TimeInterval = 2

    private let sharing: SharingStateManager
    private let onEnd: (() -> Void)?
    private let timeout: TimeInterval
    private var done = false

    @MainActor
    init(sharing: SharingStateManager, timeout: TimeInterval = ArisShareWatcher.serviceTimeout, onEnd: (() -> Void)?) {
        self.sharing = sharing
        self.timeout = timeout
        self.onEnd = onEnd
    }

    @MainActor
    func finish() {
        guard !done else { return }
        done = true
        onEnd?()
        sharing.end(releasing: self)
    }

    /// A service was chosen: listen to it, and finish anyway after the timeout.
    @MainActor
    func chose(_ service: NSSharingService) {
        service.delegate = self
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            MainActor.assumeIsolated { self?.finish() }
        }
    }

    func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        MainActor.assumeIsolated {
            if let service { chose(service) } else { finish() }
        }
    }

    func sharingService(_ service: NSSharingService, didShareItems items: [Any]) {
        MainActor.assumeIsolated { finish() }
    }

    func sharingService(_ service: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        MainActor.assumeIsolated { finish() }
    }
}
