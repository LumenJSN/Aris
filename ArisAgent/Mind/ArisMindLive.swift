//
//  ArisMindLive.swift
//  aris-agent
//
//  The Mind's live parts in the helper, set up once with `arisCore2` on (ArisCore2Trust.start): the undo performers the
//  record calls for what isn't a file (ArisMindUndoHooks), and the World facts the trust gate grounds the owner's words
//  in. The helper has no AppKit app of its own, so its World is what it can read of the moment (the app in front,
//  from the window server: ArisFrontLive); the app's World (the contacts it may read, the apps' nicknames, what is in
//  front) comes with each conversation turn (ArisWorldWire) and maps through the same ArisMindWorld.facts.
//

import Foundation

enum ArisMindLive {
    static func start() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        ArisMindUndoHooks.live.register()
        // Text an app.type added is taken back by its own range (third VM run, D3).
        ArisAppsTextUndoLive.install()
        // A replace's card shows what it would erase, and whether it can be put back (fourth VM run, D1).
        ArisTrustGate.peekReplaced = { app, target in
            let text = ArisAppsHands.shared.peekField(app: app, target: target)
            return ArisErasedText(text: text, keepable: text.map { ArisUndoStore.canKeep(text: $0, home: home) } ?? false)
        }
        // The same for a field the model named by a read's id, and for typing that follows a Select All: found again
        // by what the read printed, in a look taken now (eleventh VM run, item 1).
        ArisTrustGate.peekRead = { app, target, seen in
            ArisAppsHands.shared.peekTyping(app: app, target: target, seen: seen).map {
                (text: $0.text, selected: $0.selected, keepable: ArisUndoStore.canKeep(text: $0.text, home: home))
            }
        }
        ArisTrustGate.shared.readElements = { session, app in ArisMindClickReads.shared.elements(session: session, app: app) }
        // A Select All and the typing after it are matched by the app as the app layer resolves it (its bundle id).
        ArisTrustGate.shared.appKey = { app in
            if case .app(let target) = ArisAppsHands.shared.resolve(app, effect: .observe) { return target.bundle }
            return nil
        }
        // A taught replay's typing asks when it would go over a selection (jv-quick): the field's selected text, read now.
        ArisTrustGate.peekSelection = { app, target in ArisAppsHands.shared.peekSelection(app: app, target: target) }
        // Replaces the focus desk's own hook (ArisFocusDesk.install): its focus is part of `facts`, so there is one World.
        ArisTrustGate.shared.world = { _ in facts(home: home) }
    }

    /// The app's World of its last conversation turn (ArisWorldWire), and when it came.
    private static let inbox = ArisLocked<(payload: ArisWorldWire.Payload, at: Date)?>(nil)

    /// POST /ask's `world`, from the Aris app itself only, with Core 2 on; anything else is dropped.
    static func heard(_ raw: Any?, fromApp: Bool, now: Date = Date()) {
        guard ArisCore2.isOn(), fromApp, let payload = ArisWorldWire.decode(raw) else { return }
        inbox.withLock { $0 = (payload, now) }
    }

    /// The trust gate's facts now, its one source of the World with Core 2 on: the turn's focus (what the owner points
    /// at, and the app it is in) from the focus desk while it is fresh (jv-focus); the app's contacts and nicknames
    /// (ArisWorldWire); what is in front as the helper reads it itself, else as the app said a moment ago.
    static func facts(home: String, now: Date = Date(), focus: ArisFocusDesk = .shared) -> ArisWorldFacts {
        let app = inbox.withLock { $0 }
        return ArisMindWorld.facts(ArisMindWorld.facts(live: snapshot(), app: app?.payload, appAt: app?.at, now: now, home: home),
                                   focus: focus.worldFacts(now: now))
    }

    /// The World's lines a turn of the Mind's own loop starts with (ArisMindWorld.context).
    static func context(now: Date = Date()) -> String {
        let world = ArisMindWorld.context(snapshot(), now: now)
        // The owner's saved steps, so a model knows they exist (tenth VM run, item 1); none with the switch off.
        guard ArisTeachSwitch.isOn() else { return world }
        let taught = ArisTaughtOffer.context(ArisTeachStore.load(file: ArisTeachStore.file(home: FileManager.default.homeDirectoryForCurrentUser.path)))
        return taught.isEmpty ? world : world + "\n" + taught
    }

    /// What the helper knows of the World now.
    static func snapshot() -> ArisWorldSnapshot {
        var snapshot = ArisWorldSnapshot()
        if let front = ArisFrontLive.front() { snapshot.frontApp = .init(name: front.name, bundleID: front.bundleId, pid: front.pid) }
        return snapshot
    }
}
