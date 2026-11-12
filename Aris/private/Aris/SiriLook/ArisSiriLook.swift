//
//  ArisSiriLook.swift
//  Aris
//
//  The hidden "siri" look: Siri's surface, controls, type and motion, measured from the owner's own captures of
//  Siri on macOS 27.2 (four Retina screenshots and an 80 s screen recording, 2026-11-11), applied inside Aris's own
//  notch. Aris keeps its place and its outline (it hangs from the camera housing; Siri's panel floats); what changes
//  is what the outline is filled with and what stands in it.
//
//  Everything here is a number with where it was read. "shot": measured in a screenshot (2 px = 1 pt). "film":
//  measured frame by frame in the recording, resampled to 60 frames a second. "solved": the same glass read over a
//  white window and over black gives its tint and how much of it there is (out = behind × (1 − a) + tint × a, twice).
//  "fit": a spring fitted to the sizes measured per frame. "Aris": a value of Aris's own, said so.
//
//  Nothing of Apple's is used: no asset, font file, shader or private class. The drawing is Aris's own SwiftUI
//  (ArisSiriLookSurface, ArisSiriLookControls); this file is Foundation only and tested (tests/siri-look-tests.swift).
//

import Foundation

/// Which look Aris is drawn in. `defaults write com.lumenjsn.aris arisVoiceLook siri` switches it.
enum ArisVoiceLook: String, Equatable {
    /// Today's: the dark glass, pills and tags.
    case aris
    /// Siri's measured look over Aris's clear glass.
    case siri
    /// The same over the system's frosted glass (Siri's is frosted; the public frosted glass is darker over a white
    /// window than Siri's, so it is a second value to compare on a real screen, not the default).
    case siriFrost = "siri-frost"
    /// The surface alone (Settings' theme 밝은 아래, ArisNotchTheme): the same fill, rim, shadow and text scrim over
    /// the clear glass, with everything else Aris's own: its controls, layout, type and motion.
    case surfaceLight = "surface-light"

    static let key = "arisVoiceLook"

    /// Anything that isn't a known look is today's.
    static func resolve(_ raw: String?) -> ArisVoiceLook {
        guard let raw else { return .aris }
        return ArisVoiceLook(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? .aris
    }

    /// The whole look: its controls, layout, type and motion as well as its surface.
    var isSiri: Bool { self == .siri || self == .siriFrost }

    /// Its surface is drawn (the whole look, or the surface alone).
    var drawsSurface: Bool { self != .aris }
}

/// Reads the look when a state begins, not on every frame: the preference is looked at again only when the state
/// it is asked about differs from the last one, so the notch never changes look halfway through a state.
final class ArisVoiceLookLatch {
    private let read: () -> String?
    private var lastState: String?
    private(set) var look = ArisVoiceLook.aris

    init(read: @escaping () -> String? = { UserDefaults.standard.string(forKey: ArisVoiceLook.key) }) {
        self.read = read
    }

    func look(entering state: String) -> ArisVoiceLook {
        if state != lastState {
            lastState = state
            look = ArisVoiceLook.resolve(read())
        }
        return look
    }
}

/// The look in force. Set on the main thread by the notch when it opens, closes or a voice state begins
/// (ArisSiriLookGate); every view reads it when it is built.
enum ArisSiriLookNow {
    static var look = ArisVoiceLook.aris
    static var on: Bool { look.isSiri }
    /// The look's surface (fill, rim, shadow, the scrim behind the text) is drawn: the whole look or its surface alone.
    static var surfaceOn: Bool { look.drawsSurface }
}

/// The moments the preference is read at: the notch opening or closing, and each voice state beginning.
enum ArisSiriLookMoment {
    static func name(open: Bool, state: String) -> String { (open ? "open " : "closed ") + state }
}

enum ArisSiriLook {
    // MARK: The panel's surface

    /// One stop of the surface's fill: how far down, how much of the fill there is, and its grey (0 black, 1 white).
    struct Stop: Equatable {
        let location: Double
        let coverage: Double
        let grey: Double
    }

