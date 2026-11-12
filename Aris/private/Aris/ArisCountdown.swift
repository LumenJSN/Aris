//
//  ArisCountdown.swift
//  Aris
//
//  A dictated message's countdown in the confirm card (the owner's pick C, mockups/countdown-card): a 14-point ring beside
//  보내기 empties clockwise from 12 o'clock over ArisConfirmReply.countdownSeconds; with Reduce Motion it drops a step
//  each whole second instead of sweeping. Its words come from Aris/Localizable.xcstrings in Korean and English, in the
//  app's language (Korean when it is neither, as ArisTeamCopy picks it). The English defaults stand in only where no
//  catalog is bundled (the tests).
//

import Foundation

enum ArisCountdown {
    /// How much of the ring is left `elapsed` seconds in: all of it until the countdown starts (nil), none once it ran out.
    static func remaining(elapsed: TimeInterval?, stepped: Bool) -> Double {
        guard let elapsed else { return 1 }
        let counted = stepped ? elapsed.rounded(.down) : elapsed
        return 1 - min(1, max(0, counted / Double(ArisConfirmReply.countdownSeconds)))
    }
}

enum ArisCountdownCopy {
    static let languages: Set<String> = ["ko", "en"]

    /// The language, chosen once: the app's one UI language (ArisUILanguage).
    nonisolated(unsafe) static var language: String = ArisUILanguage.code
    nonisolated(unsafe) static var bundle: Bundle = lproj(language, in: .main)

    static func lproj(_ language: String, in bundle: Bundle) -> Bundle {
        bundle.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? bundle
    }

    static var locale: Locale { Locale(identifier: language) }
    static var korean: Bool { language == "ko" }

    /// Picks the language again (the offscreen renders).
    static func use(_ code: String, in main: Bundle = .main) {
        language = code
        bundle = lproj(code, in: main)
    }

    static var title: String { String(localized: "countdown.title", defaultValue: "Send message", bundle: bundle, locale: locale, comment: "Dictated message card: its title") }
    static var to: String { String(localized: "countdown.to", defaultValue: "To", bundle: bundle, locale: locale, comment: "Dictated message card: the recipient's label") }
    static var message: String { String(localized: "countdown.message", defaultValue: "Message", bundle: bundle, locale: locale, comment: "Dictated message card: the message's label") }
    static var hint: String { String(localized: "countdown.hint", defaultValue: "Say “cancel” to stop", bundle: bundle, locale: locale, comment: "Dictated message card: how to stop it by voice") }
    static var cancel: String { String(localized: "countdown.cancel", defaultValue: "Cancel", bundle: bundle, locale: locale, comment: "Dictated message card: stops the countdown") }
    static var send: String { String(localized: "countdown.send", defaultValue: "Send", bundle: bundle, locale: locale, comment: "Dictated message card: sends at once") }
    static var notSent: String { String(localized: "countdown.notsent", defaultValue: "Not sent", bundle: bundle, locale: locale, comment: "Dictated message card, stopped") }
    static var cancelled: String { String(localized: "countdown.cancelled", defaultValue: "Cancelled", bundle: bundle, locale: locale, comment: "Dictated message card, stopped: the note on the right") }

    /// "엄마에게 ‘곧 갈게’ 보내는 중…": what the card says once the countdown let the message go. The app only hands the
    /// yes to the agent; whether Messages really sent it is known later and told in the answer, so the card never says
    /// "보냈어요" by itself.
    static func sending(to: String, message: String) -> String {
        String(localized: "countdown.sending", defaultValue: "Sending ‘\(message)’ to \(to)…", bundle: bundle, locale: locale,
               comment: "Dictated message card, let go and on its way: the message, the recipient")
    }

    /// "엄마에게 ‘곧 갈게’를 보냈어요": the Korean object particle follows the message's last syllable. For a send that
    /// is known to have gone out (the card itself doesn't know: see `sending`).
    static func sent(to: String, message: String) -> String {
        let particle = korean ? objectParticle(after: message) : ""
        return String(localized: "countdown.sent", defaultValue: "Sent ‘\(message)’\(particle) to \(to)", bundle: bundle, locale: locale,
                      comment: "Dictated message card, sent: the message, its Korean particle (empty in English), the recipient")
    }

    /// 을 after a final consonant, else 를 (anything not Hangul counts as a vowel).
    static func objectParticle(after text: String) -> String {
        guard let last = text.unicodeScalars.last(where: { CharacterSet.alphanumerics.contains($0) }),
              (0xAC00...0xD7A3).contains(last.value) else { return "를" }
        return (last.value - 0xAC00) % 28 == 0 ? "를" : "을"
    }
}
