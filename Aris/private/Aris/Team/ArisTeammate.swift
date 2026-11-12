//
//  ArisTeammate.swift
//  Aris (also built into aris-agent)
//
//  Aris's teammates: who they are, how they look, which brain runs them. aris-agent keeps the list in
//  ~/.config/aris/aris/teammates.json (ArisTeammateStore); Claude Code is always one of them.
//

import Foundation

/// How a character looks on screen: a BotAvatarsKit type, an optional body colour ("#RRGGBB"; nil is the type's own)
/// and a shading. ArisCharacterView draws it; the rules are in ArisCharacter.swift.
struct ArisCharacterLook: Codable, Equatable {
    var type: String
    var colorHex: String?
    var shading: String

    /// BotAvatarType's raw values (kept here so this file needs no BotAvatarsKit: aris-agent builds it too).
    static let types = ["clover", "flower", "triangle", "square", "blob", "ghost", "circle", "drop", "star", "droid", "mech",
                        "alien", "hexagon", "cat", "cloud", "pill", "pebble", "puddle"]
    static let shadings = ["plastic", "crisp", "smooth", "flat", "fabric"]

    /// The characters a teammate may get by name (the star is Aris's until Aris wears one of these: ArisFace.pool).
    static let teammateTypes = ["clover", "cloud", "cat", "blob", "ghost", "pebble"]
    /// Upstream's palette (BotAvatarsKit's `botAvatarPresets`, Libraries.dev 1c87c11): its 17 distinct body colours,
    /// warm to cool, then the greys. Kept here as text so aris-agent can check a pick without the kit; a colour drawn
    /// on another type takes that type's own brightness and saturation, as upstream does. Nil is the type's own.
    static let palette = ["#EB7575", "#EAA06F", "#EFDB8E", "#9CD66A", "#ABC793", "#2FCB7A", "#1ED3C6", "#41C4FF", "#35B8FF",
                          "#ACAAF3", "#9A62FF", "#DC48FF", "#EE8BDB", "#F4F2FA", "#D5DBEA", "#CFD5E4", "#95A6C4"]
    /// Each type's own body colour (`botAvatarPresets`): the palette is these, less the repeats.
    static let ownColors = ["clover": "#41C4FF", "flower": "#2FCB7A", "triangle": "#DC48FF", "square": "#35B8FF", "blob": "#2FCB7A",
                            "ghost": "#F4F2FA", "circle": "#9A62FF", "drop": "#1ED3C6", "star": "#EFDB8E", "droid": "#D5DBEA",
                            "mech": "#95A6C4", "alien": "#9CD66A", "hexagon": "#EB7575", "cat": "#EAA06F", "cloud": "#CFD5E4",
                            "pill": "#ACAAF3", "pebble": "#ABC793", "puddle": "#EE8BDB"]

    /// The colour row for `type`: its own first (nil), then the palette without that same colour again.
    static func colorChoices(for type: String) -> [String?] {
        [nil] + palette.filter { $0 != ownColors[type] }.map(Optional.some)
    }

    /// The shadings in the picker's order: fabric (the owner's pick) first.
    static let pickerShadings = ["fabric", "plastic", "crisp", "smooth", "flat"]

    /// On the picker's allowlist: a known type (the star too: a teammate moved off the face Aris took wears it; the
    /// app's picker leaves out whichever type Aris wears, ArisFace), a palette colour (or the type's own) and a known
    /// shading.
    var isPickable: Bool {
        Self.types.contains(type) && Self.shadings.contains(shading) && (colorHex.map { Self.palette.contains($0) } ?? true)
    }

    /// Aris's face until the user picks another (ArisFace): the fabric star (the owner's pick, mockup A5). `.main` is the
    /// face it wears now.
    static let star = ArisCharacterLook(type: "star", colorHex: nil, shading: "fabric")
    /// A teammate's until the user picks one.
    static let standard = ArisCharacterLook(type: "clover", colorHex: nil, shading: "fabric")

    init(type: String, colorHex: String?, shading: String) {
        self.type = type
        self.colorHex = colorHex
        self.shading = shading
    }