    enum Surface {
        /// The fill at the very top: over white it reads 8 of 255, over black 3 (shot 4 and 3) → solved.
        static let topCoverage = 0.98
        static let topGrey = 0.0
        /// Half-way down a 600-point panel: 83 over white, 11.6 over a black window (film, 44.6–48.4 s) → solved.
        static let midCoverage = 0.72
        static let midGrey = 16.0 / 255
        /// 11 points above the bottom edge: 182 over white, 28 over black (film) → solved. The fill thins evenly
        /// with the height whatever the height (film: 172, 276 and 600 points tall all end the same).
        static let bottomCoverage = 0.40
        static let bottomGrey = 70.0 / 255
        /// Siri's panel: 420 wide, continuous corners of 38 (shot 4: the diagonal is 11.2 in). Aris keeps its own
        /// outline, so these two are here for the record only.
        static let width = 420.0
        static let cornerRadius = 38.0
        /// The blur behind it: a sharp wallpaper edge is spread over about 33 points (10 % to 90 %, shot 2), a
        /// Gaussian of about 13 to 15. Estimated. Aris's clear glass does not blur; `siri-frost` does.
        static let blurSigma = 14.0
        /// The rim: half a point. Over white the bottom edge is a full white line and the sides a line darker than
        /// the fill; over the wallpaper the bottom shows none and the top a faint one (shot 3 and 4). Drawn as
        /// white, strongest at the bottom.
        static let rimWidth = 0.5
        static let rimTop = 0.20
        static let rimSide = 0.06
        static let rimBottom = 0.38
        /// The shadow (shot 4, over white): 20 % darker at the side edges, 32.5 % under the bottom, 7 % above the
        /// top, gone 47 points out → black .40, a Gaussian of 18.5, 16 down. Fit.
        static let shadowAlpha = 0.40
        static let shadowSigma = 18.5
        static let shadowY = 16.0

        /// The fill of a notch `height` tall whose top `band` points are the camera housing's band. Aris's own:
        /// the band is full black so the notch still disappears into the hardware; under it the fill is Siri's,
        /// thinning evenly to the bottom. Always four stops, so closed, open and every height between slide into
        /// each other. Closed, or without glass (Reduce Transparency): solid black.
        static func stops(height: Double, band: Double, open: Bool, glass: Bool, base: Double = 0) -> [Stop] {
            let solid = Stop(location: 1, coverage: 1, grey: 0)
            guard open, glass, height > 0 else {
                return [Stop(location: 0, coverage: 1, grey: 0), solid, solid, solid]
            }
            let start = min(0.9, max(0, band / height))
            let middle = start + (1 - start) / 2
            return [
                Stop(location: 0, coverage: 1, grey: 0),
                over(base, Stop(location: start, coverage: band > 0 ? 1 : topCoverage, grey: topGrey)),
                over(base, Stop(location: middle, coverage: midCoverage, grey: midGrey)),
                over(base, Stop(location: 1, coverage: bottomCoverage, grey: bottomGrey)),
            ]
        }

        /// What the glass under the fill already takes of what is behind it. Aris's clear glass with its tint lets
        /// .80 of a pure white window through: measured again after the glass merge, in a
        /// VM on macOS 26.6.2 over a white TextEdit window with the scrim off (98, 138 and 173 at 56 %, 75 % and
        /// 90 % of a 532-point notch give .79 to .82; the glass branch read the same .80). An earlier .27 was read
        /// over a Finder list, which is not white. The system's frosted glass lets about .40 through. The fill is
        /// thinned by that much so the two together read as Siri's.
        static let clearBase = 0.20
        static let frostBase = 0.60

