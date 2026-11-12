// Acceptance tests for the clean-room drop state and drag detector (cleanroom-specs/06-drop-handling.md).
import AppKit

func runDropTests() {
    let region = CGRect(x: 436, y: 792, width: 640, height: 190)
    var watch = ArisDragWatch(region: region)
    let outside = CGPoint(x: 700, y: 400), inside = CGPoint(x: 700, y: 900)
    check(watch.dragged(to: inside, changeCount: 5, qualifies: { true }).isEmpty, "drag watch: nothing before the mouse goes down")
    watch.mouseDown(changeCount: 5)
    check(watch.dragged(to: inside, changeCount: 5, qualifies: { true }).isEmpty, "drag watch: an unchanged pasteboard (a window drag) is ignored")
    check(watch.dragged(to: inside, changeCount: 6, qualifies: { false }).isEmpty, "drag watch: items without file, URL or text don't count")
    check(watch.dragged(to: outside, changeCount: 6, qualifies: { true }) == [.moved(outside)], "drag watch: a content drag reports moves")
    check(watch.dragged(to: inside, changeCount: 6, qualifies: { true }) == [.moved(inside), .entered], "drag watch: entering fires once")
    check(watch.dragged(to: inside, changeCount: 6, qualifies: { true }) == [.moved(inside)], "drag watch: staying inside doesn't fire again")
    check(watch.dragged(to: outside, changeCount: 6, qualifies: { true }) == [.moved(outside), .exited]
          && watch.dragged(to: inside, changeCount: 6, qualifies: { true }) == [.moved(inside), .entered], "drag watch: exit, then re-entry fires again")
    watch.mouseUp()
    check(watch.dragged(to: inside, changeCount: 7, qualifies: { true }).isEmpty, "drag watch: mouse-up resets")
    let detector = DragDetector(notchRegion: region)
    detector.stopMonitoring()
    detector.stopMonitoring()
    check(true, "drag detector: stopping twice is harmless")

    let drop = DropInteractionState()
    check(!drop.anyDropZoneTargeting && drop.homeDropSide == nil && !drop.dropEvent, "drop state: starts idle")
    drop.generalDropTargeting = true
    check(drop.anyDropZoneTargeting, "drop state: any of the three targets makes it active")
    drop.generalDropTargeting = false
    drop.dragDetectorTargeting = true
    check(drop.anyDropZoneTargeting, "drop state: the behind-notch target too")
}

/// Stand-in for the user's ArisDropZones (a view in ArisShelfChips.swift, not compiled into the harness).
enum ArisDropZones { enum Side { case shelf, aris } }
