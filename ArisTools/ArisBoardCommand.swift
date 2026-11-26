//
//  ArisBoardCommand.swift
//  aris-tools
//
//  `board "<markdown>" [--screen here|left|right|main]` puts a table, notes or a plan on the Aris board, a
//  window the notch app shows on that screen without taking the keyboard or mouse; `board --close` takes it
//  down. The text goes through aris/board.json (the sandboxed app can read there), then a nudge to the app, which
//  answers once it took it: only then is it told as shown (ArisAppAck).
//

import Foundation

private let boardFile = arisFolder.appendingPathComponent("board.json")
private let boardLimit = 20_000

func board(_ args: [String]) {
    var words = args
    let close = words.contains("--close")
    words.removeAll { $0 == "--close" }
    let screen = option("--screen", in: &words) ?? "here"
    let markdown = words.joined(separator: " ").replacingOccurrences(of: "\\n", with: "\n")
    guard close || !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        fail("usage: board \"<markdown>\" [--screen here|left|right|main] | board --close")
    }
    let entry: [String: Any] = close ? ["close": true] : ["markdown": String(markdown.prefix(boardLimit)), "screen": screen]
    let taken: Bool
    do { taken = try ArisAppAck.handOver(entry, to: boardFile, nudge: "com.lumenjsn.aris.board") } catch {
        fail("couldn't write the board: \(error.localizedDescription)")
    }
    // Only once the app answered that it took it (ArisAppAck).
    guard taken else { fail(ArisAppAck.notTakenLine(close ? "the board's closing" : "the board")) }
    print(close ? "board closed" : "on the board (\(screen) screen)")
}