        /// `stop` as it must be drawn over a glass that already takes `base`: together they cover what `stop`
        /// says, and the fill's light (its grey times how much of it there is) stays the same. Where the glass
        /// alone already takes more than Siri's fill does, nothing is drawn: the look is then darker than Siri's.
        static func over(_ base: Double, _ stop: Stop) -> Stop {
            guard base > 0, base < 1 else { return stop }
            let coverage = min(1, max(0, 1 - (1 - stop.coverage) / (1 - base)))
            let grey = coverage > 0 ? min(1, stop.grey * stop.coverage / coverage) : 0
            return Stop(location: stop.location, coverage: coverage, grey: grey)
        }

        /// The fill `y` points down: the stops above, read as the gradient draws them.
        static func fill(at y: Double, height: Double, band: Double, open: Bool = true, glass: Bool = true, base: Double = 0) -> (coverage: Double, grey: Double) {
            let all = stops(height: height, band: band, open: open, glass: glass, base: base)
            let t = height > 0 ? min(1, max(0, y / height)) : 0
            guard let next = all.firstIndex(where: { $0.location >= t }), next > 0 else { return (all[0].coverage, all[0].grey) }
            let from = all[next - 1], to = all[next]
            guard to.location > from.location else { return (to.coverage, to.grey) }
            let k = (t - from.location) / (to.location - from.location)
            return (from.coverage + (to.coverage - from.coverage) * k, from.grey + (to.grey - from.grey) * k)
        }

        /// What a point `y` down reads (0…255) over a backdrop of `behind` (0…255): for the tests and the renders.
        static func reads(at y: Double, height: Double, band: Double, behind: Double, base: Double = 0) -> Double {
            let f = fill(at: y, height: height, band: band, base: base)
            return behind * (1 - base) * (1 - f.coverage) + 255 * f.grey * f.coverage
        }
    }

    // MARK: The round glass controls and the field

    enum Control {
        /// The ✕, expand, + and microphone circles and the field's pill are one glass: over the black top it reads
        /// 34, over the light bottom of the panel on a white window 148 where the panel beside it reads 169 (shot 3,
        /// film) → solved: a grey of .40 at .31. Lighter than black, darker than light.
        static let grey = 0.40
        static let alpha = 0.31
        /// Its rim, half a point twice: the top and bottom edges are lit (91 then 69 over a fill of 35: white .25,
        /// then .15), the left and right edges are a line darker than the fill (shot 3).
        static let rimLit = 0.25
        static let rimDark = 0.28
        /// Siri's circles are 36 across, 16 from the panel's edges, 12 from the field (shot 3).
        static let size = 36.0
        static let inset = 16.0
        static let gap = 12.0
        /// The glyphs: the ✕ is 11 across, the + 11.5, the arrows 13, the microphone 10.5 × 15 (shot 3), white .91.
        static let glyph = 11.0
        static let glyphInk = 0.91
        /// Aris's own: its top band sits beside the camera housing, so the band's circles are sized from the band
        /// (28 in a 37-point band, 33 in a 44-point one), never past Siri's 36.
        static func bandSize(band: Double) -> Double { min(size, max(20, (band * 28 / 37).rounded())) }
    }

    enum Field {
        /// The pill: 36 tall, 292 wide in the 420 panel, a capsule (shot 3). Its words are 15-point regular (the
        /// hint's width matches the system font at 15 exactly), 16 in; the hint reads white at about .45.
        static let height = 36.0
        static let fontSize = 15.0
        static let textInset = 16.0
        static let hintInk = 0.45
        /// Aris's own: its hint is a sentence to be read (the talk keys), so it is drawn at .78, which keeps 4.5:1
        /// on the control glass over a white window; Siri's own .45 does not.
        static let arisHintInk = 0.78
        /// The border that looks blue in the screenshots is the glass rim taking the wallpaper's colour: over the
        /// blue it reads (108, 172, 250) on a fill of (57, 98, 147), over a white window a plain (196, 196, 196).
        /// It does not move (film). Aris cannot see behind itself, so its rim is a faintly cool white.
        static let rimTint = (red: 0.86, green: 0.93, blue: 1.0)
    }

    // MARK: Your words