    /// `kind` and `color` are the placeholder's fields (Task 11a): still read, and still written so an older build
    /// reads the file. Anything unknown falls back to the standard look rather than dropping the teammate.
    private enum Keys: String, CodingKey { case type, colorHex, shading, kind, color }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let type = try c.decodeIfPresent(String.self, forKey: .type) ?? c.decodeIfPresent(String.self, forKey: .kind)
        let hex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? c.decodeIfPresent(String.self, forKey: .color)
        let shading = try c.decodeIfPresent(String.self, forKey: .shading)
        self.type = type.flatMap { Self.types.contains($0) ? $0 : nil } ?? Self.standard.type
        // In the palette's case (#RRGGBB upper), so a colour stored by hand still matches its pick.
        self.colorHex = hex.flatMap { $0.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression) != nil ? $0.uppercased() : nil }
        self.shading = shading.flatMap { Self.shadings.contains($0) ? $0 : nil } ?? Self.standard.shading
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(colorHex, forKey: .colorHex)
        try c.encode(shading, forKey: .shading)
        try c.encode(type, forKey: .kind)
        try c.encode(colorHex ?? "", forKey: .color)
    }
}

/// A teammate (the 팀원 page, layout A): its name and face, 언제 부를까요 (`routing`: the line main Aris hands work out
/// by; the old `role`, read from older files), 어떻게 일할까요 (`instructions`, at most 800 letters, read with every job
/// of its), its brain (any of ArisBrain's), what it may use (`scopes`: ArisTeammateScope's raw values) and its own notes
/// (`memoryFile`, kept by the agent: ArisTeammateNotes).
struct ArisTeammate: Identifiable, Equatable {
    let id: String
    var name: String
    var routing: String
    var instructions: String
    var look: ArisCharacterLook
    var brain: String
    /// Always in the page's order, each once (ArisTeammateScope.canonical).
    var scopes: [String] { didSet { scopes = ArisTeammateScope.canonical(scopes) } }
    var memoryFile: String

    init(id: String, name: String, routing: String, instructions: String = "", look: ArisCharacterLook, brain: String,
         scopes: [String] = ArisTeammate.allScopes, memoryFile: String) {
        self.id = id
        self.name = name
        self.routing = routing
        self.instructions = instructions
        self.look = look
        self.brain = brain
        self.scopes = ArisTeammateScope.canonical(scopes)
        self.memoryFile = memoryFile
    }

    /// The shape before the redesign (one `role` line, no instructions; every scope, as it could use everything then).
    init(id: String, name: String, role: String, look: ArisCharacterLook, brain: String, memoryFile: String) {
        self.init(id: id, name: name, routing: role, look: look, brain: brain, memoryFile: memoryFile)
    }

    /// The old name of `routing` (the 하는 일 line).
    var role: String {
        get { routing }
        set { routing = newValue }
    }

    var scopeSet: Set<ArisTeammateScope> { Set(scopes.compactMap(ArisTeammateScope.init(rawValue:))) }

    static let allScopes = ArisTeammateScope.allCases.map(\.rawValue)
}

extension ArisTeammate: Codable {
    /// `role` is still written (an older build reads it); `routing` wins when both are there. A file from before the
    /// redesign has no `scopes`: every scope, as its teammates could use everything then. `scopesVersion` 2: written since
    /// Aside got its own switch; an older list with every other scope on gets Aside too (N6, ArisTeammateScope.migrated).
    private enum Keys: String, CodingKey { case id, name, routing, role, instructions, look, brain, scopes, scopesVersion, memoryFile }

    /// What `scopesVersion` says now.
    static let scopesVersion = 2

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let routing = try c.decodeIfPresent(String.self, forKey: .routing) ?? c.decodeIfPresent(String.self, forKey: .role) ?? ""
        self.init(id: try c.decode(String.self, forKey: .id), name: try c.decode(String.self, forKey: .name), routing: routing,
                  instructions: try c.decodeIfPresent(String.self, forKey: .instructions) ?? "",
                  look: try c.decode(ArisCharacterLook.self, forKey: .look), brain: try c.decode(String.self, forKey: .brain),
                  scopes: ArisTeammateScope.migrated(try c.decodeIfPresent([String].self, forKey: .scopes) ?? Self.allScopes,
                                                     version: try c.decodeIfPresent(Int.self, forKey: .scopesVersion) ?? 1),
                  memoryFile: try c.decode(String.self, forKey: .memoryFile))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(routing, forKey: .routing)
        try c.encode(String(routing.prefix(Self.legacyMaxRole)), forKey: .role)
        try c.encode(instructions, forKey: .instructions)
        try c.encode(look, forKey: .look)
        try c.encode(brain, forKey: .brain)
        try c.encode(scopes, forKey: .scopes)
        try c.encode(Self.scopesVersion, forKey: .scopesVersion)
        try c.encode(memoryFile, forKey: .memoryFile)
    }
}

