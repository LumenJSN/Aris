// Tests for Aris's face (the owner's "Settings A", mockups/face/sa.html): the stored pick, the teammates' pool without
// Aris's type, the move of a teammate wearing it, the page's notice, and the 미리보기 strip's cycle. Called from
// main.swift; uses its check().
import Foundation

func runFaceTests() {
    faceStoreTests()
    facePoolTests()
    faceMoveTests()
    // The words are the catalog's (N9): these read them in Korean, as the user's Mac shows them.
    let (language, bundle) = (ArisTeamCopy.language, ArisTeamCopy.bundle)
    if let catalog = decisionCatalog(prefixes: ["team."]) { ArisTeamCopy.use("ko", in: catalog) } else { check(false, "words: the catalog reads") }
    faceWordsTests()
    faceStageTests()
    (ArisTeamCopy.language, ArisTeamCopy.bundle) = (language, bundle)
}

private func faceStore(_ body: (UserDefaults) -> Void) {
    let suite = testSuiteName("aris-face-tests")
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let saved = ArisFace.store
    ArisFace.store = defaults
    body(defaults)
    ArisFace.store = saved
    defaults.removePersistentDomain(forName: suite)
}

private func faceStoreTests() {
    check(ArisFace.choices == ["star", "clover", "cloud", "cat", "blob", "ghost", "pebble"], "face: seven to choose from, the star first")
    check(ArisCharacterLook.star == ArisCharacterLook(type: "star", colorHex: nil, shading: "fabric"), "face: the default is the fabric star")
    faceStore { defaults in
        check(ArisFace.current == .star && ArisCharacterLook.main == .star, "face: nothing picked is the star")
        var posted = 0
        let token = NotificationCenter.default.addObserver(forName: ArisFace.changed, object: nil, queue: nil) { _ in posted += 1 }
        ArisFace.set(ArisCharacterLook(type: "cat", colorHex: "#41c4ff", shading: "crisp"))
        check(ArisFace.current == ArisCharacterLook(type: "cat", colorHex: "#41C4FF", shading: "fabric") && ArisCharacterLook.main.type == "cat",
              "face: a pick is kept, read live by .main, its colour upper case, its shading always fabric")
        check(defaults.string(forKey: ArisFace.key) == "cat #41C4FF", "face: stored as plain text")
        ArisFace.set(ArisCharacterLook(type: "cat", colorHex: "#41C4FF", shading: "fabric"))
        check(posted == 1, "face: a change is announced once; the same face again is no change")
        ArisFace.set(ArisCharacterLook(type: "droid", colorHex: nil, shading: "fabric"))
        check(ArisFace.current == .star && posted == 2, "face: a type Aris can't wear falls back to the star")
        NotificationCenter.default.removeObserver(token)
        for raw in ["", "dragon", "cat #123456", "cat #41C4FF extra", "#41C4FF"] {
            defaults.set(raw, forKey: ArisFace.key)
            check(ArisFace.current == .star, "face: '\(raw)' (unknown, off-palette, junk) reads as the star")
        }
        defaults.set("cat #EAA06F", forKey: ArisFace.key)
        check(ArisFace.current == ArisCharacterLook(type: "cat", colorHex: nil, shading: "fabric"), "face: the type's own colour spelt out is its own")
        defaults.set("ghost", forKey: ArisFace.key)
        check(ArisFace.current == ArisCharacterLook(type: "ghost", colorHex: nil, shading: "fabric"), "face: a type alone is its own colour")
    }
    check(ArisFace.decode(ArisFace.encode(ArisCharacterLook(type: "pebble", colorHex: "#EB7575", shading: "fabric")))
          == ArisCharacterLook(type: "pebble", colorHex: "#EB7575", shading: "fabric"), "face: round-trips")
    check(ArisFace.colorChoices(for: "cat").count == 17 && ArisFace.colorChoices(for: "cat").first == .some(nil),
          "face: 17 colours (the type's own first), nine a row on the page")
}