    enum Bubble {
        /// A capsule 30 tall (radius 15) with a tail under its right end, right-aligned; 13-point words (width
        /// matches at 13), 12 in from each end (shot 2).
        static let height = 30.0
        static let radius = 15.0
        static let fontSize = 13.0
        static let padding = 12.0
        /// The tail: about 7 wide and 5 tall, under the right end, leaning right (shot 2).
        static let tailWidth = 7.0
        static let tailHeight = 5.0
        /// At rest under the top bar the bubble is faint: white .02 at its top to .045 at its bottom, words .38
        /// (shot 2). Fresh, in the answer's column, it is the control glass with words at .9 (film, estimated).
        static let ink = 0.9
        static let restingInk = 0.38
        /// Aris's own: a hint in the bubble ("듣고 있어요…") is to be read, so it is .6 (4.5:1 on the glass), not
        /// Siri's resting .38.
        static let quietInk = 0.6
        /// Aris's own: the room left at the bubble's left before its words wrap, so it always reads as yours.
        static let leastGap = 90.0
    }

    // MARK: The answer

    enum Answer {
        /// 15-point regular on its natural 18-point line (two lines are 36 px apart; the line's width matches the
        /// system font at 15 exactly), white .90, highlights bold; 30 in from the panel's edge (shot 2 and 3).
        static let fontSize = 15.0
        static let lineHeight = 18.0
        static let ink = 0.90
        static let inset = 30.0
        /// It arrives all at once, sharpening out of a blur over about 0.2 s, the card a moment after it (film).
        static let reveal = 0.2
    }

    enum Card {
        /// The weather card: 388 × 101 in the 420 panel, 16 in, continuous corners of 32 (shot 4).
        static let radius = 32.0
        static let inset = 16.0
    }

    // MARK: Keeping Aris's content readable

    /// Siri's fill is thin low down, and Siri answers that with dark text over light windows and cards on their
    /// own plates. Aris's rows are white text straight on the surface, so behind the content column only (never
    /// the margins or the bottom inset) the black is thickened to Aris's proven floor: at most a fifth of a white
    /// window comes through there. Over a dark backdrop it changes nothing.
    enum Scrim {
        /// How much of what is behind is held back behind content: .90. At Aris's own text floor of .8 its
        /// secondary labels (white .5) stood at 4.0:1 over a pure white window; at .90 they keep 4.5:1 even on a
        /// row's own faint fill (the timer row, a card), running text 12:1 and everything on the control glass
        /// 5:1 or more. (Aris's quietest labels, white .38 to .43, are under 4.5:1 even over black; no fill can
        /// lift them past that.)
        static let floor = 0.90
        /// The plate's corners, how far it reaches past the column at each side, and how soft its edge is.
        static let radius = 20.0
        static let outset = 4.0
        static let soften = 4.0

        /// How much of what is behind comes through the glass and the fill `y` points down.
        static func through(at y: Double, height: Double, band: Double, base: Double) -> Double {
            (1 - base) * (1 - Surface.fill(at: y, height: height, band: band, base: base).coverage)
        }

        /// How much black the scrim adds `y` points down: none where the surface already holds the floor.
        static func alpha(at y: Double, height: Double, band: Double, base: Double) -> Double {
            let passes = through(at: y, height: height, band: band, base: base)
            guard passes > 1 - floor else { return 0 }
            return min(1, 1 - (1 - floor) / passes)
        }

        /// The scrim behind a column from `top` to `bottom`, as gradient stops (eleven, evenly spaced).
        static func stops(top: Double, bottom: Double, height: Double, band: Double, base: Double) -> [(location: Double, alpha: Double)] {
            (0...10).map { step in
                let t = Double(step) / 10
                return (t, alpha(at: top + (bottom - top) * t, height: height, band: band, base: base))
            }
        }

        /// What the surface reads (0…255) `y` points down over a backdrop of `behind`, with the scrim or without.
        static func reads(at y: Double, height: Double, band: Double, behind: Double, base: Double, scrim: Bool) -> Double {
            let f = Surface.fill(at: y, height: height, band: band, base: base)
            let plain = behind * (1 - base) * (1 - f.coverage) + 255 * f.grey * f.coverage
            return scrim ? plain * (1 - alpha(at: y, height: height, band: band, base: base)) : plain
        }
    }

