// The tests' stand-in for ArisAgent/ArisQuietTuck.swift, which speaks to other apps' windows through Accessibility
// (never in a test). Its decisions are ArisQuietLaunch's and are tested there; its text is read by the wiring tests.
import Foundation

enum ArisQuietTuck {
    static func putAway(pid: Int32, window: Int, title: String) -> (place: ArisQuietLaunch.Place, own: Bool) { (.behind, false) }
    static func close(pid: Int32, window: Int, title: String?) -> Bool { false }
}
