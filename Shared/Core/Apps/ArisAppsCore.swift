//
//  ArisAppsCore.swift
//  Shared/Core/Apps (app, aris-agent, tests, swift test)
//
//  The app layer's shared words (ARCHITECTURE Part 2, "Hands", jv-apps): a JSON value for arguments and results and the
//  outcome every capability returns (what happened, what is true now). All of
//  the app layer's types live inside `ArisApps` so nothing collides with the app's own names. Pure (Foundation only).
//

import Foundation

enum ArisApps {}

extension ArisApps {
    /// A JSON value: arguments in, results out. Sendable and comparable, unlike `[String: Any]`.
    enum JSON: Equatable, Sendable, Codable {
        case null
        case bool(Bool)
        case number(Double)
        case string(String)
        case array([JSON])
        case object([String: JSON])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() { self = .null }
            else if let value = try? container.decode(Bool.self) { self = .bool(value) }
            else if let value = try? container.decode(Double.self) { self = .number(value) }
            else if let value = try? container.decode(String.self) { self = .string(value) }
            else if let value = try? container.decode([JSON].self) { self = .array(value) }
            else { self = .object(try container.decode([String: JSON].self)) }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .null: try container.encodeNil()
            case .bool(let value): try container.encode(value)
            case .number(let value): try container.encode(value)
            case .string(let value): try container.encode(value)
            case .array(let value): try container.encode(value)
            case .object(let value): try container.encode(value)
            }
        }

        /// From what JSONSerialization gives (an MCP call's arguments).
        init(any value: Any?) {
            switch value {
            case nil, is NSNull: self = .null
            case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID(): self = .bool(number.boolValue)
            case let number as NSNumber: self = .number(number.doubleValue)
            case let text as String: self = .string(text)
            case let list as [Any]: self = .array(list.map { JSON(any: $0) })
            case let object as [String: Any]: self = .object(object.mapValues { JSON(any: $0) })
            default: self = .null
            }
        }

        /// As JSONSerialization takes it (the MCP face, the API brains' schemas).
        var any: Any {
            switch self {
            case .null: return NSNull()
            case .bool(let value): return value
            case .number(let value): return value.rounded() == value && abs(value) < 1e15 ? Int(value) as Any : value
            case .string(let value): return value
            case .array(let value): return value.map(\.any)
            case .object(let value): return value.mapValues(\.any)
            }
        }

        subscript(key: String) -> JSON? {
            if case .object(let object) = self { return object[key] }
            return nil
        }

        var string: String? {
            switch self {
            case .string(let value): return value
            case .number(let value): return value.rounded() == value ? String(Int(value)) : String(value)
            default: return nil
            }
        }

        var number: Double? {
            switch self {
            case .number(let value): return value
            case .string(let value): return Double(value.trimmingCharacters(in: .whitespaces))
            default: return nil
            }
        }

        var int: Int? { number.flatMap { $0.rounded() == $0 ? Int($0) : nil } }

        var bool: Bool? {
            switch self {
            case .bool(let value): return value
            case .string(let value): return ["true", "yes", "1"].contains(value.lowercased()) ? true : ["false", "no", "0"].contains(value.lowercased()) ? false : nil
            default: return nil
            }
        }

        var array: [JSON]? { if case .array(let value) = self { return value } else { return nil } }
        var object: [String: JSON]? { if case .object(let value) = self { return value } else { return nil } }

        /// Compact text, keys sorted (stable for tests and for the model).
        var text: String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
        }
    }

    /// What one call answers: whether it did it, what happened, what is true now, the data, and how it was done.
    struct Outcome: Equatable, Sendable {
        var ok: Bool
        /// What happened, in one line ("pressed File › New Window in TextEdit").
        var did: String
        /// What is true now, when the channel could check it ("TextEdit has 2 windows; the front one is Untitled 2").
        var now: String
        var data: JSON = .null
        /// The effect this call had (or would have had).
        var effect: Effect
        /// The channel that ran it ("sdef", "menu", "ax", "engine", "workspace", "url", "shortcut").
        var channel: String? = nil
        /// Whether the effect was seen to happen (a menu mark, a window that appeared, the script's answer).
        var verified: Bool = false
        /// One short question when the request is ambiguous (two apps called that, two menu items match).
        var question: String? = nil
        /// One sentence to say before a macOS permission prompt appears (once per app).
        var notice: String? = nil
        /// How to take this change back, when it can be (text app.type added: ArisApps.TextUndo); the record keeps it.
        var undo: ArisUndoRecipe? = nil

        static func failure(_ did: String, now: String = "", effect: Effect, data: JSON = .null) -> Outcome {
            Outcome(ok: false, did: did, now: now, data: data, effect: effect)
        }

        /// The result as the model reads it.
        var json: JSON {
            var object: [String: JSON] = ["ok": .bool(ok), "did": .string(did), "effect": .string(effect.rawValue), "verified": .bool(verified)]
            if !now.isEmpty { object["now"] = .string(now) }
            if data != .null { object["data"] = data }
            if let channel { object["channel"] = .string(channel) }
            if let question { object["question"] = .string(question) }
            if let notice { object["notice"] = .string(notice) }
            return .object(object)
        }
    }
}
