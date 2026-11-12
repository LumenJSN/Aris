//
//  ArisDropKind.swift
//  Aris
//
//  What a file dropped on Aris is, by its extension: the kinds Aris can really do something with today. A PDF, a
//  document or a plain text file is read by the app itself and sent with the request (ArisAttachmentText), so every
//  brain can summarize or translate it. A picture, a video or a sound is converted by aris-tools (ArisConvert). The
//  lists here are the ones those two read, and the tests hold them to each other. Foundation only, so it is tested.
//

import Foundation

enum ArisDropKind: Equatable {
    case pdf
    /// Writing people read: Word, RTF, a web page, plain text, Markdown.
    case document
    /// Data and code the app reads as plain text: a CSV, JSON, a script.
    case text
    case image, video, audio
    case folder
    /// Anything Aris has no chip for (a spreadsheet, a zip, a kind of video it can't convert).
    case other

    static let documentTypes: Set<String> = ["rtf", "rtfd", "doc", "docx", "odt", "html", "htm", "webarchive", "txt", "md", "markdown", "tex"]
    static let textTypes: Set<String> = ["csv", "tsv", "json", "xml", "yaml", "yml", "log", "ini", "toml", "swift", "py", "js", "ts", "java",
                                         "c", "h", "cpp", "m", "rb", "go", "rs", "sh"]
    static let imageTypes: Set<String> = ["heic", "heif", "jpg", "jpeg", "png", "tiff", "tif", "gif", "bmp", "webp"]
    static let videoTypes: Set<String> = ["mov", "mp4", "m4v"]
    static let audioTypes: Set<String> = ["m4a", "mp3", "wav", "aiff", "aif", "caf", "aac"]
    /// Documents macOS keeps as a folder: they are read like a file.
    private static let packages: Set<String> = ["rtfd"]

    static func of(_ path: String, isFolder: Bool = false) -> ArisDropKind {
        let type = (path as NSString).pathExtension.lowercased()
        if isFolder, !packages.contains(type) { return .folder }
        if type == "pdf" { return .pdf }
        if documentTypes.contains(type) { return .document }
        if textTypes.contains(type) { return .text }
        if imageTypes.contains(type) { return .image }
        if videoTypes.contains(type) { return .video }
        return audioTypes.contains(type) ? .audio : .other
    }

    /// The format a file already is, in aris-tools' spelling (jpeg is jpg, tif is tiff, heif is heic, m4v is mp4).
    static func format(_ path: String) -> String {
        let type = (path as NSString).pathExtension.lowercased()
        return ["jpeg": "jpg", "tif": "tiff", "heif": "heic", "m4v": "mp4"][type] ?? type
    }

    /// The app reads this kind's text up front.
    var isRead: Bool { self == .pdf || self == .document || self == .text }
}
