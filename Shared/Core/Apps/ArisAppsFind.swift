//
//  ArisAppsFind.swift
//  Shared/Core/Apps
//
//  app.find: what a person calls an app, resolved to a bundle. The candidates are every installed and running app
//  with every name its bundle carries (file name, shown name in each language), the catalog's nicknames for it, and
//  the names the owner taught by correcting Aris. Each is scored (exact, a learned alias, a prefix, a word inside the
//  name, a jamo-level near miss, a cross-script sound-alike) and the ranked list becomes one answer: the app, the web
//  service in the default browser when no app for it is installed, one short question when two are close or the best
//  is only a guess, or nothing. Pure.
//

import Foundation

extension ArisApps {
    /// An app as the system reports it (LaunchServices / Spotlight, the running list).
    struct AppRecord: Codable, Equatable, Sendable {
        var bundle: String
        /// Every name it carries: the file name, the shown name in each language its bundle has.
        var names: [String]
        var path: String? = nil
        var version: String? = nil
        var running = false
        var frontmost = false
        var installed = true
    }

    /// Names the owner taught ("카톡 말고 카카오톡 베타야"): said key → bundle id.
    struct Aliases: Codable, Equatable, Sendable {
        var byKey: [String: String] = [:]

        func learning(_ said: String, bundle: String) -> Aliases {
            let key = Text.core(said)
            guard !key.isEmpty, !bundle.isEmpty else { return self }
            var copy = self
            copy.byKey[key] = bundle
            return copy
        }

        func forgetting(_ said: String) -> Aliases {
            var copy = self
            copy.byKey[Text.core(said)] = nil
            return copy
        }

        func bundle(for said: String) -> String? {
            for form in Text.forms(said) { if let bundle = byKey[form] { return bundle } }
            return nil
        }
    }

    enum Find {
        struct Match: Equatable, Sendable {
            var bundle: String?
            var name: String
            var score: Double
            /// Why it matched ("exact name", "nickname 카톡", "learned", "near 까톡"…).
            var why: String
            var web: String? = nil
            var installed: Bool
            var running = false
            var path: String? = nil

            var json: JSON {
                var object: [String: JSON] = ["name": .string(name), "confidence": .number((score * 100).rounded() / 100),
                                              "why": .string(why), "installed": .bool(installed), "running": .bool(running)]
                if let bundle { object["bundle"] = .string(bundle) }
                if let web { object["web"] = .string(web) }
                if let path { object["path"] = .string(path) }
                return .object(object)
            }
        }

        enum Answer: Equatable, Sendable {
            /// The app (installed).
            case app(Match)
            /// No app for it is installed: its web address, opened in the default browser.
            case web(Match)
            /// Two or more are close, or the best is a guess: one short question.
            case ask([Match])
            /// Known, but not on this Mac and with no web address.
            case notInstalled(Match)
            case none
        }

        // MARK: - Scores

        static let exactAlias = 1.0, exactName = 0.98, exactNickname = 0.96, exactBundleTail = 0.9
        /// At or above: an answer without asking, when nothing else is close.
        static let sure = 0.8
        /// Below: not a match at all.
        static let floor = 0.55
        /// Within this of the best, another app is close enough to ask about.
        static let close = 0.12

        /// How well one of the said forms meets one name, and why.
        static func score(_ forms: [String], name: String, nickname: Bool) -> (Double, String) {
            let target = Text.key(name)
            guard !target.isEmpty else { return (0, "") }
            var best: (Double, String) = (0, "")
            func take(_ value: Double, _ why: String) { if value > best.0 { best = (value, why) } }
            for said in forms where !said.isEmpty {
                if said == target { take(nickname ? exactNickname : exactName, nickname ? "nickname \(name)" : "exact name"); continue }
                let ratio = Double(min(said.count, target.count)) / Double(max(said.count, target.count))
                if said.count >= 2 {
                    if target.hasPrefix(said) { take(0.72 + 0.2 * ratio, "start of \(name)") }
                    // A word of the name ("code" in Visual Studio Code, "teams" in Microsoft Teams).
                    let words = name.precomposedStringWithCanonicalMapping.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
                    if words.count > 1, words.contains(where: { Text.key($0) == said }) { take(0.78 + 0.12 * ratio, "word of \(name)") }
                    else if target.contains(said) { take(0.6 + 0.2 * ratio, "inside \(name)") }
                }
                if said.count >= 2, Text.hasHangul(said) == Text.hasHangul(target) {
                    let near = Text.similarity(said, target)
                    if near >= 0.75 { take(0.4 + 0.5 * near, "near \(name)") }
                }
                if Text.hasHangul(said) != Text.hasHangul(target), Text.skeleton(said).count >= 3, Text.soundsLike(said, target) >= 0.9 {
                    take(0.7, "sounds like \(name)")
                }
            }
            return best
        }

