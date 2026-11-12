//
//  ArisTurnImage.swift
//  Aris (also built into aris-agent)
//
//  An image that travels with one turn: the screenshot of the display under the pointer, a window the user circled
//  (numbered 1–8), or the whole screen with what he drew. The app sends them in POST /ask as "images"; the agent
//  checks every one here before any brain sees it (neither Codex nor Claude refuses bad bytes, P1.0). Any problem
//  refuses the whole turn, so nothing is half used. Images live in memory only. Pure, so the tests run it.
//

import CoreGraphics
import Foundation

enum ArisTurnImageError: Error, Equatable {
    /// Not a list of objects, a field of the wrong type, or no data.
    case shape
    case kind, mime
    /// Not base64.
    case encoding
    /// Over `maxBytesEach`.
    case size
    /// The bytes aren't the format the mime names.
    case magic
    /// Not a whole PNG or JPEG (truncated, damaged, no image data).
    case header
    /// Long edge over `maxLongEdge`.
    case dimensions
    /// A gesture shot without a unique badge in 1…8, or a badge on another kind.
    case badge
    /// Over 1 cursor, 8 gesture or 3 drawing images.
    case counts
    /// The cursor shot with gesture shots or a drawing (a gesture turn has no cursor shot).
    case mixed
}

struct ArisTurnImage: Equatable {
    enum Kind: String { case cursor, gesture, drawing }

    let kind: Kind
    /// Aris's own file name for it (never the sender's): cursor-screen.png, gesture-screenshot-N.jpg, drawing-reference-K.jpg.
    let name: String
    let format: ArisImageFormat
    let data: Data
    /// The number in a gesture shot's corner, 1…8.
    let badge: Int?
    /// The circled window's app and title: other people's words, cleaned and capped.
    let app: String?
    let title: String?

    static let maxBytesEach = 6 * 1_048_576
    static let maxLongEdge = 3_072
    static let maxCursor = 1, maxGesture = 8, maxDrawing = 3
    static let maxApp = 40, maxTitle = 120
    /// The longest base64 that can decode to `maxBytesEach`: anything longer is refused before decoding.
    static let maxBase64 = (maxBytesEach + 2) / 3 * 4

    /// What the brain reads next to the image, e.g. "gesture-screenshot-2.jpg — 동그라미 2: Safari — Pull request #12".
    var label: String {
        let what: String
        switch kind {
        case .cursor: what = "지금 화면"
        case .gesture: what = "동그라미 \(badge ?? 0)"
        case .drawing: what = "그린 화면 \(name.filter(\.isNumber))"
        }
        let details = [app, title].compactMap { $0 }
        return "\(name) — \(what)" + (details.isEmpty ? "" : ": " + details.joined(separator: " — "))
    }

    var base64: String { data.base64EncodedString() }

    var dataURL: String { "data:\(format.rawValue);base64,\(base64)" }

    /// One entry of /ask's "images", as the app sends it.
    var json: [String: Any] {
        var entry: [String: Any] = ["kind": kind.rawValue, "name": name, "mime": format.rawValue, "data": base64]
        if let badge { entry["badge"] = badge }
        if let app { entry["app"] = app }
        if let title { entry["title"] = title }
        return entry
    }

    /// /ask's "images" (nil or absent: none). Every entry passes, or the turn is refused.
    static func parse(_ value: Any?) -> Result<[ArisTurnImage], ArisTurnImageError> {
        guard let value, !(value is NSNull) else { return .success([]) }
        guard let list = value as? [Any] else { return .failure(.shape) }
        guard list.count <= maxCursor + maxGesture + maxDrawing else { return .failure(.counts) }
        var entries: [(Kind, [String: Any])] = []
        for item in list {
            guard let entry = item as? [String: Any], let raw = entry["kind"] as? String else { return .failure(.shape) }
            guard let kind = Kind(rawValue: raw) else { return .failure(.kind) }
            entries.append((kind, entry))
        }
        let count = { (kind: Kind) in entries.filter { $0.0 == kind }.count }
        guard count(.cursor) <= maxCursor, count(.gesture) <= maxGesture, count(.drawing) <= maxDrawing else { return .failure(.counts) }
        guard count(.cursor) == 0 || (count(.gesture) == 0 && count(.drawing) == 0) else { return .failure(.mixed) }

        var images: [ArisTurnImage] = []
        var badges: Set<Int> = []
        var drawings = 0
        for (kind, entry) in entries {
            if kind == .drawing { drawings += 1 }
            switch image(kind, entry, drawing: drawings) {
            case .failure(let error): return .failure(error)
            case .success(let image):
                if let badge = image.badge {
                    guard badges.insert(badge).inserted else { return .failure(.badge) }
                }
                images.append(image)
            }
        }
        return .success(images)
    }

