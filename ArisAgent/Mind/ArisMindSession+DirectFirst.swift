//
//  ArisMindSession+DirectFirst.swift
//  aris-agent
//
//  The Mind's rule for opening things (tenth VM run, item 2: "다운로드 폴더 열어 줘" took 31 s, an invented
//  /Users/me/Downloads, five key presses in Finder and two click cards, with the Go-to-Folder sheet left open). One
//  direct call opens a folder, a file, an app or a link, or shows a file in Finder; an app is driven by keys, typing or
//  clicks only when no direct capability does the thing. The home folder is never the model's to guess. Pinned by
//  mind10b-tests (the key sentences), and nothing here is for speaking aloud.
//

import Foundation

extension ArisMindSession {
    static let directFirstRule = """
    Use a direct capability first. To open a folder, a file, an app or a link, or to show a file in Finder, make one \
    app_open call: a folder everyone knows by its name goes in place (다운로드 is downloads, 문서 documents, 바탕화면 \
    desktop, 홈 home, 응용 프로그램 applications), any other folder or file in path written from ~ or /. Drive an app \
    by pressing keys, typing or clicking only when no direct capability does it. Never invent a path under /Users: you \
    do not know the owner's user name, so write ~ and Aris fills in the real home folder. When a direct call fails, say \
    so; do not fall back to keys in Finder.
    """
}
