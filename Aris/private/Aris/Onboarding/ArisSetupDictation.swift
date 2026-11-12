//
//  ArisSetupDictation.swift
//  Aris
//
//  The setup's 받아쓰기 page as rules. Two things:
//   · The one line under the practice note that brings in the model for more accurate dictation (the owner's pick 9-A,
//     2026-11-11). It used to be a card that dropped under the notch after the first question of any kind; now it is
//     asked where dictation is being tried. 받기 starts the small model's download (Wi-Fi only) and nothing waits for
//     it: the line itself shows how far it is, and dictation works meanwhile with macOS's own recognition. A Mac that
//     already has a model shows no line. The large model stays in Settings › AI services.
//   · The dictation key's name, read from the key Aris watches (ArisDictationKey.keyCode) in one place, so the page
//     never says a key that is not the one set.
//  Pure, so the tests run every state; ArisModelLineView and ArisDictationPage draw them.
//

import Foundation

enum ArisModelLine {
    enum Action: Equatable {
        /// 받기: start the download.
        case get
        /// 이어 받기: it was paused.
        case resume
        /// 다시 받기: it failed for something other than the network.
        case retry
    }

    struct Shown: Equatable {
        let title: String
        let detail: String
        let action: Action?
        /// How far the download is, 0…1, while one is under way (the line draws its bar); nil otherwise.
        let fraction: Double?
    }

    /// The model the line offers.
    static let offered = ArisSpeechModel.small

    /// The download's state as the line reads it. The downloader goes back to idle a few seconds after it finishes
    /// (its own card closes); on this page a model that came in here stays "ready", with nothing to press.
    static func lineState(_ state: ArisModelDownload, cameInHere: Bool) -> ArisModelDownload {
        state == .idle && cameInHere ? .done : state
    }

    /// `state`, `model`: the download as it is and the model it brings in. `installed`: a model is already on this Mac.
    static func shown(state: ArisModelDownload, model: ArisSpeechModel, installed: Bool, english: Bool) -> Shown? {
        let title = ArisSetupWords.modelTitle(english: english), name = model.name(english: english)
        switch state {
        case .idle:
            guard !installed else { return nil }
            let detail = "\(offered.name(english: english)) \(offered.sizeText(english: english)) · \(ArisSetupWords.modelWifi(english: english))"
            return Shown(title: title, detail: detail, action: .get, fraction: nil)
        case .running(let fraction):
            return Shown(title: title, detail: ArisSetupWords.modelComing(name, percent: state.percent, english: english), action: nil, fraction: fraction)
        case .waiting(let fraction):
            return Shown(title: title, detail: ArisSetupWords.modelWaiting(english: english), action: nil, fraction: fraction)
        case .paused(let fraction):
            return Shown(title: title, detail: ArisSetupWords.modelPaused(percent: state.percent, english: english), action: .resume, fraction: fraction)
        case .failed:
            return Shown(title: title, detail: ArisSetupWords.modelFailed(english: english), action: .retry, fraction: nil)
        case .done:
            return Shown(title: title, detail: ArisSetupWords.modelReady(name, english: english), action: nil, fraction: nil)
        }
    }
}

/// The key that dictates, as the page names it: the one set in Settings (ArisDictationKey.Choice), never a fixed one.
enum ArisDictationKeyName {
    /// The key's name for a sentence ("오른쪽 ⌥", "the right ⌥", "fn"). A code that is no modifier key is called what
    /// it is for, never by another key's name.
    static func name(keyCode: UInt16 = ArisDictationKey.Choice.current.keyCode, english: Bool) -> String {
        guard let key = ArisDictationKey.Choice.key(keyCode) else { return english ? "the dictation key" : "받아쓰기 키" }
        let name = key.name(english: english)
        return english && key.right != nil ? "the \(name)" : name
    }
}

// MARK: - The page's words

extension ArisSetupWords {
    /// The page's body, with the dictation key as it is set.
    static func dictateLead(key: String = ArisDictationKeyName.name(english: english), english: Bool = english) -> String {
        say("어느 앱에서든 \(key)를 누른 채 말하고 떼면, 다듬어서 써 줘요.", "In any app, hold \(key) and talk. Let go, and I'll type it, tidied up.", english)
    }

    static func modelTitle(english: Bool = english) -> String { say("더 정확하게 받아쓰기", "More accurate dictation", english) }
    static func modelWifi(english: Bool = english) -> String { say("Wi-Fi에서만 받아요", "downloads on Wi-Fi only", english) }
    static func modelGet(english: Bool = english) -> String { say("받기", "Download", english) }
    static func modelResume(english: Bool = english) -> String { say("이어 받기", "Resume", english) }
    static func modelRetry(english: Bool = english) -> String { say("다시 받기", "Try again", english) }
    static func modelAction(_ action: ArisModelLine.Action, english: Bool = english) -> String {
        switch action {
        case .get: modelGet(english: english)
        case .resume: modelResume(english: english)
        case .retry: modelRetry(english: english)
        }
    }
    /// `name`: the model's name ("작은 모델", "Small model").
    static func modelComing(_ name: String, percent: Int, english: Bool = english) -> String {
        say("\(name) 받는 중 \(percent)% · 그동안에도 쓸 수 있어요", "\(name) downloading, \(percent)% · dictation works meanwhile", english)
    }
    static func modelWaiting(english: Bool = english) -> String {
        say("Wi-Fi에 연결되면 이어서 받아요 · 그동안에도 쓸 수 있어요", "Goes on once you're on Wi-Fi · dictation works meanwhile", english)
    }
    static func modelPaused(percent: Int, english: Bool = english) -> String { say("잠시 멈췄어요 · \(percent)%", "Paused at \(percent)%", english) }
    static func modelFailed(english: Bool = english) -> String { say("받지 못했어요 · 곧 다시 해 볼게요", "Couldn't download it · I'll try again soon", english) }
    static func modelReady(_ name: String, english: Bool = english) -> String { say("\(name) 준비 끝", "\(name) ready", english) }
}
