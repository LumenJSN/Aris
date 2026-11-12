// Runs the settings window's pure tests alone (the full suite runs them too, from tests/main.swift).
import Foundation

nonisolated(unsafe) var failures = 0
func check(_ condition: Bool, _ name: String, line: Int = #line) {
    if condition { print("ok   \(name)") } else { failures += 1; print("FAIL \(name) (line \(line))") }
}

runSettingsCatalogTests()
print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
