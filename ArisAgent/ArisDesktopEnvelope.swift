//
//  ArisDesktopEnvelope.swift
//  aris-agent
//
//  One JSON envelope Peekaboo prints with --json (`success`, `data` or `error` with `code` and `message`, and for
//  actions an `outcome`: its state, whether anything was dispatched and whether a retry is safe), read for what Aris
//  needs. Its `debug_logs` are never passed on. An exit code or `success` is never taken as proof that something
//  happened: the controller reads the window back (ArisDesktopVerify). The data is the app's own words, so it is only
//  ever passed on as outside text, after the privacy filter. Pure.
//

import CoreGraphics
import Foundation

struct ArisDesktopEnvelope {
    let success: Bool
    let data: [String: Any]
    /// `data` as it came.
    let raw: Any?
    let code: String?
    let message: String?
    /// `outcome.state`: confirmed_change, confirmed_no_change, dispatched_unverified, refused, partial…
    let state: String?
    /// Peekaboo says repeating it is safe (nothing reached the app).
    let retrySafe: Bool
    /// Something reached the app (a click, keys, a menu step).
    let dispatched: Bool
    let refusal: String?
    /// The window and process Peekaboo acted on.
    let windowId: Int?
    let pid: Int32?

    static func parse(_ raw: Data) -> ArisDesktopEnvelope? {
        // Peekaboo prints one pretty-printed object; anything before its first brace (a stray notice) is skipped.
        guard let start = raw.firstIndex(of: UInt8(ascii: "{")),
              let object = (try? JSONSerialization.jsonObject(with: raw[start...])) as? [String: Any],
              let success = object["success"] as? Bool else { return nil }
        let error = object["error"] as? [String: Any] ?? [:]
        let outcome = object["outcome"] as? [String: Any] ?? [:]
        let receipt = (object["target_receipt"] ?? object["target_identity"]) as? [String: Any] ?? [:]
        let dispatched = (outcome["mutation_dispatched"] as? Bool) ?? (error["mutation_dispatched"] as? Bool) ?? false
        let retrySafe = (outcome["retry_safe"] as? Bool) ?? (error["retry_safe"] as? Bool) ?? false
        return ArisDesktopEnvelope(success: success, data: object["data"] as? [String: Any] ?? [:], raw: object["data"],
                                   code: error["code"] as? String, message: error["message"] as? String, state: outcome["state"] as? String,
                                   retrySafe: retrySafe, dispatched: dispatched, refusal: outcome["refusal_reason"] as? String,
                                   windowId: (receipt["window_id"] as? NSNumber)?.intValue, pid: (receipt["pid"] as? NSNumber).map { Int32(truncating: $0) })
    }

    /// The snapshot a `see` made (`ps1_` and 32 hex digits).
    var snapshotId: String? {
        guard let id = data["snapshot_id"] as? String, ArisPeekabooSnapshots.isSnapshotId(id) else { return nil }
        return id
    }

    var applicationName: String? { data["application_name"] as? String }
    var windowTitle: String? { data["window_title"] as? String }
    var isDialog: Bool { data["is_dialog"] as? Bool ?? false }
    /// The raw (or annotated) screenshot a `see --path` saved.
    var screenshot: String? { (data["screenshot_raw"] as? String).flatMap { $0.isEmpty ? nil : $0 } }
    var annotated: String? { (data["screenshot_annotated"] as? String).flatMap { $0.isEmpty ? nil : $0 } }

    /// The focused element's AX role (AXTextField, AXSecureTextField…).
    var focusedRole: String? { (data["focused_element"] as? [String: Any])?["role"] as? String }

    /// The focused element's frame (`[[x, y], [w, h]]`), when the window has one.
    var focusedFrame: CGRect? {
        guard let focused = data["focused_element"] as? [String: Any], let frame = focused["frame"] as? [[NSNumber]], frame.count == 2,
              frame[0].count == 2, frame[1].count == 2 else { return nil }
        return CGRect(x: frame[0][0].doubleValue, y: frame[0][1].doubleValue, width: frame[1][0].doubleValue, height: frame[1][1].doubleValue)
    }

    /// The `see` listed more elements than Aris keeps: what is missing (a Send control) can't be ruled out.
    var elementsTruncated: Bool { ((data["ui_elements"] as? [Any])?.count ?? 0) > ArisComputerUseLedger.maxElements }

    /// Every element of a `see`, in Peekaboo's order (its menu bar too; the observation drops that).
    var elements: [ArisDesktopElement] {
        guard let list = data["ui_elements"] as? [[String: Any]] else { return [] }
        return list.prefix(ArisComputerUseLedger.maxElements).compactMap(ArisDesktopElement.init(peekaboo:))
    }

    /// Nothing reached the app (refused before dispatch): only then may a call be repeated, and only when Peekaboo
    /// says so too.
    var safeToRepeat: Bool { retrySafe && !dispatched }

    /// Background keys or typing refused before anything was sent: the app's keyboard focus is in another of its windows
    /// (a panel, a popover), which background delivery can't reach (bench te_saveas, the Finder tasks).
    var focusElsewhere: Bool {
        guard !dispatched else { return false }
        let said = (message ?? "") + " " + (refusal ?? "")
        return said.contains("belongs to a different window") || said.contains("does not hold it")
    }

    /// A background point click found nothing pressable there (a custom-drawn view): a real pointer click is the next way.
    var nothingPressable: Bool { !success && (message ?? "").contains("No pressable accessibility element") }
}

