//
//  ArisMCPSchema.swift
//  aris-agent
//
//  An MCP tool's arguments checked against the tool's own input schema before anything is sent: the JSON Schema
//  keywords tools use (type, properties, required, additionalProperties, enum, const, items, lengths, bounds,
//  anyOf/oneOf/allOf and local $ref), within a step budget and a time limit. A server's `pattern` is never run here (a
//  regex someone else wrote can backtrack for ever; the server checks it itself). The schema comes from the server, so it is read defensively: too deep, a $ref
//  that can't be found or a value of the wrong shape is a problem, never a pass. Pure, so the tests run it.
//

import Foundation

enum ArisMCPSchema {
    /// Deeper than this, in the schema or the value, is refused.
    static let maxDepth = 16
    /// The most a call's arguments may weigh as JSON.
    static let maxArgumentBytes = 64 * 1_024
    /// The most schema nodes one check visits, how long it may take, and how many shapes an anyOf/oneOf may offer.
    static let maxSteps = 20_000
    static let timeLimit: TimeInterval = 0.25
    static let maxBranches = 16

    /// One check's budget (security review I4).
    final class Walk {
        private var steps = 0
        private let deadline = Date().addingTimeInterval(ArisMCPSchema.timeLimit)
        /// False once the budget is spent.
        func step() -> Bool {
            steps += 1
            return steps <= ArisMCPSchema.maxSteps && (steps % 128 != 0 || Date() < deadline)
        }
    }

    /// Nil when `arguments` fit `schema`; else the first problem, as "<path>: <what>".
    static func problem(_ arguments: [String: Any], schema: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(arguments),
              let data = try? JSONSerialization.data(withJSONObject: arguments) else { return "arguments: not JSON" }
        guard data.count <= maxArgumentBytes else { return "arguments: larger than \(maxArgumentBytes / 1_024) KB" }
        // A tool's arguments are always an object, whatever the schema says about its root.
        var root = schema
        if root["type"] == nil { root["type"] = "object" }
        return check(arguments, root, root: schema, path: "arguments", depth: 0, walk: Walk())
    }

    private static func check(_ value: Any, _ schema: [String: Any], root: [String: Any], path: String, depth: Int, walk: Walk) -> String? {
        guard depth <= maxDepth else { return "\(path): nested too deeply" }
        guard walk.step() else { return "\(path): too complex to check" }
        if let reference = schema["$ref"] as? String {
            guard let target = resolve(reference, in: root) else { return "\(path): unknown schema reference" }
            if let problem = check(value, target, root: root, path: path, depth: depth + 1, walk: walk) { return problem }
        }
        if let types = typeList(schema["type"]), !types.contains(where: { matches(value, type: $0) }) {
            return "\(path): expected \(types.joined(separator: " or "))"
        }
        if let allowed = schema["enum"] as? [Any], !allowed.contains(where: { same($0, value) }) { return "\(path): not one of the allowed values" }
        if let constant = schema["const"], !same(constant, value) { return "\(path): must be \(constant)" }
        if let all = schema["allOf"] as? [[String: Any]] {
            for part in all { if let problem = check(value, part, root: root, path: path, depth: depth + 1, walk: walk) { return problem } }
        }
        for key in ["anyOf", "oneOf"] {
            if let options = schema[key] as? [[String: Any]], options.count > maxBranches { return "\(path): too many allowed shapes to check" }
            if let options = schema[key] as? [[String: Any]], !options.isEmpty,
               !options.contains(where: { check(value, $0, root: root, path: path, depth: depth + 1, walk: walk) == nil }) {
                return "\(path): matches none of the allowed shapes"
            }
        }
        switch value {
        case let text as String: return string(text, schema, path: path)
        case let number as NSNumber where !isBool(number): return self.number(number, schema, path: path)
        case let list as [Any]: return array(list, schema, root: root, path: path, depth: depth, walk: walk)
        case let object as [String: Any]: return self.object(object, schema, root: root, path: path, depth: depth, walk: walk)
        default: return nil
        }
    }

    private static func string(_ text: String, _ schema: [String: Any], path: String) -> String? {
        if let least = int(schema["minLength"]), text.count < least { return "\(path): shorter than \(least)" }
        if let most = int(schema["maxLength"]), text.count > most { return "\(path): longer than \(most)" }
        return nil
    }

    private static func number(_ number: NSNumber, _ schema: [String: Any], path: String) -> String? {
        let value = number.doubleValue
        if let least = double(schema["minimum"]), value < least { return "\(path): below \(least)" }
        if let most = double(schema["maximum"]), value > most { return "\(path): above \(most)" }
        if let least = double(schema["exclusiveMinimum"]), value <= least { return "\(path): not above \(least)" }
        if let most = double(schema["exclusiveMaximum"]), value >= most { return "\(path): not below \(most)" }
        return nil
    }

