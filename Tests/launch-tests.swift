// Acceptance tests for the clean-room app entry (cleanroom-specs/01-app-lifecycle.md), pure parts.
func runLaunchTests() {
    typealias L = ArisLaunchRules
    check(L.migratedDisplayMode(showOnAllDisplays: true, followActiveDisplay: true, automaticallySwitchDisplay: true) == .allDisplays
          && L.migratedDisplayMode(showOnAllDisplays: false, followActiveDisplay: true, automaticallySwitchDisplay: true) == .activeDisplay
          && L.migratedDisplayMode(showOnAllDisplays: false, followActiveDisplay: false, automaticallySwitchDisplay: true) == .fallbackIfPreferredUnavailable
          && L.migratedDisplayMode(showOnAllDisplays: false, followActiveDisplay: false, automaticallySwitchDisplay: false) == .preferredDisplay,
          "launch: the legacy display switches map to the four modes")
    check(L.crossesWindowSets(from: .allDisplays, to: .activeDisplay) && L.crossesWindowSets(from: .preferredDisplay, to: .allDisplays)
          && !L.crossesWindowSets(from: .preferredDisplay, to: .activeDisplay) && !L.crossesWindowSets(from: nil, to: .allDisplays),
          "launch: only a change across all displays / single display tears the other windows down")
    check(L.toggleAutoClose == .seconds(3) && L.peekShortcutDuration == 3, "launch: the toggle closes after 3 s, the peek shortcut shows 3 s")
}