/// One element a `see` showed: Peekaboo's id, its role and label (and value), where it is, and whether it acts.
/// A caret (length 0) or selection in a text control.
struct ArisTextRange: Equatable {
    let location: Int
    let length: Int
    var shown: String { length == 0 ? "at \(location)" : "\(location)…\(location + length)" }
}

struct ArisDesktopElement: Equatable {
    /// Peekaboo's id (`elem_27`), or Aris's own for a text mark read from the screen (`ocr` marks, never passed to
    /// Peekaboo).
    let id: String
    let role: String
    let label: String
    var value: String? = nil
    var bounds: CGRect = .zero
    var enabled = true
    var actionable = false
    /// The value exactly as the app holds it: never redacted or cut, never shown to a brain. Only Aris compares with it
    /// and writes it back (the type ladder), and only the user's card shows it. Nil when the app gave none or it is longer
    /// than `maxRaw` (`rawCapped`): then nothing is ever written back from it (security review C2).
    var rawValue: String? = nil
    var rawCapped = false
    /// Peekaboo's `ax_role` (AXTextField, AXSecureTextField…) and `role_description` (I6).
    var axRole: String? = nil
    var roleDescription: String? = nil
    /// Peekaboo's `identifier` (a System Settings pane's extension id on its row) and `is_selected`.
    var identifier: String? = nil
    var selected = false
    /// A text control's caret or selection (Peekaboo's `selected_text_range`, AX's kAXSelectedTextRange), when exposed.
    var selectedRange: ArisTextRange? = nil

    /// The longest raw value kept (set-value's own limit).
    static let maxRaw = 131_072

    init(id: String, role: String, label: String, value: String? = nil, bounds: CGRect = .zero, enabled: Bool = true, actionable: Bool = false,
         rawValue: String? = nil, rawCapped: Bool = false, axRole: String? = nil, roleDescription: String? = nil) {
        self.id = id
        self.role = role
        self.label = label
        self.value = value
        self.bounds = bounds
        self.enabled = enabled
        self.actionable = actionable
        self.rawValue = rawValue ?? (rawCapped ? nil : value)
        self.rawCapped = rawCapped
        self.axRole = axRole
        self.roleDescription = roleDescription
    }

    /// A password field: never typed into, set or read back (I6).
    var isSecure: Bool {
        if axRole == "AXSecureTextField" { return true }
        let said = (roleDescription ?? "").lowercased()
        return ["secure", "password", "보안", "암호"].contains(where: said.contains)
    }

    /// A search field (a chat list's or a window's search): never the field a send carries.
    var isSearch: Bool {
        if role == "searchField" || axRole == "AXSearchField" { return true }
        let said = ArisRiskPolicy.folded(label + " " + (roleDescription ?? ""))
        return ["search", "검색", "찾기", "検索", "搜索"].contains(where: said.contains)
    }

    /// A button with nothing to name it (an icon): next to a chat's message field, the send button (re-review 4).
    var isUnlabelledButton: Bool {
        (role == "button" || axRole == "AXButton") && label.trimmingCharacters(in: .whitespaces).isEmpty && (value ?? "").isEmpty
    }

    /// A field text goes into.
    var isTextEntry: Bool {
        ["textField", "textArea", "comboBox", "searchField"].contains(role) || ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"].contains(axRole ?? "")
    }

    init?(peekaboo object: [String: Any]) {
        guard let id = object["id"] as? String, id.range(of: #"^(elem|menuitem|ocr)_[0-9]{1,6}$"#, options: .regularExpression) != nil else { return nil }
        let bounds = object["bounds"] as? [String: Any] ?? [:]
        let number = { (key: String) in (bounds[key] as? NSNumber)?.doubleValue ?? 0 }
        let label = (object["label"] as? String) ?? (object["title"] as? String) ?? (object["description"] as? String) ?? ""
        let value: String?
        switch object["value"] {
        case let text as String: value = text
        case let number as NSNumber: value = number.stringValue
        default: value = nil
        }
        let capped = (value?.utf8.count ?? 0) > Self.maxRaw
        self.init(id: id, role: object["role"] as? String ?? "", label: label, value: value,
                  bounds: CGRect(x: number("x"), y: number("y"), width: number("width"), height: number("height")),
                  enabled: object["is_enabled"] as? Bool ?? true, actionable: object["is_actionable"] as? Bool ?? false,
                  rawValue: capped ? nil : value, rawCapped: capped, axRole: object["ax_role"] as? String,
                  roleDescription: object["role_description"] as? String)
        identifier = object["identifier"] as? String
        selected = object["is_selected"] as? Bool ?? false
        if let range = object["selected_text_range"] as? [String: Any], let location = (range["location"] as? NSNumber)?.intValue,
           let length = (range["length"] as? NSNumber)?.intValue, location >= 0, length >= 0 {
            selectedRange = ArisTextRange(location: location, length: length)
        }
    }

    /// `elem_27` → 27 (the number in Aris's ref `@s…:e27`).
    var number: Int? { id.split(separator: "_").last.flatMap { Int($0) } }
    var isMenuBar: Bool { id.hasPrefix("menuitem_") }
    var centre: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }

    /// The same control in another snapshot: its role and label (never its value, which an action changes).
    func sameControl(_ other: ArisDesktopElement) -> Bool { role == other.role && label == other.label }
}
