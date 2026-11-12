//
//  ArisPillLook.swift
//  Aris
//
//  The pill's glass as numbers. ArisPillGlass draws these for the jobs' pill under the notch and for a teammate's
//  bubble, and tests/vside-tests.swift pins every one. Foundation only.
//
//  The pill sits under the notch, where the star drops into it. It comes and goes down from the notch on the notch's
//  clock, with the star's hop timed to it, and it says one status line.
//

import Foundation

enum ArisPillLook {
    /// A vertical gradient (180deg) from rgba(22,22,27,.96) to rgba(12,12,15,.96). The alpha is
    /// ArisGlassRecipe.pillFill (solid with Reduce Transparency).
    static let fillTop = (red: 22.0 / 255, green: 22.0 / 255, blue: 27.0 / 255)
    static let fillBottom = (red: 12.0 / 255, green: 12.0 / 255, blue: 15.0 / 255)
    /// A radius of 24 in every state (a 30-point pill is a capsule either way).
    static let radius = 24.0
    /// A 14-point backdrop blur. Drawn with AppKit's behind-window material, whose radius is its own:
    /// under a .96 fill the two cannot be told apart.
    static let backdropBlur = 14.0
    /// The pill has no shadow.
    static let shadowOpacity = 0.0

    /// A 1-point ring: over white .07, a highlight at the top left
    /// corner and another at the bottom right, each white .28 at the corner, .08 at 30 % and gone at 60 % of an
    /// ellipse that reaches the far corner.
    static let ringWidth = 1.0
    static let ringBase = 0.07
    static let ringStops: [(location: Double, alpha: Double)] = [(0, 0.28), (0.3, 0.08), (0.6, 0)]
    /// Each highlight's ellipse ends at the farthest corner: √2 of the box each way.
    static let ringReach = 2.0.squareRoot()
}
