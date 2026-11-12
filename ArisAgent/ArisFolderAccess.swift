//
//  ArisFolderAccess.swift
//  aris-agent
//
//  The folders macOS guards for each app on its own (Desktop, Documents, Downloads). aris-agent and the aris-tools it
//  runs touch them for the user (moving, converting, putting back); the first time, macOS asks "'aris-agent'이(가) 데스크탑
//  폴더의 파일에 접근하려고 합니다" and the action waits on that prompt (QA BUG-17). This names the folder a path or an
//  undo is in, and lets 설정 › 컴퓨터 제어 ask up front (aris-agent reads the folder's list once). Pure apart from touch.
//

import Foundation

enum ArisFolderAccess {
    static let folders = ["Desktop", "Documents", "Downloads"]

    /// Which of the three folders `path` is in (or is), under `home`; nil for anywhere else.
    static func folder(of path: String, home: String) -> String? {
        let standard = (path as NSString).standardizingPath
        return folders.first { standard == home + "/" + $0 || standard.hasPrefix(home + "/" + $0 + "/") }
    }

    /// The folder an activity log entry's undo (its JSON) touches: the first of its paths that is in one.
    static func folder(ofUndo undo: [String: Any]?, home: String) -> String? {
        guard let undo else { return nil }
        func paths(_ value: Any) -> [String] {
            switch value {
            case let text as String: return [text]
            case let list as [Any]: return list.flatMap(paths)
            case let object as [String: Any]: return object.keys.sorted().flatMap { paths(object[$0] as Any) }
            default: return []
            }
        }
        return paths(undo).lazy.compactMap { folder(of: $0, home: home) }.first
    }

    /// One of the three folders by name, under `home`; nil for any other name.
    static func url(named name: String, home: String) -> URL? {
        folders.contains(name) ? URL(fileURLWithPath: home).appendingPathComponent(name, isDirectory: true) : nil
    }

    /// Reads the folder's list once, as aris-agent (macOS asks the user the first time; this waits for their answer). Whether
    /// it could. Only for 설정's 허용하기, never in the tests.
    static func touch(_ folder: URL) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) != nil
    }
}