extension ArisTeammate {
    static let claudeCodeId = "claude-code"
    static let maxName = 30
    /// 언제 부를까요: one line (the mockup's 80).
    static let maxRouting = 80
    static let maxRole = maxRouting
    /// What an older build cut a role to.
    static let legacyMaxRole = 40
    /// 어떻게 일할까요.
    static let maxInstructions = 800

    /// Seeded until the user names it.
    static let claudeCode = ArisTeammate(id: claudeCodeId, name: "Claude Code", routing: "터미널에서 프로젝트를 코딩할 때",
                                         look: claudeCodeLook, brain: "claude", scopes: ["files", "terminal"],
                                         memoryFile: "teammates/claude-code.md")
    /// The ghost: Claude Code's face until the user picks another in the 팀원 settings (ArisCharacterLook.forName gives the same; tested).
    static let claudeCodeLook = ArisCharacterLook(type: "ghost", colorHex: nil, shading: "fabric")

    static let legacyClaudeCodeRole = "Coding in a terminal window, in a project folder"
    /// The seed before the redesign: reads as today's.
    static let previousClaudeCodeRole = "터미널에서 코딩 담당"

    /// Lowercase letters, digits and dashes: it names files and goes into prompts.
    static func isValidId(_ id: String) -> Bool {
        id.range(of: #"^[a-z0-9][a-z0-9-]{0,31}$"#, options: .regularExpression) != nil
    }

    /// The entry with its name, routing and instructions made safe to put in a prompt (one line, no tags; the
    /// instructions may keep line breaks); nil when unusable.
    func checked() -> ArisTeammate? {
        guard Self.isValidId(id) else { return nil }
        let seeded = id == Self.claudeCodeId && [Self.legacyClaudeCodeRole, Self.previousClaudeCodeRole].contains(routing)
        let routing = seeded ? Self.claudeCode.routing : Self.plain(self.routing, limit: Self.maxRouting)
        // At most 12 wide (ArisTeammateName), so whatever is stored or read back fits a chip.
        guard let name = ArisTeammateName.validate(Self.plain(self.name, limit: Self.maxName)) else { return nil }
        return ArisTeammate(id: id, name: name, routing: routing, instructions: Self.instructionsText(instructions), look: look,
                            brain: brain, scopes: scopes, memoryFile: memoryFile)
    }

    /// Instructions as kept: lines without tags or invisible letters, at most 800 letters.
    static func instructionsText(_ text: String) -> String {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: .newlines).map { line in
            line.filter { $0 != "<" && $0 != ">" && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }
        }
        return String(lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxInstructions))
    }

    private static func plain(_ text: String, limit: Int) -> String {
        let flat = text.components(separatedBy: .newlines).joined(separator: " ")
            .filter { $0 != "<" && $0 != ">" && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }
        return String(flat.trimmingCharacters(in: .whitespaces).prefix(limit))
    }

    /// Entry by entry, so one damaged entry never hides the rest: unusable ones and repeated ids are skipped, and
    /// Claude Code is always there (first, as seeded, when the file lacks it).
    static func list(from data: Data) -> [ArisTeammate] {
        let entries = (try? JSONSerialization.jsonObject(with: data)) as? [Any] ?? []
        let decoded = entries.compactMap { entry -> ArisTeammate? in
            guard JSONSerialization.isValidJSONObject(entry), let one = try? JSONSerialization.data(withJSONObject: entry) else { return nil }
            return (try? JSONDecoder().decode(ArisTeammate.self, from: one))?.checked()
        }
        let unique = decoded.reduce(into: [ArisTeammate]()) { kept, teammate in
            if !kept.contains(where: { $0.id == teammate.id }) { kept.append(teammate) }
        }
        return unique.contains { $0.id == claudeCodeId } ? unique : [claudeCode] + unique
    }
}

/// A teammate's name is at most `limit` wide, a wide letter (Hangul, CJK, fullwidth) counting 2: 6 Korean letters or
/// 12 Latin ones. The user names them themselves, so a longer name is cut at the limit (never inside a letter, emoji or
/// accent, with no ellipsis) rather than refused.
enum ArisTeammateName {
    static let limit = 12

