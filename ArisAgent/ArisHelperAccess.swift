//
//  ArisHelperAccess.swift
//  aris-agent
//
//  Whether aris-agent has its own switch in System Settings › Accessibility, for the app's question
//  (/permissions accessibilityAccess: the setup's card, the helper panel, the settings row, the fix button). macOS is
//  asked at each call and nothing is kept here: unlike Screen Recording's answer, which a running process is told
//  once (ArisScreenAccess asks through a new process for that reason), this one follows the switch while the process
//  runs. It never asks macOS to show anything (no AXIsProcessTrustedWithOptions prompt).
//

import ApplicationServices

enum ArisHelperAccess {
    static var accessibility: Bool { AXIsProcessTrusted() }
}
