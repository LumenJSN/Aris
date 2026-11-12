//
//  ArisLog.swift
//  Aris
//
//  Shared log categories under Aris's subsystem, for the notch, music and shelf code.
//

import os

enum Log {
    static let subsystem = "com.lumenjsn.aris"

    static let general = Logger(subsystem: subsystem, category: "general")
    static let app = Logger(subsystem: subsystem, category: "app")
    static let music = Logger(subsystem: subsystem, category: "music")
    static let xpc = Logger(subsystem: subsystem, category: "xpc")
    static let shelf = Logger(subsystem: subsystem, category: "shelf")
    static let calendar = Logger(subsystem: subsystem, category: "calendar")
    static let window = Logger(subsystem: subsystem, category: "window")
}
