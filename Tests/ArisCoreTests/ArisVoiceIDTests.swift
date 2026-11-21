import XCTest
@testable import ArisCore

/// F1, the owner's voice: the vector arithmetic, the print and its update rule, the verdict's lines on fixture
/// vectors, what a verdict changes (wake, spoken yes, learning, the turn's speaker), and the provenance rows the
/// speaker adds to the trust policy.
final class ArisVoiceIDTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let model = "community-1"
    private let size = 256

    /// A unit vector along axis `axis`, tilted towards axis `towards` so its cosine to the axis is `cosine`.
    private func vector(axis: Int, towards: Int = 255, cosine: Float = 1) -> [Float] {
        var out = [Float](repeating: 0, count: size)
        out[axis] = cosine
        out[towards] += (1 - cosine * cosine).squareRoot()
        return out
    }

    private func enrolled(axis: Int = 0) -> ArisVoiceProfile {
        ArisVoiceProfile.empty(model: model, at: now).adding([(vector(axis: axis), 3), (vector(axis: axis), 3), (vector(axis: axis), 3)], at: now)
    }

    // MARK: - Vectors

    func testCosineMeanAndBlend() {
        XCTAssertEqual(ArisVoiceVector.cosine([1, 0], [1, 0]), 1)
        XCTAssertEqual(ArisVoiceVector.cosine([1, 0], [0, 2]), 0)
        XCTAssertEqual(ArisVoiceVector.cosine([2, 0], [-1, 0]), -1)
        XCTAssertNil(ArisVoiceVector.cosine([1, 0], [1, 0, 0]), "sizes differ")
        XCTAssertNil(ArisVoiceVector.cosine([0, 0], [1, 0]), "no direction")
        XCTAssertNil(ArisVoiceVector.normalized([1, .nan]))
        XCTAssertNil(ArisVoiceVector.normalized([1, .infinity]))
        let mean = ArisVoiceVector.mean([[1, 0], [0, 1]])!
        XCTAssertEqual(mean[0], mean[1], accuracy: 1e-6)
        XCTAssertEqual(mean[0], 1 / Float(2).squareRoot(), accuracy: 1e-6)
        XCTAssertNil(ArisVoiceVector.mean([[1, 0], [1, 0, 0]]))
        XCTAssertNil(ArisVoiceVector.mean([]))
        let half = ArisVoiceVector.blended([1, 0], [0, 1], weight: 0.5)!
        XCTAssertEqual(half[0], half[1], accuracy: 1e-6)
    }

    // MARK: - The print

    func testAPrintIsEnrolledOnlyWithEnoughUtterancesAndVoice() {
        var profile = ArisVoiceProfile.empty(model: model, at: now)
        XCTAssertFalse(profile.isEnrolled)
        profile = profile.adding(vector(axis: 0), seconds: 4, at: now)!
        profile = profile.adding(vector(axis: 0), seconds: 4, at: now)!
        XCTAssertFalse(profile.isEnrolled, "two utterances are not enough, however long")
        var short = ArisVoiceProfile.empty(model: model, at: now)
        for _ in 0..<4 { short = short.adding(vector(axis: 0), seconds: 1, at: now)! }
        XCTAssertFalse(short.isEnrolled, "four utterances but 4 s of voice: the bar is 6 s")
        XCTAssertTrue(short.adding(vector(axis: 0), seconds: 2, at: now)!.isEnrolled)
        XCTAssertTrue(enrolled().isEnrolled)
    }

    func testTheUpdateRuleIsAnExactMeanThenASteadyStep() {
        // The first utterances are an exact mean.
        let two = ArisVoiceProfile.empty(model: model, at: now).adding([([1] + [Float](repeating: 0, count: size - 1), 2),
                                                                          ([0, 1] + [Float](repeating: 0, count: size - 2), 2)], at: now)
        XCTAssertEqual(two.centroid[0], two.centroid[1], accuracy: 1e-5)
        XCTAssertEqual(two.samples, 2)
        XCTAssertEqual(two.seconds, 4)
        // Past steadyAt, one odd utterance moves the print by 1/steadyAt only.
        var settled = ArisVoiceProfile.empty(model: model, at: now)
        for _ in 0..<60 { settled = settled.adding(vector(axis: 0), seconds: 2, at: now)! }
        let odd = settled.adding(vector(axis: 1), seconds: 2, at: now.addingTimeInterval(5))!
        let moved = ArisVoiceVector.cosine(odd.centroid, settled.centroid)!
        XCTAssertGreaterThan(moved, 0.999, "one utterance barely moves a settled print")
        XCTAssertEqual(odd.samples, 61)
        XCTAssertEqual(odd.updated, now.addingTimeInterval(5))
        XCTAssertEqual(odd.created, now)
        // It still follows a voice that changes for good.
        var follows = settled
        for _ in 0..<80 { follows = follows.adding(vector(axis: 1), seconds: 2, at: now)! }
        XCTAssertGreaterThan(ArisVoiceVector.cosine(follows.centroid, vector(axis: 1))!, 0.8)
        // The print never mutates: the old one is as it was.
        XCTAssertEqual(settled.samples, 60)
    }

    func testAPrintRefusesWhatIsNotAVoiceVector() {
        let profile = enrolled()
        XCTAssertNil(profile.adding([1, 2, 3], seconds: 2, at: now), "too small to be a model's vector")
        XCTAssertNil(profile.adding(vector(axis: 0) + [0], seconds: 2, at: now), "a size other than the print's")
        XCTAssertNil(profile.adding([Float](repeating: 0, count: size), seconds: 2, at: now))
        XCTAssertNil(profile.adding(vector(axis: 0), seconds: 0, at: now))
        XCTAssertNil(profile.adding(vector(axis: 0), seconds: .nan, at: now))
    }

    func testTheStoredFormRoundTripsAndAnythingElseIsNoPrint() {
        let profile = enrolled()
        let data = profile.encoded()!
        XCTAssertEqual(ArisVoiceProfile.decoded(data, model: model), profile)
        XCTAssertNil(ArisVoiceProfile.decoded(data, model: "another-model"), "a print from another model means nothing")
        XCTAssertNil(ArisVoiceProfile.decoded(Data("{}".utf8), model: model))
        XCTAssertNil(ArisVoiceProfile.decoded(Data("not json".utf8), model: model))
        // A centroid someone edited off unit length, or with a count that lies, is not used.
        var json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        json["centroid"] = [Float](repeating: 3, count: size)
        XCTAssertNil(ArisVoiceProfile.decoded(try! JSONSerialization.data(withJSONObject: json), model: model))
        json["centroid"] = [Float]()
        XCTAssertNil(ArisVoiceProfile.decoded(try! JSONSerialization.data(withJSONObject: json), model: model), "no centroid but samples > 0")
        XCTAssertEqual(ArisVoiceProfile.decoded(ArisVoiceProfile.empty(model: model, at: now).encoded()!, model: model)?.samples, 0)
        // Nothing but numbers and counts is stored: no audio, no words.
        XCTAssertEqual(Set(json.keys), ["version", "model", "centroid", "samples", "seconds", "created", "updated"])
    }

    // MARK: - The verdict

    func testTheLinesOnFixtureVectors() {
        let profile = enrolled()
        func verdict(_ cosine: Float, _ seconds: Double) -> ArisVoiceVerdict {
            ArisVoiceMatcher.match(vector(axis: 0, cosine: cosine), seconds: seconds, profile: profile).verdict
        }
        // Long utterances: owner at 0.60 and over, not the owner under 0.40.
        XCTAssertEqual(verdict(0.85, 3), .owner)
        XCTAssertEqual(verdict(0.60, 3), .owner)
        XCTAssertEqual(verdict(0.59, 3), .unsure)
        XCTAssertEqual(verdict(0.40, 3), .unsure)
        XCTAssertEqual(verdict(0.39, 3), .notOwner)
        XCTAssertEqual(verdict(0.10, 3), .notOwner)
        // Short ones (a lone "아리스", a "응"): a wider band.
        XCTAssertEqual(verdict(0.61, 1), .unsure)
        XCTAssertEqual(verdict(0.62, 1), .owner)
        XCTAssertEqual(verdict(0.39, 1), .unsure)
        XCTAssertEqual(verdict(0.37, 1), .notOwner)
        // Too little voice decides nothing, however far off.
        XCTAssertEqual(verdict(0.0, 0.3), .unsure)
        XCTAssertEqual(ArisVoiceMatcher.match(vector(axis: 0), seconds: 0.3, profile: profile).why, "too-short")
    }

    func testNoPrintAndNoVectorAreUnsure() {
        XCTAssertEqual(ArisVoiceMatcher.match(vector(axis: 0), seconds: 3, profile: nil), .unsure("no-print", seconds: 3))
        let half = ArisVoiceProfile.empty(model: model, at: now).adding(vector(axis: 0), seconds: 3, at: now)!
        XCTAssertEqual(ArisVoiceMatcher.match(vector(axis: 0), seconds: 3, profile: half).why, "no-print", "not enrolled yet")
        XCTAssertEqual(ArisVoiceMatcher.match(nil, seconds: 3, profile: enrolled()).why, "no-vector")
        XCTAssertEqual(ArisVoiceMatcher.match([1, 2], seconds: 3, profile: enrolled()).why, "no-vector")
    }

    // MARK: - What a verdict changes

    private func match(_ verdict: ArisVoiceVerdict) -> ArisVoiceMatch {
        switch verdict {
        case .owner: ArisVoiceMatcher.verdict(score: 0.8, seconds: 3)
        case .notOwner: ArisVoiceMatcher.verdict(score: 0.1, seconds: 3)
        case .unsure: ArisVoiceMatcher.verdict(score: 0.5, seconds: 3)
        }
    }

    func testTheWakeClosesOnlyForAClearlyOtherVoiceAndNeverTwiceInARow() {
        typealias D = ArisVoiceDecisions
        for entry in [ArisTurnEntry.wakeWord, .followUp] {
            XCTAssertEqual(D.wake(match(.notOwner), entry: entry, lastClose: nil, now: 100), .closeNotOwner)
            XCTAssertEqual(D.wake(match(.unsure), entry: entry, lastClose: nil, now: 100), .goOn, "unsure: today's behaviour")
            XCTAssertEqual(D.wake(match(.owner), entry: entry, lastClose: nil, now: 100), .goOn)
            XCTAssertEqual(D.wake(nil, entry: entry, lastClose: nil, now: 100), .goOn, "nothing checked: today's behaviour")
            // Misheard once, the owner's second try near the print within the window is heard; a clearly different voice
            // repeating itself is not.
            let near = ArisVoiceMatcher.verdict(score: 0.33, seconds: 3), nearShort = ArisVoiceMatcher.verdict(score: 0.31, seconds: 1)
            XCTAssertEqual(near.verdict, .notOwner)
            XCTAssertEqual(D.wake(near, entry: entry, lastClose: 95, now: 100), .goOn)
            XCTAssertEqual(D.wake(nearShort, entry: entry, lastClose: 95, now: 100), .goOn)
            XCTAssertEqual(D.wake(ArisVoiceMatcher.verdict(score: 0.31, seconds: 3), entry: entry, lastClose: 95, now: 100), .closeNotOwner)
            XCTAssertEqual(D.wake(ArisVoiceMatcher.verdict(score: 0.29, seconds: 1), entry: entry, lastClose: 95, now: 100), .closeNotOwner)
            XCTAssertEqual(D.wake(match(.notOwner), entry: entry, lastClose: 95, now: 100), .closeNotOwner, "a clearly other voice: no second chance")
            XCTAssertEqual(D.wake(near, entry: entry, lastClose: 80, now: 100), .closeNotOwner, "past the window")
            XCTAssertEqual(D.wake(near, entry: entry, lastClose: nil, now: 100), .closeNotOwner, "the first time")
        }
        // The key and typing are never held to the voice.
        for entry in [ArisTurnEntry.keyHeld, .typed, .tapped] {
            XCTAssertEqual(D.wake(match(.notOwner), entry: entry, lastClose: nil, now: 100), .goOn)
        }
        XCTAssertFalse(D.checks(.keyHeld))
        XCTAssertFalse(D.checks(.typed))
        XCTAssertTrue(D.checks(.wakeWord) && D.checks(.followUp) && D.checks(.tapped))
    }

    func testASpokenYesIsRefusedOnlyForAClearlyOtherVoice() {
        XCTAssertFalse(ArisVoiceDecisions.yesCounts(match(.notOwner)))
        XCTAssertTrue(ArisVoiceDecisions.yesCounts(match(.unsure)))
        XCTAssertTrue(ArisVoiceDecisions.yesCounts(match(.owner)))
        XCTAssertTrue(ArisVoiceDecisions.yesCounts(nil))
        XCTAssertTrue(ArisVoiceDecisions.yesCounts(.unsure("too-short")))
        XCTAssertTrue(ArisVoiceDecisions.yesRefusedLine(english: false).contains("Y"))
        XCTAssertTrue(ArisVoiceDecisions.yesRefusedLine(english: true).contains("Allow"))
    }

    func testOnlyAHeldKeyTeachesThePrintAndNeverAnotherVoice() {
        typealias D = ArisVoiceDecisions
        XCTAssertTrue(D.learns(entry: .keyHeld, seconds: 2, match: nil), "the first utterances start the print")
        XCTAssertTrue(D.learns(entry: .keyHeld, seconds: 2, match: match(.owner)))
        XCTAssertTrue(D.learns(entry: .keyHeld, seconds: 2, match: match(.unsure)))
        XCTAssertFalse(D.learns(entry: .keyHeld, seconds: 2, match: match(.notOwner)), "a video playing while the key is held")
        XCTAssertFalse(D.learns(entry: .keyHeld, seconds: 0.6, match: nil), "too little voice")
        for entry in [ArisTurnEntry.wakeWord, .followUp, .tapped, .typed] {
            XCTAssertFalse(D.learns(entry: entry, seconds: 5, match: match(.owner)), "\(entry) never teaches the print")
        }
    }

    func testTheTurnsSpeaker() {
        typealias D = ArisVoiceDecisions
        XCTAssertEqual(D.speaker(.typed, match: match(.notOwner)), .typed)
        XCTAssertEqual(D.speaker(.keyHeld, match: match(.notOwner)), .keyHeld)
        XCTAssertEqual(D.speaker(.wakeWord, match: match(.owner)), .voiceMatched)
        XCTAssertEqual(D.speaker(.wakeWord, match: match(.unsure)), .unverified, "unsure counts like content (a card)")
        XCTAssertEqual(D.speaker(.followUp, match: match(.notOwner)), .unverified)
        XCTAssertEqual(D.speaker(.tapped, match: .unsure("too-short")), .unverified)
        XCTAssertEqual(D.speaker(.wakeWord, match: nil), .notChecked)
        XCTAssertEqual(D.speaker(.wakeWord, match: .unsure("no-print")), .notChecked, "no print: as today")
        XCTAssertEqual(ArisTurnSpeaker.allCases.filter { !$0.countsAsOwner }, [.unverified])
        XCTAssertEqual(ArisTurnSpeaker.named(nil), .notChecked)
        XCTAssertEqual(ArisTurnSpeaker.named("someone"), .notChecked)
        XCTAssertEqual(ArisTurnSpeaker.named("unverified"), .unverified)
    }

    // MARK: - The audio

    func testTheClipIsTrimmedMeasuredAndFilled() {
        let rate = ArisVoiceClip.sampleRate
        let silence = [Float](repeating: 0, count: rate / 2)
        let tone = (0..<rate).map { Float(sin(Double($0) * 2 * .pi * 220 / Double(rate))) * 0.3 }
        let clip = silence + tone + silence
        let trimmed = ArisVoiceClip.trimmed(clip)
        XCTAssertEqual(Double(trimmed.count) / Double(rate), 1.0, accuracy: 0.05)
        XCTAssertEqual(ArisVoiceClip.voicedSeconds(clip), 1.0, accuracy: 0.05)
        XCTAssertEqual(ArisVoiceClip.voicedSeconds(silence), 0)
        XCTAssertEqual(ArisVoiceClip.trimmed(silence), [])
        let filled = ArisVoiceClip.filled(trimmed)!
        XCTAssertEqual(filled.count, ArisVoiceClip.window)
        XCTAssertEqual(Array(filled[trimmed.count..<(trimmed.count + 100)]), Array(trimmed.prefix(100)), "a short clip is repeated, not padded")
        XCTAssertEqual(ArisVoiceClip.filled([Float](repeating: 0.1, count: ArisVoiceClip.window * 2))!.count, ArisVoiceClip.window)
        XCTAssertNil(ArisVoiceClip.filled([]))
    }

    // MARK: - The provenance rows

    private let home = "/Users/user"
    private let world = ArisWorldFacts(contacts: [.init(name: "엄마", addresses: ["mom@example.com"])], home: "/Users/user")

    private func verdict(_ words: String, speaker: ArisTurnSpeaker, effect: ArisEffectClass, arguments: [ArisKeyArgument]) -> ArisProvenanceVerdict {
        var tracker = ArisProvenanceTracker(world: world)
        tracker.ownerTurn(words, speaker: speaker)
        return tracker.toolCall(id: "c1", capability: effect == .outward ? "messages.send" : "file.delete", effect: effect, arguments: arguments)
    }

    func testTheVerdictCarriesTheTurnsSpeaker() {
        let send = [ArisKeyArgument(kind: .recipient, value: "엄마"), ArisKeyArgument(kind: .body, value: "늦어요")]
        let owner = verdict("엄마한테 늦어요라고 보내 줘", speaker: .keyHeld, effect: .outward, arguments: send)
        XCTAssertEqual(owner.provenance, .ownerSaid)
        XCTAssertEqual(owner.speaker, .keyHeld)
        let other = verdict("엄마한테 늦어요라고 보내 줘", speaker: .unverified, effect: .outward, arguments: send)
        XCTAssertEqual(other.provenance, .ownerSaid, "the words still ground the call; the speaker is a field of its own")
        XCTAssertEqual(other.speaker, .unverified)
        XCTAssertTrue(other.reasons.contains { $0.contains("voice") })
        // A turn after it is spoken by whoever speaks it.
        var tracker = ArisProvenanceTracker(world: world)
        tracker.ownerTurn("엄마한테 보내", speaker: .unverified)
        tracker.ownerTurn("엄마한테 보내", speaker: .typed)
        XCTAssertEqual(tracker.turnSpeaker, .typed)
        XCTAssertEqual(ArisProvenanceTracker(world: world).turnSpeaker, .notChecked)
    }

    func testAnUnverifiedVoiceAsksBeforeAnythingOutwardOrPermanentAtEveryLevel() {
        let call = ArisCallFacts(capability: "messages.send", arguments: [ArisKeyArgument(kind: .recipient, value: "mom@example.com")])
        let grant = ArisStandingGrant(capability: "messages.*", target: .init(kind: .recipient, pattern: "엄마", addresses: ["mom@example.com"]))
        let provenances: [ArisCallProvenance] = [.ownerSaid, .ownerEarlier, .ownStep, .content(ArisContentSource(kind: "web", source: "x"))]
        for level in ArisTrustLevel.allCases {
            for provenance in provenances {
                for grants in [[], [grant]] {
                    let context = ArisTrustPolicy.Context(level: level, grants: grants, home: home)
                    for effect in ArisEffectClass.allCases {
                        let owner = ArisTrustPolicy.decide(call, effect: effect, provenance: provenance, specified: true, context: context)
                        for speaker in ArisTurnSpeaker.allCases {
                            let got = ArisTrustPolicy.decide(call, effect: effect, provenance: provenance, specified: true, speaker: speaker, context: context)
                            let name = "\(level) \(provenance.column) \(effect) \(speaker) grant=\(!grants.isEmpty)"
                            if speaker.countsAsOwner || effect == .observe || effect == .changeReversible {
                                XCTAssertEqual(got, owner, name + ": the owner's decision, unchanged")
                            } else if case .refuse = owner {
                                XCTAssertEqual(got, owner, name + ": a refusal stays")
                            } else if owner.waitsForOwner {
                                XCTAssertEqual(got, owner, name + ": a question stays as it was")
                            } else {
                                XCTAssertEqual(got, effect == .outward ? .readBackThenAsk : .ask, name + ": what would have run waits for the owner")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Earlier words and undo (security review of the first commit)

    func testEarlierWordsInAnotherVoiceNeverGroundACallAsTheOwners() {
        let send = [ArisKeyArgument(kind: .recipient, value: "엄마"), ArisKeyArgument(kind: .body, value: "늦어요")]
        // Someone else names the recipient; then the owner, verified, says "그거 해 줘".
        var tracker = ArisProvenanceTracker(world: world)
        tracker.ownerTurn("엄마한테 늦어요라고 문자 보내", speaker: .unverified)
        tracker.ownerTurn("그거 해 줘", speaker: .voiceMatched)
        let after = tracker.toolCall(id: "c1", capability: "messages.send", effect: .outward, arguments: send)
        XCTAssertEqual(after.speaker, .unverified, "it stands only on the other voice's words")
        XCTAssertTrue(after.reasons.contains { $0.contains("earlier words") })
        let context = ArisTrustPolicy.Context(level: .free, home: home)
        XCTAssertTrue(ArisTrustPolicy.decide(ArisCallFacts(capability: "messages.send", arguments: send), effect: .outward, provenance: after.provenance,
                                             specified: after.specified, ownerNamed: after.ownerNamed, speaker: after.speaker, context: context).waitsForOwner)
        // The same words from the owner's own earlier turn stay his.
        var own = ArisProvenanceTracker(world: world)
        own.ownerTurn("엄마한테 늦어요라고 문자 보내", speaker: .keyHeld)
        own.ownerTurn("그거 해 줘", speaker: .voiceMatched)
        XCTAssertEqual(own.toolCall(id: "c1", capability: "messages.send", effect: .outward, arguments: send).speaker, .voiceMatched)
        // A call the owner's own words ground does not lean on the other voice's turn in between.
        var mixed = ArisProvenanceTracker(world: world)
        mixed.ownerTurn("유튜브 틀어 줘", speaker: .unverified)
        mixed.ownerTurn("엄마한테 늦어요라고 문자 보내", speaker: .keyHeld)
        XCTAssertEqual(mixed.toolCall(id: "c1", capability: "messages.send", effect: .outward, arguments: send).speaker, .keyHeld)
        // Unenrolled (nothing checked anywhere): exactly as before.
        var before = ArisProvenanceTracker(world: world)
        before.ownerTurn("엄마한테 늦어요라고 문자 보내")
        before.ownerTurn("그거 해 줘")
        let plain = before.toolCall(id: "c1", capability: "messages.send", effect: .outward, arguments: send)
        XCTAssertEqual(plain.speaker, .notChecked)
        XCTAssertEqual(plain.provenance, .ownerEarlier)
        XCTAssertEqual(before.earlierSpeakers, [.notChecked])
    }

    private func undoEntry(_ session: String, undo: ArisUndoRecipe) -> ArisRecordEntry {
        .call(at: now.addingTimeInterval(-60), session: session, task: nil, capability: "file.write", effect: .changeReversible, provenance: .ownerSaid,
              decision: .runWithUndo(announce: false), arguments: [.init(kind: .path, value: "/Users/Documents/a.txt")], result: nil, ok: true, undo: undo)
    }

    func testAnUndoInAnotherVoiceIsDecidedLikeAnyChangeInThatVoice() {
        let context = ArisTrustPolicy.Context(level: .free, home: home, now: now)
        let mine = undoEntry("s1", undo: .fileCreated(path: "/Users/Documents/a.txt"))
        let theirs = undoEntry("s2", undo: .fileCreated(path: "/Users/Documents/a.txt"))
        let event = undoEntry("s1", undo: .itemCreated(kind: "calendar", id: "E1"))
        let path = [ArisKeyArgument(kind: .path, value: "/Users/Documents/a.txt")]
        for speaker in ArisTurnSpeaker.allCases {
            let caller = ArisUndoCaller(session: "s1", provenance: .ownerSaid, speaker: speaker)
            // Reach: another conversation's entry only for the owner's own words in his own voice.
            let reach = ArisUndoScope.decide(id: nil, count: 3, state: ArisRecordState([mine, theirs]), caller: caller, context: context).ids
            XCTAssertEqual(Set(reach), speaker.countsAsOwner ? [theirs.id, mine.id] : [mine.id], "\(speaker)")
            // Decision: the same as any change of that effect class asked for in that voice.
            for (entry, effect) in [(mine, ArisEffectClass.changeReversible), (event, .changePermanent)] {
                let undo = ArisUndoScope.decide(id: nil, count: 1, state: ArisRecordState([entry]), caller: caller, context: context).decision
                let change = ArisTrustPolicy.decide(ArisCallFacts(capability: "record.undo", arguments: effect == .changePermanent ? [] : path),
                                                    effect: effect, provenance: .ownerSaid, speaker: speaker, context: context)
                XCTAssertEqual(undo, change, "\(speaker) \(effect)")
            }
        }
        // An older entry named by id: never for another voice.
        let old = ArisRecordEntry.call(at: now.addingTimeInterval(-3 * 86_400), session: "s1", task: nil, capability: "file.write", effect: .changeReversible,
                                       provenance: .ownerSaid, decision: .runWithUndo(announce: false), arguments: path, result: nil, ok: true,
                                       undo: .fileCreated(path: "/Users/Documents/a.txt"))
        let other = ArisUndoCaller(session: "s1", provenance: .ownerSaid, speaker: .unverified)
        if case .refuse = ArisUndoScope.decide(id: old.id, count: nil, state: ArisRecordState([old]), caller: other, context: context).decision {} else { XCTFail() }
        XCTAssertEqual(ArisUndoScope.decide(id: old.id, count: nil, state: ArisRecordState([old]), caller: ArisUndoCaller(session: "s1", provenance: .ownerSaid),
                                            context: context).decision, .readBackThenAsk, "unenrolled: as before")
    }

    // MARK: - Fail-closed, parity, notice (security review of the app hooks)

    func testNoAudioWithAPrintIsUnsureNeverNothingChecked() {
        typealias D = ArisVoiceDecisions
        for entry in [ArisTurnEntry.wakeWord, .followUp, .tapped] {
            let none = D.noAudio(on: true, enrolled: true, entry: entry)
            XCTAssertEqual(none, .unsure("no-audio"))
            XCTAssertEqual(D.speaker(entry, match: none), .unverified, "\(entry): no audio with a print is unverified")
            XCTAssertEqual(D.wake(none, entry: entry, lastClose: nil, now: 1), .goOn, "unsure never closes a turn")
            XCTAssertNil(D.noAudio(on: false, enrolled: true, entry: entry), "switched off: as today")
            XCTAssertNil(D.noAudio(on: true, enrolled: false, entry: entry), "no print: as today")
            XCTAssertEqual(D.speaker(entry, match: D.noAudio(on: true, enrolled: false, entry: entry)), .notChecked)
        }
        XCTAssertNil(D.noAudio(on: true, enrolled: true, entry: .keyHeld))
        XCTAssertNil(D.noAudio(on: true, enrolled: true, entry: .typed))
    }

    func testAnEarlyRequestGoesOnlyForTheOwnersVoiceAndNeverWithAStrongerTag() {
        typealias D = ArisVoiceDecisions
        XCTAssertTrue(D.early(nil), "nothing checked: as today")
        XCTAssertTrue(D.early(match(.owner)))
        XCTAssertFalse(D.early(match(.unsure)))
        XCTAssertFalse(D.early(match(.notOwner)))
        XCTAssertFalse(D.early(.unsure("too-short")), "no audio so far: the request waits")
        // The turn takes an early request only when the final speaker agrees on owner-or-not.
        XCTAssertTrue(D.sameTag(early: .voiceMatched, final: .voiceMatched))
        XCTAssertTrue(D.sameTag(early: nil, final: .notChecked))
        XCTAssertTrue(D.sameTag(early: nil, final: .keyHeld))
        XCTAssertFalse(D.sameTag(early: .voiceMatched, final: .unverified), "the final check weaker: the early request is dropped")
        XCTAssertFalse(D.sameTag(early: nil, final: .unverified))
        for speaker in ArisTurnSpeaker.allCases { XCTAssertEqual(D.ownerTag(speaker), speaker.countsAsOwner) }
        XCTAssertTrue(D.ownerTag(nil))
    }

    func testTheNoticeSaysTheKeyWorksAndComesAtMostEveryTenMinutes() {
        typealias D = ArisVoiceDecisions
        XCTAssertTrue(D.noticeDue(last: nil, now: 5))
        XCTAssertFalse(D.noticeDue(last: 5, now: 300))
        XCTAssertTrue(D.noticeDue(last: 5, now: 5 + D.noticeEvery))
        XCTAssertTrue(D.noticeDue(last: 500, now: 10), "a clock that went back")
        XCTAssertTrue(D.closedLine(english: false).contains("단축키"))
        XCTAssertTrue(D.closedLine(english: true).contains("shortcut"))
    }
}
