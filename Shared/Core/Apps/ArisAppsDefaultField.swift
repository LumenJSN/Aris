//
//  ArisAppsDefaultField.swift
//  Shared/Core/Apps
//
//  The text field app.type means when the call names none (tenth VM run, item 4: the model's "TextEdit 내용 전부 …로
//  바꿔 줘" came as app.type with replace and no target, so nothing was read before it, the card said "지워질 글을 미리
//  읽지 못했어요", no copy was kept and the typing had no undo; a taught replay names its field and had all three).
//  Only when it is plain which one: the text element that has the keyboard focus, else the window's one text area (a
//  document), else its one text field. Never a password field; with two candidates and no focus, none. Pure.
//

import Foundation

extension ArisApps.Read {
    static func defaultTextField(in elements: [ArisApps.ReadElement], focusedFrame: (Double, Double)? = nil) -> ArisApps.ReadElement? {
        let fields = elements.filter { $0.isText && $0.role != "secureTextField" && $0.enabled }
        if let focusedFrame {
            let focused = fields.filter { $0.frame.map { abs($0.x - focusedFrame.0) < 1 && abs($0.y - focusedFrame.1) < 1 } ?? false }
            if focused.count == 1 { return focused[0] }
        }
        let areas = fields.filter { $0.role == "textArea" }
        if areas.count == 1 { return areas[0] }
        return areas.isEmpty && fields.count == 1 ? fields[0] : nil
    }

    /// The focused element's origin in an engine look's reply.
    static func focusedFrame(_ data: ArisApps.JSON) -> (Double, Double)? {
        data["focused_element"]?["frame"]?.array?.first?.array.flatMap { pair -> (Double, Double)? in
            guard pair.count == 2, let x = pair[0].number, let y = pair[1].number else { return nil }
            return (x, y)
        }
    }
}