        /// Every candidate ranked, best first; one entry per app.
        static func rank(_ said: String, apps: [AppRecord], aliases: Aliases = Aliases(), rows: [Catalog.Row] = Catalog.rows) -> [Match] {
            let forms = Text.forms(said)
            guard !forms.isEmpty else { return [] }
            let taught = aliases.bundle(for: said)
            var matches: [String: Match] = [:]
            var rowsSeen = Set<Int>()
            // Installed and running apps, by their own names and their row's nicknames.
            var byBundle: [String: AppRecord] = [:]
            for app in apps {
                let key = app.bundle.lowercased()
                if var known = byBundle[key] {
                    known.names += app.names.filter { !known.names.contains($0) }
                    known.running = known.running || app.running
                    known.frontmost = known.frontmost || app.frontmost
                    known.installed = known.installed || app.installed
                    if known.path == nil { known.path = app.path }
                    byBundle[key] = known
                } else {
                    byBundle[key] = app
                }
            }
            for app in byBundle.values.sorted(by: { $0.bundle < $1.bundle }) {
                let rowIndex = rows.firstIndex { $0.bundles.contains { $0.caseInsensitiveCompare(app.bundle) == .orderedSame } }
                if let rowIndex { rowsSeen.insert(rowIndex) }
                let row = rowIndex.map { rows[$0] }
                var best: (Double, String) = (0, "")
                if let taught, taught.caseInsensitiveCompare(app.bundle) == .orderedSame { best = (exactAlias, "learned") }
                if forms.contains(Text.key(app.bundle)), best.0 < exactAlias { best = (exactAlias, "bundle id") }
                if let tail = app.bundle.split(separator: ".").last, forms.contains(Text.key(String(tail))), best.0 < exactBundleTail {
                    best = (exactBundleTail, "bundle id")
                }
                for name in app.names + (row.map { [$0.name] } ?? []) {
                    let found = score(forms, name: name, nickname: false)
                    if found.0 > best.0 { best = found }
                }
                for nickname in row?.says ?? [] {
                    let found = score(forms, name: nickname, nickname: true)
                    if found.0 > best.0 { best = found }
                }
                guard best.0 >= floor else { continue }
                let bonus = (app.running ? 0.02 : 0) + (app.frontmost ? 0.01 : 0)
                let shown = app.names.first(where: { !Text.hasHangul($0) }) ?? app.names.first ?? row?.name ?? app.bundle
                matches[app.bundle.lowercased()] = Match(bundle: app.bundle, name: shown, score: min(1, best.0 + bonus), why: best.1,
                                                         web: row?.web, installed: app.installed, running: app.running, path: app.path)
            }
            // Rows of apps not on this Mac: web services, and apps that would have to be installed.
            for (index, row) in rows.enumerated() where !rowsSeen.contains(index) {
                var best = score(forms, name: row.name, nickname: false)
                for nickname in row.says {
                    let found = score(forms, name: nickname, nickname: true)
                    if found.0 > best.0 { best = found }
                }
                if let taught, row.bundles.contains(where: { $0.caseInsensitiveCompare(taught) == .orderedSame }) { best = (exactAlias, "learned") }
                guard best.0 >= floor else { continue }
                let key = row.bundles.first?.lowercased() ?? "web:" + row.name
                matches[key] = Match(bundle: row.bundles.first, name: row.name, score: best.0, why: best.1, web: row.web, installed: false)
            }
            return matches.values.sorted { $0.score != $1.score ? $0.score > $1.score : ($0.installed != $1.installed ? $0.installed : $0.name < $1.name) }
        }

        /// The one answer for a ranked list.
        static func answer(_ ranked: [Match]) -> Answer {
            guard let best = ranked.first, best.score >= floor else { return .none }
            let contenders = ranked.filter { $0.score >= best.score - close }
            if !best.installed {
                // Not on this Mac: an installed app that also fits is asked about before a web page or an install.
                if let installed = ranked.first(where: { $0.installed && $0.score >= 0.6 }) { return .ask([best, installed]) }
                if contenders.count > 1, contenders.contains(where: { $0.installed }) { return .ask(Array(contenders.prefix(3))) }
                return best.web != nil ? (best.score >= sure ? .web(best) : .ask([best])) : (best.score >= sure ? .notInstalled(best) : .ask([best]))
            }
            if best.score >= sure, contenders.count == 1 { return .app(best) }
            // What the owner taught wins over the catalog's guess.
            if best.why == "learned" { return .app(best) }
            // An exact name or nickname beats near ones ("Discord" with Discord PTB installed); two exact ones are asked.
            if best.score >= exactNickname, contenders.filter({ $0.score >= exactNickname }).count == 1 { return .app(best) }
            return .ask(Array(contenders.prefix(3)))
        }

        /// The short question for an `.ask`, Korean first, and the English line.
        static func question(_ said: String, _ matches: [Match]) -> (ko: String, en: String) {
            let names = matches.map { $0.installed || $0.web == nil ? $0.name : "\($0.name)(웹)" }
            if names.count == 1 {
                return ("‘\(said)’, \(names[0]) 말씀이세요?", "By ‘\(said)’, do you mean \(matches[0].name)?")
            }
            return ("‘\(said)’는 \(names.joined(separator: ", ")) 중 어느 앱인가요?",
                    "Which app is ‘\(said)’: \(matches.map(\.name).joined(separator: " or "))?")
        }
    }
}
