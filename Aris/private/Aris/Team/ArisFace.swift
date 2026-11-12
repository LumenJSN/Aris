//
//  ArisFace.swift
//  Aris
//
//  Aris's own face, picked on the 팀원 page (the owner's "Settings A", mockups/face/sa.html): one of seven types (the star
//  first) in any palette colour, always fabric. Kept in the app's defaults; everything that draws Aris reads it live.
//  Pure rules too (Foundation only, so the tests build it): the teammates' pool loses the type Aris wears and gains
//  the star, a teammate wearing Aris's new type moves, and no teammate ever shows Aris's type. The words are the
//  catalog's (ArisTeamCopy, Korean and English).
//

import Foundation

enum ArisFace {
    /// The defaults key: "type", or "type #RRGGBB" for a palette colour.
    static let key = "arisFace"
    /// Posted (on the main thread, by `set`) after the face changed.
    static let changed = Notification.Name("com.lumenjsn.aris.faceChanged")
    /// What Aris may wear: the star, then the six the teammates are given by name.
    static let choices = ["star"] + ArisCharacterLook.teammateTypes
    /// Aris's shading never changes (the owner's pick, mockup A5).
    static let shading = "fabric"

    /// Where the face is kept (the tests and the offscreen renders use their own).
    nonisolated(unsafe) static var store: UserDefaults = .standard

    /// The face Aris wears now: what was picked, else the star.
    static var current: ArisCharacterLook { decode(store.string(forKey: key)) }

    /// Wears `look` from now on (its shading is always fabric; a type or colour Aris can't wear is the star's own),
    /// and says so. Nothing happens when it is already worn.
    static func set(_ look: ArisCharacterLook) {
        let next = decode(encode(look))
        guard next != current else { return }
        store.set(encode(next), forKey: key)
        NotificationCenter.default.post(name: changed, object: nil)
    }

    // MARK: stored form

    static func encode(_ look: ArisCharacterLook) -> String {
        look.colorHex.map { "\(look.type) \($0.uppercased())" } ?? look.type
    }

    /// Anything unreadable, or a type or colour Aris can't wear, is the plain star (never a crash, never a teammate's
    /// face by accident).
    static func decode(_ raw: String?) -> ArisCharacterLook {
        let parts = (raw ?? "").split(separator: " ").map(String.init)
        guard let type = parts.first, choices.contains(type), parts.count <= 2 else { return .star }
        // The type's own colour spelt out is its own (nil), as the colour row offers it.
        let hex = parts.count == 2 ? parts[1].uppercased() : nil
        let own = hex == ArisCharacterLook.ownColors[type]
        if let hex, !own, !colorChoices(for: type).contains(hex) { return .star }
        return ArisCharacterLook(type: type, colorHex: own ? nil : hex, shading: shading)
    }

    /// The colour row for `type`: its own (nil) first, then the palette without it.
    static func colorChoices(for type: String) -> [String?] { ArisCharacterLook.colorChoices(for: type) }

    // MARK: the teammates

    /// The six faces a teammate is given by name: the type Aris wears leaves, the star takes its place, so every other
    /// name keeps the face it had.
    static func pool(aris: String) -> [String] {
        ArisCharacterLook.teammateTypes.map { $0 == aris ? "star" : $0 }
    }

    /// What a teammate's picker offers: every type but the one Aris wears (the star too, once Aris wears another).
    static func pickableTypes(aris: String) -> [String] {
        ArisCharacterLook.types.filter { $0 != aris }
    }

    /// The face a teammate wearing Aris's type is given instead: the star while Aris wears another face; when Aris
    /// is the star again, the one its name gives it.
    static func replacement(name: String, aris: String) -> String {
        aris == "star" ? pool(aris: aris)[ArisActivityTab.paletteIndex(name, count: ArisCharacterLook.teammateTypes.count)] : "star"
    }

    /// What a teammate shows: its own look, unless that is Aris's type (a file written before the change, a figure
    /// already out): then the replacement, in its own shading.
    static func shown(_ look: ArisCharacterLook, name: String, aris: ArisCharacterLook) -> ArisCharacterLook {
        guard look.type == aris.type else { return look }
        return ArisCharacterLook(type: replacement(name: name, aris: aris.type), colorHex: nil, shading: look.shading)
    }

    /// The team once Aris wears `aris`: each teammate wearing that type moved to its replacement (in team order),
    /// everyone else as they were.
    static func moving(_ team: [ArisTeammate], to aris: ArisCharacterLook) -> (team: [ArisTeammate], moved: [ArisTeammate]) {
        let next = team.map { mate -> ArisTeammate in
            var moved = mate
            moved.look = shown(mate.look, name: mate.name, aris: aris)
            return moved
        }
        return (next, zip(team, next).filter { $0.look != $1.look }.map(\.1))
    }

    /// The page's line for a teammate just moved off the face Aris took: "코디도 고양이였어요. 이제 코디는 별이에요." (in
    /// English "Codi was the cat too. Now Codi is the star.").
    static func notice(moved: ArisTeammate, aris: String) -> String {
        let korean = ArisTeamCopy.korean
        return ArisTeamCopy.faceNotice(name: moved.name, was: korean ? josa(name(aris), "이었어요", "였어요") : name(aris),
                                       then: korean ? josa(moved.name, "은", "는") : moved.name,
                                       now: korean ? josa(name(moved.look.type), "이에요", "예요") : name(moved.look.type))
    }

    /// The button beside the notice.
    static func noticeAction(moved: ArisTeammate) -> String { ArisTeamCopy.faceNoticeAction(moved.name) }

    // MARK: words

    /// Each type's name, as the pickers show it (the catalog's: ArisTeamCopy.faceName).
    static func name(_ type: String) -> String { ArisTeamCopy.faceName(type) ?? type }

    /// `word` and the particle its last syllable takes: josa("몽실", "은", "는") is "몽실은". A word that doesn't end in
    /// Hangul takes the second.
    static func josa(_ word: String, _ withBatchim: String, _ without: String) -> String {
        guard let last = word.unicodeScalars.last?.value, (0xAC00...0xD7A3).contains(last) else { return word + without }
        return word + ((last - 0xAC00) % 28 == 0 ? without : withBatchim)
    }
}

extension ArisCharacterLook {
    /// Aris as it looks now (ArisFace.current): the face picked on the 팀원 page, the fabric star until then.
    static var main: ArisCharacterLook { ArisFace.current }
}