    private static func image(_ kind: Kind, _ entry: [String: Any], drawing: Int) -> Result<ArisTurnImage, ArisTurnImageError> {
        guard let mime = entry["mime"] as? String, let encoded = entry["data"] as? String else { return .failure(.shape) }
        guard let format = ArisImageFormat(rawValue: mime) else { return .failure(.mime) }
        guard encoded.utf8.count <= maxBase64 else { return .failure(.size) }
        guard let data = Data(base64Encoded: encoded) else { return .failure(.encoding) }
        guard data.count <= maxBytesEach else { return .failure(.size) }
        guard !data.isEmpty, ArisImageCodec.format(of: data) == format else { return .failure(.magic) }
        let declared = format == .png ? ArisImageCheck.png(data) : ArisImageCheck.jpeg(data)
        guard let declared, let pixels = ArisImageCodec.pixelSize(of: data),
              Int(pixels.width) == declared.width, Int(pixels.height) == declared.height else { return .failure(.header) }
        guard max(declared.width, declared.height) <= maxLongEdge else { return .failure(.dimensions) }

        let badge: Int?
        switch badgeValue(entry["badge"]) {
        case .failure(let error): return .failure(error)
        case .success(let value): badge = value
        }
        if kind == .gesture {
            guard let badge, (1...maxGesture).contains(badge) else { return .failure(.badge) }
        } else if badge != nil {
            return .failure(.badge)
        }
        guard case .success(let app) = cleaned(entry["app"], max: maxApp),
              case .success(let title) = cleaned(entry["title"], max: maxTitle) else { return .failure(.shape) }
        return .success(ArisTurnImage(kind: kind, name: name(kind, format: format, badge: badge, drawing: drawing), format: format,
                                      data: data, badge: badge, app: app, title: title))
    }

    private static func name(_ kind: Kind, format: ArisImageFormat, badge: Int?, drawing: Int) -> String {
        let ext = format == .png ? "png" : "jpg"
        switch kind {
        case .cursor: return "cursor-screen.\(ext)"
        case .gesture: return "gesture-screenshot-\(badge ?? 0).\(ext)"
        case .drawing: return "drawing-reference-\(drawing).\(ext)"
        }
    }

    /// A whole number (not a JSON true/false); absent is nil.
    private static func badgeValue(_ value: Any?) -> Result<Int?, ArisTurnImageError> {
        guard let value, !(value is NSNull) else { return .success(nil) }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let whole = Int(exactly: number.doubleValue) else { return .failure(.badge) }
        return .success(whole)
    }

    /// Other people's text as one plain line: line breaks become spaces, control and invisible format characters
    /// (bidi overrides, zero-width) go, and it's capped. Absent or empty is nil; a non-string is refused.
    private static func cleaned(_ value: Any?, max: Int) -> Result<String?, ArisTurnImageError> {
        guard let value, !(value is NSNull) else { return .success(nil) }
        guard let text = value as? String else { return .failure(.shape) }
        let scalars = text.unicodeScalars.compactMap { scalar -> Unicode.Scalar? in
            if scalar.properties.isWhitespace { return " " }
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .privateUse, .surrogate, .unassigned: return nil
            default: return scalar
            }
        }
        let line = String(String.UnicodeScalarView(scalars)).split(separator: " ").joined(separator: " ")
        // At most `max` characters and `max` scalars, cut between characters (stacked combining marks count).
        var capped = "", count = 0
        for character in line.prefix(max) {
            count += character.unicodeScalars.count
            guard count <= max else { break }
            capped.append(character)
        }
        return .success(capped.isEmpty ? nil : capped)
    }
}

/// What "이거/this" most likely means on an image turn (the agent tells the brain): the screen when the user circled
/// something or the notch isn't showing the last answer; that answer when the open notch shows it.
enum ArisReferenceFocus: String {
    case screen, panel

    static func of(hasShots: Bool, notchShowsAnswer: Bool) -> ArisReferenceFocus {
        hasShots || !notchShowsAnswer ? .screen : .panel
    }
}