    /// WCAG contrast between white at `ink` and what it is drawn on, both as 0…255 readings (sRGB greys). `glass`:
    /// the text sits on the control glass over that reading.
    static func contrast(ink: Double, on reading: Double, glass: Bool = false, fill: Double = 0) -> Double {
        func luminance(_ value: Double) -> Double {
            let c = min(1, max(0, value / 255))
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        // `fill`: the text sits on a row's or a card's own white fill of that strength (.05, .06).
        let ground = glass ? reading * (1 - Control.alpha) + 255 * Control.grey * Control.alpha : reading + (255 - reading) * fill
        let text = 255 * ink + ground * (1 - ink)
        return (luminance(text) + 0.05) / (luminance(ground) + 0.05)
    }

    // MARK: Thinking

    enum Dots {
        /// Six white dots on a ring, in a capsule 128 × 52 with one word after them (film, 6.6–8.6 s).
        static let count = 6
        /// The ring is 24 across in the 52-point capsule; a dot swells from 3.8 to 9 across and back.
        static let ringRadius = 12.0
        static let smallest = 3.8
        static let largest = 9.0
        /// The ring turns once in about 7.6 s (26° in 0.55 s); the swelling goes round it once in about 0.95 s.
        static let turn = 7.6
        static let wave = 0.95
        /// The capsule and its word (17 points, changing by blurring across, "처리 중" → "검색 중").
        static let capsule = (width: 128.0, height: 52.0)
        static let wordSize = 17.0

        /// Dot `index` at `time`: where on the ring (radians, clockwise from the top) and how wide, as a share of
        /// the ring's diameter. A smooth turning and swelling: no dot ever goes out or jumps. With Reduce Motion
        /// the ring is one still picture.
        static func dot(_ index: Int, at time: Double, reduceMotion: Bool = false) -> (angle: Double, size: Double) {
            let t = reduceMotion ? 0 : time
            let place = Double(index) / Double(count)
            let angle = 2 * Double.pi * (place + t / turn)
            let swell = (1 + cos(2 * Double.pi * (t / wave - place))) / 2
            let width = smallest + (largest - smallest) * swell
            return (angle, width / (2 * ringRadius))
        }
    }

    // MARK: Motion

    /// A spring as SwiftUI names it: how long one swing takes and how much of critical damping it has.
    struct Spring: Equatable {
        let response: Double
        let damping: Double

        /// How far along (0 → 1, past 1 on an overshoot) the spring is `time` seconds in.
        func progress(at time: Double) -> Double {
            guard time > 0, response > 0 else { return 0 }
            let w = 2 * Double.pi / response
            if damping >= 1 { return 1 - exp(-w * time) * (1 + w * time) }
            let wd = w * (1 - damping * damping).squareRoot()
            return 1 - exp(-damping * w * time) * (cos(wd * time) + damping * w / wd * sin(wd * time))
        }
    }

    enum Motion {
        /// Growing (the capsule into the answer, 128 × 52 → 420 × 172 and → 420 × 600): both sizes pass their
        /// end by about 2.7 % a quarter of a second in and are still by 0.45 s. Fit: response .42, damping .75.
        static let grow = Spring(response: 0.42, damping: 0.75)
        /// Shrinking (the answer into the capsule): faster and without the overshoot, done in about 0.3 s.
        static let shrink = Spring(response: 0.30, damping: 1)
        /// The controls arriving under the pointer (172 → 276 tall): response .52, damping .73.
        static let reveal = Spring(response: 0.52, damping: 0.73)
        /// The field's arrival: from 8 points above and 5 % larger, clear to full in about 0.12 s, in place by 0.2.
        static let appear = Spring(response: 0.22, damping: 0.8)
        static let appearFade = 0.12
        static let appearRise = 8.0
        static let appearScale = 1.05
    }
}
