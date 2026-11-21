//
//  ArisAppsSdef.swift
//  Shared/Core/Apps
//
//  An app's scripting dictionary (its .sdef, as `sdef <app>` prints it with the includes expanded) read into commands,
//  classes and enumerations: the channel that runs in the background and answers with a result. Hidden terms are
//  kept out. `xi:include`s left in a raw file are listed so the caller can read them too. Pure (XMLParser).
//

import Foundation

extension ArisApps {
    enum Sdef {
        struct Parameter: Codable, Equatable, Sendable {
            var name: String
            var code: String
            var type: String
            var optional: Bool
            var description: String
        }

        struct Command: Codable, Equatable, Sendable {
            var name: String
            var code: String
            var suite: String
            var description: String
            var direct: Parameter?
            var parameters: [Parameter]
            var result: String?
        }

        struct Property: Codable, Equatable, Sendable {
            var name: String
            var code: String
            var type: String
            var writable: Bool
            var description: String
        }

        struct ClassDef: Codable, Equatable, Sendable {
            var name: String
            var code: String
            var plural: String?
            var inherits: String?
            /// A class-extension (`extends`): it adds to a class defined elsewhere.
            var extends: Bool
            var description: String
            var properties: [Property]
            var elements: [String]
            var responds: [String]
        }

        struct Enumeration: Codable, Equatable, Sendable {
            var name: String
            var code: String
            var values: [String]
        }

        /// An `xi:include` a raw file kept: the file it names, and the commands its xpointer leaves out.
        struct Include: Codable, Equatable, Sendable {
            var href: String
            var excluded: [String]

            /// The local path of a file:// href ("file://localhost/System/…" and "file:///System/…").
            var path: String? {
                guard href.hasPrefix("file://") else { return nil }
                let rest = href.dropFirst(7)
                return rest.hasPrefix("localhost/") ? String(rest.dropFirst(9)) : String(rest)
            }
        }

        struct Dictionary: Codable, Equatable, Sendable {
            var suites: [String] = []
            var commands: [Command] = []
            var classes: [ClassDef] = []
            var enumerations: [Enumeration] = []
            var includes: [Include] = []

            var isEmpty: Bool { commands.isEmpty && classes.isEmpty }

            /// The class with this name, its extensions folded in.
            func classNamed(_ name: String) -> ClassDef? {
                let all = classes.filter { $0.name == name }
                guard var first = all.first(where: { !$0.extends }) ?? all.first else { return nil }
                for more in all where more != first {
                    first.properties += more.properties.filter { added in !first.properties.contains { $0.name == added.name } }
                    first.elements += more.elements.filter { !first.elements.contains($0) }
                    first.responds += more.responds.filter { !first.responds.contains($0) }
                }
                return first
            }

            /// The classes the application holds as elements (`make new note`, `every window`).
            var topElements: [String] { classNamed("application")?.elements ?? [] }

            /// With its includes read in (`load` gives a file's bytes by path), the commands they leave out left out.
            func resolved(_ load: (String) -> Data?) -> Dictionary {
                var copy = self
                for include in includes {
                    guard let path = include.path, let data = load(path), var other = Sdef.parse(data) else { continue }
                    other.commands.removeAll { include.excluded.contains($0.name) }
                    copy = copy.merged(with: other)
                }
                copy.includes = []
                return copy
            }

            func merged(with other: Dictionary) -> Dictionary {
                var copy = self
                copy.suites += other.suites.filter { !copy.suites.contains($0) }
                copy.commands += other.commands.filter { added in !copy.commands.contains { $0.name == added.name } }
                copy.classes += other.classes
                copy.enumerations += other.enumerations.filter { added in !copy.enumerations.contains { $0.name == added.name } }
                return copy
            }
        }

        /// The command names an include's xpointer leaves out ("…[not(self::command and ((@name = 'delete') or …))]").
        static func excluded(_ xpointer: String) -> [String] {
            guard xpointer.contains("not(") else { return [] }
            var names: [String] = [], rest = Substring(xpointer)
            while let range = rest.range(of: "@name = '") {
                let after = rest[range.upperBound...]
                guard let end = after.firstIndex(of: "'") else { break }
                names.append(String(after[..<end]))
                rest = after[after.index(after: end)...]
            }
            return names
        }

        /// Parses sdef XML; nil when it is not a dictionary at all.
        static func parse(_ data: Data) -> Dictionary? {
            let reader = Reader()
            let parser = XMLParser(data: data)
            parser.shouldResolveExternalEntities = false
            parser.shouldProcessNamespaces = false
            parser.delegate = reader
            guard parser.parse() || reader.sawDictionary else { return nil }
            return reader.sawDictionary ? reader.dictionary : nil
        }