    private static func array(_ list: [Any], _ schema: [String: Any], root: [String: Any], path: String, depth: Int, walk: Walk) -> String? {
        if let least = int(schema["minItems"]), list.count < least { return "\(path): fewer than \(least) items" }
        if let most = int(schema["maxItems"]), list.count > most { return "\(path): more than \(most) items" }
        guard let items = schema["items"] as? [String: Any] else { return nil }
        for (index, item) in list.enumerated() {
            if let problem = check(item, items, root: root, path: "\(path)[\(index)]", depth: depth + 1, walk: walk) { return problem }
        }
        return nil
    }

    private static func object(_ object: [String: Any], _ schema: [String: Any], root: [String: Any], path: String, depth: Int, walk: Walk) -> String? {
        let properties = schema["properties"] as? [String: Any] ?? [:]
        for name in (schema["required"] as? [String] ?? []).sorted() where object[name] == nil || object[name] is NSNull {
            return "\(path).\(name): required"
        }
        for name in object.keys.sorted() {
            let inner = object[name] as Any
            if let property = properties[name] as? [String: Any] {
                if let problem = check(inner, property, root: root, path: "\(path).\(name)", depth: depth + 1, walk: walk) { return problem }
            } else if let extra = schema["additionalProperties"] {
                if let flag = extra as? NSNumber, isBool(flag), !flag.boolValue { return "\(path).\(name): not a field this tool takes" }
                if let extraSchema = extra as? [String: Any],
                   let problem = check(inner, extraSchema, root: root, path: "\(path).\(name)", depth: depth + 1, walk: walk) { return problem }
            }
        }
        return nil
    }

    /// "#/$defs/x" or "#/definitions/x" inside the tool's own schema; nil for anything else.
    private static func resolve(_ reference: String, in root: [String: Any]) -> [String: Any]? {
        if reference == "#" { return root }
        guard reference.hasPrefix("#/") else { return nil }
        var node: Any = root
        for part in reference.dropFirst(2).split(separator: "/") {
            let key = part.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
            guard let object = node as? [String: Any], let next = object[key] else { return nil }
            node = next
        }
        return node as? [String: Any]
    }

    private static func typeList(_ raw: Any?) -> [String]? {
        if let one = raw as? String { return [one] }
        if let many = raw as? [String], !many.isEmpty { return many }
        return nil
    }

    static func matches(_ value: Any, type: String) -> Bool {
        switch type {
        case "string": return value is String
        case "boolean": return (value as? NSNumber).map(isBool) == true
        case "number": return (value as? NSNumber).map { !isBool($0) } == true
        case "integer":
            guard let number = value as? NSNumber, !isBool(number) else { return false }
            return number.doubleValue.rounded() == number.doubleValue && abs(number.doubleValue) < 9.0e15
        case "array": return value is [Any]
        case "object": return value is [String: Any]
        case "null": return value is NSNull
        default: return false
        }
    }

    /// JSON equality for enum and const (numbers by value, booleans apart from numbers).
    private static func same(_ a: Any, _ b: Any) -> Bool {
        switch (a, b) {
        case (let x as String, let y as String): return x == y
        case (let x as NSNumber, let y as NSNumber): return isBool(x) == isBool(y) && x == y
        case (is NSNull, is NSNull): return true
        case (let x as [Any], let y as [Any]): return x.count == y.count && zip(x, y).allSatisfy(same)
        case (let x as [String: Any], let y as [String: Any]):
            return Set(x.keys) == Set(y.keys) && x.allSatisfy { key, value in y[key].map { same(value, $0) } ?? false }
        default: return false
        }
    }

    static func isBool(_ number: NSNumber) -> Bool { CFGetTypeID(number) == CFBooleanGetTypeID() }

    private static func int(_ raw: Any?) -> Int? {
        guard let number = raw as? NSNumber, !isBool(number) else { return nil }
        return number.intValue
    }

    private static func double(_ raw: Any?) -> Double? {
        guard let number = raw as? NSNumber, !isBool(number) else { return nil }
        return number.doubleValue
    }

    // MARK: - key=value arguments

    /// `key=value` words (the sealed form, with no JSON) as the tool's arguments: each value read as the schema's
    /// property type says (a number, true/false, or text); nil when a word isn't `key=value`, a key repeats or a value
    /// doesn't read as its type. Only top-level fields can be given this way.
    static func pairs(_ words: [String], schema: [String: Any]) -> [String: Any]? {
        let properties = schema["properties"] as? [String: Any] ?? [:]
        var arguments: [String: Any] = [:]
        for word in words {
            guard let equals = word.firstIndex(of: "="), equals != word.startIndex else { return nil }
            let key = String(word[..<equals]), raw = String(word[word.index(after: equals)...])
            guard arguments[key] == nil else { return nil }
            let types = typeList((properties[key] as? [String: Any])?["type"]) ?? ["string"]
            if types.contains("string") {
                arguments[key] = raw
            } else if types.contains("integer"), let number = Int(raw) {
                arguments[key] = number
            } else if types.contains("number"), let number = Double(raw) {
                arguments[key] = number
            } else if types.contains("boolean"), raw == "true" || raw == "false" {
                arguments[key] = raw == "true"
            } else {
                return nil
            }
        }
        return arguments
    }
}
