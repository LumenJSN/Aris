//
//  ArisRecognizer.swift
//  Aris
//
//  What ArisListener hears with: one of Apple's speech engines behind one interface (ArisListenEngine picks which).
//  The listener owns the microphone (or the wake detector's audio, or a test file) and hands every buffer to the
//  recognizer in the format it asked for; the recognizer says what it heard. Two of them: ArisAnalyzerRecognizer
//  (SpeechAnalyzer, macOS 26) and ArisRotatingRecognizer (SFSpeechRecognizer, macOS 14 and 15, its tasks swapped
//  before Apple's one-minute limit and their text stitched). The tests drive the second with fake tasks.
//  AVFoundation only (tested).
//

import AVFoundation
import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "listen")

/// Where a recognizer wants its audio, and in what format. `append` runs on the audio thread.
struct ArisRecognizerInput: @unchecked Sendable {
    let format: AVAudioFormat
    let append: @Sendable (AVAudioPCMBuffer) -> Void
}

@MainActor
protocol ArisRecognizer: AnyObject {
    /// What was heard: `kept` is finished (the listener adds it to what it keeps), `guess` the current guess after it
    /// (it replaces the last one). Called on the main actor.
    var onHeard: ((_ kept: String, _ guess: String) -> Void)? { get set }
    /// It stopped hearing for good this listen, with the line that says why (the older engine with macOS Dictation
    /// off). Called on the main actor, once.
    var onProblem: ((String) -> Void)? { get set }
    /// The language's model isn't on this Mac yet (it is being installed, and this turn says so).
    func modelMissing(locale: Locale) async throws -> Bool
    /// Ready to hear `locale`, with `hints` as words to expect.
    func start(locale: Locale, hints: [String]) async throws -> ArisRecognizerInput
    /// No more audio: waits for the last words (every onHeard has been called when it returns).
    func finish() async
}

// MARK: - The older engine, task by task

/// One recognition task of the older engine. `append` is called on the audio thread.
protocol ArisSpeechTask: AnyObject, Sendable {
    func append(_ buffer: AVAudioPCMBuffer)
    /// No more audio for this task: it finishes its last words and ends.
    func endAudio()
    func cancel()
}

/// Makes the older engine's tasks (ArisSFSpeechTasks in the app, a fake in the tests).
@MainActor
protocol ArisSpeechTaskMaker: AnyObject {
    /// The audio format its tasks take.
    var format: AVAudioFormat { get }
    /// Where it recognises (known once `prepare` ran).
    var place: ArisListenPlace { get }
    /// Ready for `locale`, or why not.
    func prepare(locale: Locale) throws
    /// A new task. `onText`: its whole text so far (`final`: its last); `onEnd`: it ended without a final text, with
    /// the line for the user when its error means no task can hear (ArisListenEngineWords.problem). Both on the main actor.
    func make(hints: [String], onText: @escaping @MainActor (String, Bool) -> Void, onEnd: @escaping @MainActor (String?) -> Void) -> ArisSpeechTask
}

/// The older engine: one task at a time, swapped for a new one at a pause before Apple's one-minute limit (and when a
/// task ends by itself while Aris still listens), the tasks' text stitched (ArisTaskStitch, ArisTaskRotation).
@MainActor
final class ArisRotatingRecognizer: ArisRecognizer {
    var onHeard: ((_ kept: String, _ guess: String) -> Void)?
    var onProblem: ((String) -> Void)?

    private let maker: ArisSpeechTaskMaker
    private var stitch = ArisTaskStitch()
    private var hints: [String] = []
    /// The task hearing now, its segment, and when (in seconds of audio) it began.
    private var current: (index: Int, task: ArisSpeechTask, startedAt: Double, wrote: Bool)?
    private var tasks: [Int: ArisSpeechTask] = [:]
    private let route = AudioRoute()
    private var running = false
    private var quickEnds = 0
    private var ticker: Task<Void, Never>?
    private var finished: CheckedContinuation<Void, Never>?
    /// Tasks started, for the log and the tests.
    private(set) var started = 0

    init(maker: ArisSpeechTaskMaker) { self.maker = maker }

    /// Where it recognises (on the Mac, or Apple's servers).
    var place: ArisListenPlace { maker.place }

    func modelMissing(locale: Locale) async throws -> Bool { false }

