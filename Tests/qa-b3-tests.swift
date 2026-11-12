// QA batch 3 (QA session's branch): the calendar strip (BUG-57).
import Foundation

func runQAB3Tests() {
    stripLayoutTests()
}

private func stripLayoutTests() {
    // The strip as the VM showed it: 198 wide, 30-point days, today (index 7 of 22) chosen.
    let width: CGFloat = 198, cell: CGFloat = 30
    let todayX = ArisStripLayout.offset(width: width, index: 7, cell: cell) + 7 * cell
    check(todayX + cell / 2 == width / 2, "strip layout: the chosen day sits in the middle (BUG-57: it opened at the left edge)")
    let elevenX = ArisStripLayout.offset(width: width, index: 9, cell: cell) + 9 * cell
    check(elevenX + cell / 2 == width / 2, "strip layout: picking another day brings that day to the middle")
    check(ArisStripLayout.offset(width: width, index: 0, cell: cell) > 0,
          "strip layout: the first day centred leaves room on its left, as the old margins did")

    // The wheel: one notch steps a day; down (negative dy on macOS is content up) follows the old sign: >0 is earlier.
    var (pending, step) = ArisStripLayout.scrolled(pending: 0, dx: 0, dy: 3, precise: false)
    check(step == -1 && pending == 0, "strip layout: a wheel notch up steps a day earlier")
    (pending, step) = ArisStripLayout.scrolled(pending: 0, dx: 0, dy: -3, precise: false)
    check(step == 1, "strip layout: a wheel notch down steps a day later")

    // A trackpad: small deltas add up before a step, and a sideways swipe counts too.
    (pending, step) = ArisStripLayout.scrolled(pending: 0, dx: -6, dy: 1, precise: true)
    check(step == nil && pending == -6, "strip layout: a small swipe waits for more")
    (pending, step) = ArisStripLayout.scrolled(pending: pending, dx: -14, dy: 0, precise: true)
    check(step == 1 && pending == 0, "strip layout: a sideways swipe to the left steps a day later")
    (_, step) = ArisStripLayout.scrolled(pending: 0, dx: 25, dy: 2, precise: true)
    check(step == -1, "strip layout: the larger axis decides (a swipe right goes earlier)")

    // Steps stay on the strip.
    check(ArisStripLayout.stepped(0, by: -1, count: 22) == 0, "strip layout: no step before the first day")
    check(ArisStripLayout.stepped(21, by: 1, count: 22) == 21, "strip layout: no step past the last day")
    check(ArisStripLayout.stepped(7, by: 1, count: 22) == 8, "strip layout: a step moves one day")
}
