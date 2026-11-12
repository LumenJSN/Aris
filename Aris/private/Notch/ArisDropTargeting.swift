//
//  ArisDropTargeting.swift
//  Aris
//
//  Which of a notch's drop targets a drag is over, per display: the target behind the closed notch, the open
//  notch's layout, the user's drop zones (and which half of the home page), and whether a drop just happened (the
//  close logic consumes it).
//

import Observation

@Observable
final class DropInteractionState {
    /// The transparent target behind the closed notch.
    var dragDetectorTargeting = false
    /// The open notch's layout as a whole.
    var generalDropTargeting = false
    /// One of the drop zones on the open pages.
    var dropZoneTargeting = false
    /// Set by a successful drop; read once by the close logic.
    var dropEvent = false
    /// The half of the open home page under the drag: the shelf or Aris (the user's ArisDropZones).
    var homeDropSide: ArisDropZones.Side?
    /// Files were just given to Aris: the open notch stays, on the composer, until the pointer has come and gone or
    /// the files are used (ArisNotchDecisions.dropHold).
    var arisDropHold = false
    /// A content drag is just under the closed notch: its drag strip can be hit (ArisNotchDecisions.dragHoverDepth).
    var dragNear = false

    var anyDropZoneTargeting: Bool { dragDetectorTargeting || generalDropTargeting || dropZoneTargeting }

    init() {}
}