private func facePoolTests() {
    check(ArisFace.pool(aris: "star") == ArisCharacterLook.teammateTypes, "pool: Aris the star leaves the six as they were")
    check(ArisFace.pool(aris: "cat") == ["clover", "cloud", "star", "blob", "ghost", "pebble"],
          "pool: the type Aris wears leaves and the star takes its place")
    for aris in ArisFace.choices {
        check(!ArisFace.pool(aris: aris).contains(aris) && ArisFace.pool(aris: aris).count == 6, "pool: never Aris's own type (\(aris))")
        check(!ArisFace.pickableTypes(aris: aris).contains(aris) && ArisFace.pickableTypes(aris: aris).count == 17,
              "pool: a teammate's picker offers every type but Aris's (\(aris))")
    }
    check(ArisFace.pickableTypes(aris: "cat").contains("star"), "pool: once Aris wears another face a teammate may pick the star")
    let names = ["코디", "Claude Code", "냥", "mail", "Researcher", "몽실", "a", "b", "쑥", "새 팀원"]
    for aris in ArisFace.choices {
        let face = ArisCharacterLook(type: aris, colorHex: nil, shading: "fabric")
        check(names.allSatisfy { ArisCharacterLook.forName($0, aris: face).type != aris }, "pool: no name is given Aris's type (\(aris))")
    }
    let cat = ArisCharacterLook(type: "cat", colorHex: nil, shading: "fabric")
    let kept = names.filter { ArisCharacterLook.forName($0, aris: .star).type != "cat" }
    check(kept.allSatisfy { ArisCharacterLook.forName($0, aris: cat) == ArisCharacterLook.forName($0, aris: .star) }
          && names.filter { ArisCharacterLook.forName($0, aris: .star).type == "cat" }.allSatisfy { ArisCharacterLook.forName($0, aris: cat).type == "star" },
          "pool: every other name keeps its face; only the ones that had Aris's type get the star")
    check(ArisCharacterLook.forName(ArisActivityTab.mainName, aris: cat) == cat, "pool: Aris's own rows wear its face")
    // The page's adding never hands out Aris's type, even when it is the first free one.
    let crowd = ["clover", "flower", "triangle", "square", "blob", "ghost", "circle", "drop"].enumerated().map { n, type in
        ArisTeammate(id: "m\(n)", name: "m\(n)", role: "", look: ArisCharacterLook(type: type, colorHex: nil, shading: "fabric"), brain: "codex", memoryFile: "")
    }
    check(ArisTeamEditing.adding(to: crowd, aris: ArisCharacterLook(type: "star", colorHex: nil, shading: "fabric")).last!.look.type == "droid"
          && ArisTeamEditing.adding(to: [], aris: ArisCharacterLook(type: "clover", colorHex: nil, shading: "fabric")).last!.look.type != "clover",
          "pool: a new teammate never gets Aris's type")
    check(ArisTeamEditing.rows([], aris: cat).first?.look == cat, "pool: the roster's Aris row wears its face")
}

private func faceMoveTests() {
    let cat = ArisCharacterLook(type: "cat", colorHex: "#EB7575", shading: "fabric")
    let codi = ArisTeammate(id: "claude-code", name: "코디", role: "Claude Code 담당", look: ArisCharacterLook(type: "cat", colorHex: "#41C4FF", shading: "crisp"),
                            brain: "claude", memoryFile: "")
    let mong = ArisTeammate(id: "mong", name: "몽실", role: "", look: ArisCharacterLook(type: "cloud", colorHex: nil, shading: "fabric"), brain: "codex", memoryFile: "")
    let (team, moved) = ArisFace.moving([codi, mong], to: cat)
    check(moved.map(\.id) == ["claude-code"] && team[0].look == ArisCharacterLook(type: "star", colorHex: nil, shading: "crisp") && team[1] == mong,
          "move: the teammate wearing Aris's new type gets the star (its shading kept); the others are untouched")
    check(ArisFace.moving([codi, mong], to: ArisCharacterLook(type: "blob", colorHex: nil, shading: "fabric")).moved.isEmpty,
          "move: nobody moves when nobody wears that type")
    // Back to the star: a teammate moved to the star earlier gets the face its name gives it, never the star.
    let starred = ArisFace.moving([codi], to: cat).team
    let back = ArisFace.moving(starred, to: .star)
    check(back.moved.count == 1 && back.team[0].look.type != "star" && ArisCharacterLook.teammateTypes.contains(back.team[0].look.type),
          "move: Aris back to the star moves a starred teammate onto its own face from the six")
    // Display: a stale file (or a figure already out) never shows Aris's type.
    check(ArisCharacterLook.of(teammateId: "claude-code", name: "코디", in: [codi], aris: cat).type == "star"
          && ArisCharacterLook.of(teammateId: "mong", name: "몽실", in: [mong], aris: cat) == mong.look
          && ArisCharacterLook.of(teammateId: nil, name: ArisActivityTab.mainName, in: [codi], aris: cat) == cat,
          "move: a teammate still stored with Aris's type shows the star; Aris shows its own face")
    let ghost = ArisCharacterLook(type: "ghost", colorHex: nil, shading: "fabric")
    check(ArisCharacterLook.of(teammateId: "claude-code", name: "Claude Code", in: [], aris: ghost).type == "star",
          "move: Claude Code's ghost before the list is in is the star when Aris wears the ghost")
    for aris in ArisFace.choices {
        let face = ArisCharacterLook(type: aris, colorHex: nil, shading: "fabric")
        let anyone = ArisCharacterLook.types.map { ArisCharacterLook(type: $0, colorHex: nil, shading: "fabric") }
        check(anyone.allSatisfy { ArisFace.shown($0, name: "누구", aris: face).type != aris }, "move: nothing a teammate shows is Aris's type (\(aris))")
    }
    check(ArisCharacterLook(type: "star", colorHex: nil, shading: "fabric").isPickable, "move: the agent stores a teammate's star")
}

