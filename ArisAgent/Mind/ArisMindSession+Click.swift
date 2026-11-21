//
//  ArisMindSession+Click.swift
//  aris-agent
//
//  The Mind's rule for pressing something in an app (tenth VM run, item 8: three reads of a page, then a click on
//  ‘the “역사” link in the 목차 (table of contents) sidebar’, a card, nothing found, a second card for Cmd+F). The
//  rule is enforced where the call is decided (ArisMindClickReads); this is the sentence that keeps the model from
//  running into it. Its key sentences are pinned by mind10c-tests.
//

import Foundation

extension ArisMindSession {
    static let clickRule = """
    To press something in an app (a button, a link, a row, a tab), read the app first in this turn (app_read; \
    part="controls" lists what can be pressed, and find="word" narrows a long page to the lines holding that word), \
    then make one app_click naming the element by its id or its exact name from that read. Never describe an element \
    ("the History link in the sidebar"): a target that wasn't just read is refused. When what you look for isn't in \
    the read, read again with another find or the next offset, or say it isn't there; don't press keys to search for it.
    """
}