    /// The East Asian wide ranges: Hangul Jamo and syllables, CJK (radicals to compatibility), Yi, fullwidth forms.
    private static let wide: [ClosedRange<UInt32>] = [
        0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xA000...0xA4CF,
        0xA960...0xA97F, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60, 0xFFE0...0xFFE6,
        0x20000...0x2FFFD, 0x30000...0x3FFFD,
    ]

    /// One letter's width: 2 when its first scalar is wide, else 1.
    private static func width(of letter: Character) -> Int {
        guard let first = letter.unicodeScalars.first?.value else { return 0 }
        return wide.contains { $0.contains(first) } ? 2 : 1
    }

    static func width(_ name: String) -> Int {
        name.reduce(0) { $0 + width(of: $1) }
    }

    /// The name trimmed and cut to the limit, letter by letter; nil when nothing is left.
    static func validate(_ name: String) -> String? {
        let capped = cap(name.trimmingCharacters(in: .whitespacesAndNewlines))
        return capped.isEmpty ? nil : capped
    }

    /// The cap while the user types: the same width, never trimmed (so a space can be typed between two words).
    static func fitting(_ name: String) -> String {
        var used = 0
        return String(name.prefix { letter in
            used += width(of: letter)
            return used <= limit
        })
    }

    /// The same cap for showing a name kept from before the limit (or a worker's): never wider than a chip allows.
    static func display(_ name: String) -> String {
        validate(name) ?? name
    }

    private static func cap(_ name: String) -> String {
        fitting(name).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Who a request speaks to: only a teammate named at its very start ("코디야 …", "코디아 …", "코디, …", "코디한테 …",
/// "코디에게 …", "hey 코디 …").
enum ArisTeamRouting {
    static func addressee(in text: String, teammates: [ArisTeammate]) -> ArisTeammate? {
        let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let rest = spoken.range(of: #"^hey\s+"#, options: [.regularExpression, .caseInsensitive]).map { String(spoken[$0.upperBound...]) }
        // Longer names first, so "Claude Code" isn't taken for a teammate called "Claude".
        for teammate in teammates.sorted(by: { $0.name.count > $1.name.count }) where !teammate.name.isEmpty {
            if let rest, let after = after(teammate.name, in: rest), endsWord(after) { return teammate }
            guard let after = after(teammate.name, in: spoken) else { continue }
            for marker in ["야", "아", ",", "한테", "에게", "께"] where after.hasPrefix(marker) && endsWord(after.dropFirst(marker.count)) {
                return teammate
            }
        }
        return nil
    }

    /// "이 말이면 누가 맡을까요?": the teammate (never Claude Code, which only takes coding in a project folder) whose
    /// 언제 부를까요 and name share the most words with `text` (each word of two letters or more, by its first two), nil when
    /// none shares any or two share as many. The 팀원 page's test line shows it, and main Aris's <teammates> block names
    /// it as the likely one (the brain still decides).
    static func bestMatch(_ text: String, teammates: [ArisTeammate]) -> ArisTeammate? {
        let words = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 1 }
        guard !words.isEmpty else { return nil }
        let scored = teammates.filter { $0.id != ArisTeammate.claudeCodeId && !$0.routing.isEmpty }.map { mate -> (ArisTeammate, Int) in
            let hay = (mate.routing + " " + mate.name).lowercased()
            return (mate, words.filter { hay.contains(String($0.prefix(2))) }.count)
        }.filter { $0.1 > 0 }
        guard let best = scored.max(by: { $0.1 < $1.1 }), scored.filter({ $0.1 == best.1 }).count == 1 else { return nil }
        return best.0
    }

    /// What follows `name` when `text` starts with it (any case).
    private static func after(_ name: String, in text: String) -> Substring? {
        guard let found = text.range(of: name, options: [.caseInsensitive, .anchored]) else { return nil }
        return text[found.upperBound...]
    }

    /// The word ended: nothing, a space or punctuation follows.
    private static func endsWord(_ rest: Substring) -> Bool {
        guard let next = rest.unicodeScalars.first else { return true }
        return CharacterSet.whitespacesAndNewlines.contains(next) || CharacterSet.punctuationCharacters.contains(next)
    }
}