private func faceWordsTests() {
    let codi = ArisTeammate(id: "c", name: "코디", role: "", look: ArisCharacterLook(type: "star", colorHex: nil, shading: "fabric"), brain: "", memoryFile: "")
    check(ArisFace.notice(moved: codi, aris: "cat") == "코디도 고양이였어요. 이제 코디는 별이에요.", "words: the mockup's notice")
    let mong = ArisTeammate(id: "m", name: "몽실", role: "", look: ArisCharacterLook(type: "cat", colorHex: nil, shading: "fabric"), brain: "", memoryFile: "")
    check(ArisFace.notice(moved: mong, aris: "star") == "몽실도 별이었어요. 이제 몽실은 고양이예요.", "words: the particles follow the last letter")
    check(ArisFace.noticeAction(moved: codi) == "코디 얼굴 고르기", "words: the notice's button")
    check(ArisFace.josa("Codi", "은", "는") == "Codi는" && ArisFace.josa("쑥", "은", "는") == "쑥은", "words: josa")
    check(ArisFace.choices.allSatisfy { ArisFace.name($0) != $0 } && ArisFace.name("star") == "별", "words: every face has a Korean name")
}

private func faceStageTests() {
    check(ArisFaceStage.Mode.allCases == [.rest, .listen, .work], "stage: rest, listening, working")
    check(ArisFaceStage.next(.rest) == .listen && ArisFaceStage.next(.listen) == .work && ArisFaceStage.next(.work) == .rest,
          "stage: 자동 plays them in turn")
    check(ArisFaceStage.interval == 2.2, "stage: 2.2 s each, as the mockup")
    check(ArisFaceStage.caption(.rest) == "쉴 때 · 카메라 옆에서 기다려요" && ArisFaceStage.caption(.listen) == "들을 때 · 띠가 넓어지고 고개를 들어요"
          && ArisFaceStage.caption(.work) == "일할 때 · 노치 아래 알약에서 일해요", "stage: the mockup's captions")
    check(ArisFaceStage.Pin.allCases.map(\.title) == ["자동", "쉴 때", "들을 때", "일할 때"], "stage: the segmented control's four")
    check(ArisFaceStage.mode(pin: .auto, tick: 4) == .listen && ArisFaceStage.mode(pin: .work, tick: 4) == .work,
          "stage: 자동 follows the clock; a pinned mode holds")
    check(ArisFaceStage.mode(pin: .auto, tick: 7, reduced: true) == .rest, "stage: 모션 줄이기 holds 자동 at rest")
    check(ArisFaceStage.notchWidth(.rest) == 150 && ArisFaceStage.notchWidth(.listen) == 270 && ArisFaceStage.notchHeight(.listen) == 32,
          "stage: the band widens to 270 × 32 while listening")
}
