// How the memory import sheet moves (ArisMemoryImportPacing): the curves it plays, which way a step change goes, the
// preview rows' stagger, and the notes cut into one sentence a line. Called last from main.swift; uses its check().
import Foundation

func runMemoryImportMotionTests() {
    typealias P = ArisMemoryImportPacing

    // The curves start at nothing, end at all, and never run backwards or past the end (no bounce).
    for curve in [P.step, P.leave, P.rise, P.tick, P.draw, P.undo, P.reduced] {
        check(curve.progress(at: 0) == 0, "every import curve starts at nothing")
        check(abs(curve.progress(at: curve.duration) - 1) < 1e-9, "every import curve has arrived when its time is up")
        check(curve.progress(at: curve.duration * 3) == 1, "every import curve stays arrived after its time")
        var last = 0.0, monotonic = true, inside = true
        for frame in 0...60 {
            let value = curve.progress(at: curve.duration * Double(frame) / 60)
            if value < last - 1e-9 { monotonic = false }
            if value < -1e-9 || value > 1 + 1e-9 { inside = false }
            last = value
        }
        check(monotonic, "an import curve never runs backwards")
        check(inside, "an import curve never overshoots (nothing in the sheet bounces)")
    }
    check(P.step.duration <= 0.3 && P.tick.duration <= 0.3 && P.undo.duration <= 0.3, "the sheet's own changes stay under 300 ms")
    check(P.leave.duration < P.step.duration, "a step leaves quicker than the next one comes in")

    // The solver matches CSS's cubic-bezier: ease-out-ish curves are well past half at half time; linear is linear.
    check(abs(P.bezier(0.5, 0, 0, 1, 1) - 0.5) < 1e-6, "a linear bezier is linear")
    check(P.draw.progress(at: P.draw.duration / 2) > 0.85, "the tick mark is mostly drawn by half its time (a strong ease-out)")
    check(abs(P.bezier(0.5, 0.45, 0, 0.55, 1) - 0.5) < 1e-6, "the symmetric close curve is halfway at half time")

    // Direction: forward is the order the sheet goes in; going back comes in from the other side.
    check(P.forward(from: "copy", to: "paste"), "next from the request goes forward")
    check(P.forward(from: "paste", to: "preview"), "the preview arriving goes forward")
    check(P.forward(from: "preview", to: "done"), "the receipt goes forward")
    check(!P.forward(from: "paste", to: "copy"), "back from the paste goes back")
    check(!P.forward(from: "preview", to: "paste"), "back (or add another part) from the preview goes back")

    // The stagger: 40 ms apart, only the first rows; a long list never trickles in.
    check(P.riseDelay(0) == 0 && abs(P.riseDelay(1) - 0.04) < 1e-9, "preview rows rise 40 ms apart")
    check(P.riseDelay(40) == P.riseDelay(P.riseRows), "rows past the first few rise with the last of them")
    check(P.riseDelay(40) + P.rise.duration < 0.62, "the whole list has risen in well under two thirds of a second")

    // One sentence a line, in both languages; a dot inside a word does not cut.
    check(P.sentences("가져오지 못했어요. 잠시 뒤에 다시 해 주세요.") == ["가져오지 못했어요.", "잠시 뒤에 다시 해 주세요."], "a Korean note is cut into its sentences")
    check(P.sentences("The export says there is more. When you have the next part, Add another part joins it to this list.")
          == ["The export says there is more.", "When you have the next part, Add another part joins it to this list."], "an English note is cut into its sentences")
    check(P.sentences("Paste that AI's whole answer, or drop a .txt or .md file here.").count == 1, "a file extension does not cut a sentence")
    check(P.sentences("체크한 줄만 기억에 들어가요.") == ["체크한 줄만 기억에 들어가요."], "a one-sentence note stays one line")
    check(P.sentences("") == [], "an empty note has no lines")
}