    func start(locale: Locale, hints: [String]) async throws -> ArisRecognizerInput {
        try maker.prepare(locale: locale)
        self.hints = hints
        running = true
        begin()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, self.running else { return }
                self.tick()
            }
        }
        let route = route
        return ArisRecognizerInput(format: maker.format, append: { route.append($0) })
    }

    /// Swaps the task when it is time (ArisTaskRotation). Called four times a second; the tests call it directly.
    func tick() {
        guard running, let current else { return }
        let clock = route.clock()
        let age = clock.heard - current.startedAt
        let quiet = clock.heard - max(clock.lastLoud, current.startedAt)
        guard ArisTaskRotation.shouldRotate(age: age, quietFor: quiet) else { return }
        log.notice("older engine: task \(current.index, privacy: .public) swapped after \(Int(age), privacy: .public) s (quiet \(Int(quiet * 1000), privacy: .public) ms)")
        begin()
        current.task.endAudio()
    }

    func finish() async {
        running = false
        ticker?.cancel()
        ticker = nil
        route.task = nil
        current?.task.endAudio()
        current = nil
        if !stitch.allEnded {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                finished = continuation
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(ArisTaskRotation.finishWait))
                    self?.giveUpWaiting()
                }
            }
        }
        for task in tasks.values { task.cancel() }
        tasks = [:]
    }

    /// The last tasks took too long to end: what they wrote last is kept.
    private func giveUpWaiting() {
        guard let finished else { return }
        self.finished = nil
        if !stitch.allEnded {
            log.notice("older engine: the last task gave no final words in time; its last guess is kept")
            deliver(stitch.endAll())
        }
        finished.resume()
    }

    private func begin() {
        let index = stitch.begin()
        let task = maker.make(hints: hints,
                              onText: { [weak self] text, final in self?.heard(index, text: text, final: final) },
                              onEnd: { [weak self] problem in self?.ended(index, problem: problem) })
        tasks[index] = task
        started += 1
        current = (index, task, route.clock().heard, false)
        route.task = task
    }

    private func heard(_ index: Int, text: String, final: Bool) {
        guard !stitch.isEnded(index) else { return }
        if index == current?.index, !text.isEmpty { current?.wrote = true }
        deliver(stitch.update(index, text: text, final: final))
        if final { taskEnded(index) }
    }

    private func ended(_ index: Int, problem: String? = nil) {
        guard !stitch.isEnded(index) else { return }
        deliver(stitch.end(index))
        taskEnded(index, problem: problem)
    }

    /// Task `index` is over: the next one starts if it was the one hearing and Aris still listens. A task whose error
    /// means none can hear (macOS Dictation off), or the third in a row to end at once, ends the listening with a line.
    private func taskEnded(_ index: Int, problem: String? = nil) {
        tasks[index] = nil
        if let current, current.index == index, running {
            let next = ArisTaskRotation.afterEnd(quickEnds: quickEnds, age: route.clock().heard - current.startedAt, wroteWords: current.wrote)
            quickEnds = next.quickEnds
            if next.restart, problem == nil {
                log.notice("older engine: task \(index, privacy: .public) ended by itself; the next one listens")
                begin()
            } else {
                let why = problem == nil ? "\(quickEnds) tasks in a row ended at once" : "it can't hear (macOS Dictation off)"
                log.error("older engine: \(why, privacy: .public); it stops trying this listen")
                self.current = nil
                route.task = nil
                let line = problem ?? ArisListenEngineWords.couldNotHear(english: ArisUIWords.english)
                let report = onProblem
                onProblem = nil
                report?(line)
            }
        }
        if !running, stitch.allEnded, let finished {
            self.finished = nil
            finished.resume()
        }
    }

    private func deliver(_ heard: (kept: String, guess: String)) {
        onHeard?(heard.kept, heard.guess)
    }
}

/// Hands each buffer to the task hearing now, and counts the audio (seconds heard, when it was last loud) on the audio
/// thread for the swap.
private final class AudioRoute: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: ArisSpeechTask?
    private var heard = 0.0
    private var lastLoud = 0.0

    var task: ArisSpeechTask? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    func clock() -> (heard: Double, lastLoud: Double) { lock.withLock { (heard, lastLoud) } }

    func append(_ buffer: AVAudioPCMBuffer) {
        let loud = Self.rms(buffer) >= ArisTaskRotation.quietRMS
        let seconds = buffer.format.sampleRate > 0 ? Double(buffer.frameLength) / buffer.format.sampleRate : 0
        let task: ArisSpeechTask? = lock.withLock {
            heard += seconds
            if loud { lastLoud = heard }
            return stored
        }
        task?.append(buffer)
    }

    private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        if let samples = buffer.floatChannelData?[0] {
            for i in 0..<frames { sum += samples[i] * samples[i] }
        } else if let samples = buffer.int16ChannelData?[0] {
            for i in 0..<frames { let s = Float(samples[i]) / Float(Int16.max); sum += s * s }
        } else {
            return 0
        }
        return (sum / Float(frames)).squareRoot()
    }
}
