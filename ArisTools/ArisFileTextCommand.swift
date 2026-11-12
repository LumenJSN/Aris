//
//  ArisFileTextCommand.swift
//  aris-tools
//
//  `files read …` (ArisFileText has the rules): reads the text of the files named, on the shelf or selected in Finder,
//  through PDFKit, AppKit's documents or as plain text, and prints it capped, marked as other people's words.
//

import AppKit
import Foundation
import PDFKit

/// A file's text by its kind; nil when it has none that can be read.
private func textOfFile(_ path: String, kind: ArisFileText.Kind) -> String? {
    let url = URL(fileURLWithPath: path)
    let text: String?
    switch kind {
    case .pdf:
        text = PDFDocument(url: url).map { pdf in
            var read = ""
            for index in 0..<min(pdf.pageCount, ArisFileText.pdfPages) where read.count < ArisFileText.perFile {
                read += (pdf.page(at: index)?.string ?? "") + "\n"
            }
            return read
        }
    case .rich: text = (try? NSAttributedString(url: url, options: [:], documentAttributes: nil))?.string
    case .plain: text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .utf16))
    }
    let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
}

func fileTextRead(_ words: [String]) {
    guard let source = ArisFileText.parse(words) else { fail(ArisFileText.usage) }
    let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path
    let environment = ProcessInfo.processInfo.environment
    let paths: [String]
    // A file Aris picked is named only by its own name in the answer; a path the brain gave is its own.
    switch source {
    case .path(let path): paths = [absolutePath(path)]
    case .shelf(let named):
        if let refusal = ArisConvert.selectorRefusal(.shelf, environment: environment, state: ArisShelfFiles.state(home: NSHomeDirectory()),
                                                     turnStarted: turnStarted(environment)) { fail(refusal) }
        let shelf = selectedFiles(.shelf)
        guard !shelf.isEmpty else { fail("The shelf is empty: ask the user which file (or for its path).") }
        paths = ArisFileText.pick(shelf, words: named)
        guard !paths.isEmpty else {
            fail("No file on the shelf has that name. On the shelf: " + shelf.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "))
        }
    case .finder:
        if let refusal = ArisConvert.selectorRefusal(.finder, environment: environment, state: ArisShelfFiles.state(home: NSHomeDirectory()),
                                                     turnStarted: turnStarted(environment)) { fail(refusal) }
        paths = selectedFiles(.finder)
        guard !paths.isEmpty else { fail("Nothing is selected in Finder: ask the user which file (or for its path).") }
    }
    guard paths.count <= ArisFileText.mostFiles else {
        fail("That is \(paths.count) files; at most \(ArisFileText.mostFiles) are read at once. Ask which ones, or name them by their words.")
    }
    let read = paths.map { given -> (name: String, text: String?, why: String?) in
        // Checked after links are followed, so a link can't point the check at one file and the read at another.
        let path = URL(fileURLWithPath: given).resolvingSymlinksInPath().path
        let name = (given as NSString).lastPathComponent
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) else { return (name, nil, "there is no file at that path") }
        let size = ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.intValue
        if let refusal = ArisFileText.refusal(path, home: home, isFolder: isFolder.boolValue, size: size) { return (name, nil, refusal) }
        guard let kind = ArisFileText.kind(path), let text = textOfFile(path, kind: kind) else { return (name, nil, "it has no text Aris can read") }
        return (name, text, nil)
    }
    // Nothing could be read: said as a failure, with why, so it is never passed on as the file's content.
    guard read.contains(where: { $0.text != nil }) else {
        fail(read.map { "\($0.name): \($0.why ?? "no text in it")" }.joined(separator: "\n"))
    }
    print(ArisFileText.answer(read))
}
