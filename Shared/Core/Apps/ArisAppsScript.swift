//
//  ArisAppsScript.swift
//  Shared/Core/Apps
//
//  The scripting-dictionary channel's words: a command from an app's sdef with the caller's arguments, written as one
//  AppleScript `tell application id …` line. Only terms the dictionary defines are written as terms; every value is a
//  quoted string, a number, a boolean or an object named by its class and name or id, so no argument can become code.
//  Pure.
//

import Foundation

extension ArisApps {
    enum Script {
        enum Problem: Error, Equatable {
            case unknownCommand(String)
            case unknownTerm(String)
            case badValue(String)
            case missing(String)
        }

        /// A term as the dictionary spells it: letters, digits and single spaces.
        static func isTerm(_ text: String) -> Bool {
            !text.isEmpty && text.count <= 64 && text.range(of: "^[A-Za-z][A-Za-z0-9]*( [A-Za-z0-9]+)*$", options: .regularExpression) != nil
        }

        static func quoted(_ text: String) -> String {
            "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }

        /// A value: text, a number, a boolean, a list of those, or {"class": "note", "name": "…"} / {"class", "id"}.
        static func value(_ json: JSON, dictionary: Sdef.Dictionary) throws -> String {
            switch json {
            case .string(let text): return quoted(text)
            case .number(let number):
                guard number.isFinite else { throw Problem.badValue("number") }
                return number.rounded() == number && abs(number) < 1e15 ? String(Int(number)) : String(number)
            case .bool(let flag): return flag ? "true" : "false"
            case .array(let list): return "{" + (try list.map { try value($0, dictionary: dictionary) }).joined(separator: ", ") + "}"
            case .object(let object):
                guard let klass = object["class"]?.string, isTerm(klass), dictionary.classNamed(klass) != nil else { throw Problem.unknownTerm(object["class"]?.string ?? "?") }
                if let id = object["id"] { return "\(klass) id \(try value(id, dictionary: dictionary))" }
                if let name = object["name"]?.string { return "\(klass) \(quoted(name))" }
                if let index = object["index"]?.int, index != 0 { return "\(klass) \(index)" }
                throw Problem.badValue(klass)
            case .null: throw Problem.badValue("null")
            }
        }

        /// `tell application id "<bundle>" to <command> [direct] [parameter value]…`.
        static func command(_ name: String, bundle: String, dictionary: Sdef.Dictionary, direct: JSON?, parameters: [String: JSON]) throws -> String {
            guard let command = dictionary.commands.first(where: { $0.name == name }), isTerm(name) else { throw Problem.unknownCommand(name) }
            var words = [name]
            if let direct, direct != .null { words.append(try value(direct, dictionary: dictionary)) }
            else if let needed = command.direct, !needed.optional, !["specifier", ""].contains(needed.type) { throw Problem.missing("direct object") }
            for (key, given) in parameters.sorted(by: { $0.key < $1.key }) {
                guard let parameter = command.parameters.first(where: { $0.name == key }), isTerm(key) else { throw Problem.unknownTerm(key) }
                words.append(parameter.name)
                words.append(try value(given, dictionary: dictionary))
            }
            for parameter in command.parameters where !parameter.optional && parameters[parameter.name] == nil {
                throw Problem.missing(parameter.name)
            }
            return "tell application id \(quoted(bundle)) to " + words.joined(separator: " ")
        }

        /// `make new <class> with properties {…}` (only the class's own properties).
        static func make(_ klass: String, bundle: String, dictionary: Sdef.Dictionary, properties: [String: JSON]) throws -> String {
            guard isTerm(klass), let definition = dictionary.classNamed(klass) else { throw Problem.unknownTerm(klass) }
            var pairs: [String] = []
            for (key, given) in properties.sorted(by: { $0.key < $1.key }) {
                guard isTerm(key), definition.properties.contains(where: { $0.name == key && $0.writable }) else { throw Problem.unknownTerm(key) }
                pairs.append("\(key):\(try value(given, dictionary: dictionary))")
            }
            let with = pairs.isEmpty ? "" : " with properties {\(pairs.joined(separator: ", "))}"
            return "tell application id \(quoted(bundle)) to make new \(klass)\(with)"
        }

        /// The names (or the count) of every object of a class the application holds.
        static func list(_ klass: String, bundle: String, dictionary: Sdef.Dictionary) throws -> String {
            guard isTerm(klass), let definition = dictionary.classNamed(klass) else { throw Problem.unknownTerm(klass) }
            let plural = definition.plural ?? klass + "s"
            guard isTerm(plural) else { throw Problem.unknownTerm(plural) }
            if definition.properties.contains(where: { $0.name == "name" }) || klass == "window" || klass == "document" {
                return "tell application id \(quoted(bundle)) to get name of every \(klass)"
            }
            return "tell application id \(quoted(bundle)) to count every \(klass)"
        }
    }
}