        private final class Reader: NSObject, XMLParserDelegate {
            var dictionary = Dictionary()
            var sawDictionary = false
            private var suite = ""
            private var suiteHidden = false
            private var command: Command?
            private var commandHidden = false
            private var parameter: Parameter?
            private var parameterIsDirect = false
            private var klass: ClassDef?
            private var classHidden = false
            private var property: Property?
            private var enumeration: Enumeration?
            private var inResult = false

            private func hidden(_ attributes: [String: String]) -> Bool { attributes["hidden"] == "yes" }

            func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                        attributes: [String: String] = [:]) {
                switch name {
                case "dictionary": sawDictionary = true
                case "xi:include", "include":
                    if let href = attributes["href"] { dictionary.includes.append(Include(href: href, excluded: Sdef.excluded(attributes["xpointer"] ?? ""))) }
                case "suite":
                    suite = attributes["name"] ?? ""
                    suiteHidden = hidden(attributes)
                    if !suiteHidden, !suite.isEmpty, !dictionary.suites.contains(suite) { dictionary.suites.append(suite) }
                case "command" where command == nil:
                    commandHidden = hidden(attributes) || suiteHidden
                    command = Command(name: attributes["name"] ?? "", code: attributes["code"] ?? "", suite: suite,
                                      description: attributes["description"] ?? "", direct: nil, parameters: [], result: attributes["result"])
                case "direct-parameter", "parameter":
                    guard command != nil else { return }
                    parameterIsDirect = name == "direct-parameter"
                    parameter = Parameter(name: attributes["name"] ?? (parameterIsDirect ? "" : "?"), code: attributes["code"] ?? "",
                                          type: attributes["type"] ?? "", optional: attributes["optional"] == "yes",
                                          description: attributes["description"] ?? "")
                    if hidden(attributes) { parameter = nil }
                case "result":
                    inResult = true
                    if let type = attributes["type"] { command?.result = type }
                case "type":
                    guard let type = attributes["type"] else { return }
                    let shown = attributes["list"] == "yes" ? "list of \(type)" : type
                    if parameter != nil { parameter!.type = parameter!.type.isEmpty ? shown : parameter!.type + " | " + shown }
                    else if inResult, command != nil { command!.result = (command!.result.map { $0 + " | " } ?? "") + shown }
                    else if property != nil { property!.type = property!.type.isEmpty ? shown : property!.type + " | " + shown }
                case "class", "class-extension":
                    guard klass == nil else { return }
                    classHidden = hidden(attributes) || suiteHidden
                    let extends = name == "class-extension"
                    klass = ClassDef(name: attributes[extends ? "extends" : "name"] ?? "", code: attributes["code"] ?? "", plural: attributes["plural"],
                                     inherits: attributes["inherits"], extends: extends, description: attributes["description"] ?? "",
                                     properties: [], elements: [], responds: [])
                case "property":
                    guard klass != nil else { return }
                    property = Property(name: attributes["name"] ?? "", code: attributes["code"] ?? "", type: attributes["type"] ?? "",
                                        writable: attributes["access"] != "r", description: attributes["description"] ?? "")
                    if hidden(attributes) { property = nil }
                case "element":
                    if let type = attributes["type"], !hidden(attributes) { klass?.elements.append(type) }
                case "responds-to":
                    if let command = attributes["command"] ?? attributes["name"] { klass?.responds.append(command) }
                case "enumeration":
                    enumeration = Enumeration(name: attributes["name"] ?? "", code: attributes["code"] ?? "", values: [])
                    if hidden(attributes) || suiteHidden { enumeration = nil }
                case "enumerator":
                    if let value = attributes["name"], !hidden(attributes) { enumeration?.values.append(value) }
                default: break
                }
            }

            func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
                switch name {
                case "command":
                    if let command, !commandHidden, !command.name.isEmpty { dictionary.commands.append(command) }
                    command = nil
                case "direct-parameter", "parameter":
                    if let parameter, command != nil {
                        if parameterIsDirect { command!.direct = parameter } else { command!.parameters.append(parameter) }
                    }
                    parameter = nil
                case "result": inResult = false
                case "class", "class-extension":
                    if let klass, !classHidden, !klass.name.isEmpty { dictionary.classes.append(klass) }
                    klass = nil
                case "property":
                    if let property, klass != nil { klass!.properties.append(property) }
                    property = nil
                case "enumeration":
                    if let enumeration { dictionary.enumerations.append(enumeration) }
                    enumeration = nil
                case "suite":
                    suite = ""
                    suiteHidden = false
                default: break
                }
            }
        }
    }
}
