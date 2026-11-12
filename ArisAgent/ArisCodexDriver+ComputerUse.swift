//
//  ArisCodexDriver+ComputerUse.swift
//  aris-agent
//
//  Computer use's pieces for the Codex driver: a step's app and card (told only when both of the runtime's names
//  agree), and the apps a cua_repl call's code names. The user's per-app "computer use OK" is the conversation's
//  ArisComputerUseLedger, shared with every brain's `aris-tools desktop`.
//

import Foundation

extension ArisCodexDriver {
    /// Said on a message card when the code picks the chat without naming it.
    static let blindChat = "대화는 코드가 직접 골라요 (이름이 코드에 없어요)"

    /// The one card the user taps for code in a chat app, titled from the chat app: every text it types (quoted, control
    /// characters shown escaped), the chat it picks by name (or a warning that it picks blind), any other app it names.
    /// The whole code is under 전체 보기.
    static func messageCard(_ step: ArisJudgedStep) -> (title: String, detail: String) {
        let chat = step.targets.first(where: \.sending)?.name ?? "?"
        let typed = (step.program?.typedStrings ?? []).map { ArisJSValue.string($0).text }
        let labels = (step.program?.selections ?? []).map { ArisJSValue.string($0).text }
        let apps = step.targets.count > 1 ? "\n앱: " + step.targets.map(\.name).joined(separator: ", ") : ""
        let detail = "입력하는 글:\n" + (typed.isEmpty ? "(없음)" : typed.joined(separator: "\n"))
            + "\n" + (labels.isEmpty ? blindChat : "코드가 고른 대화: " + labels.joined(separator: ", ")) + apps
        return ("\(chat)에서 보내기", detail)
    }

    /// A computer-use step's app and card. The card is named from the app the runtime named (its bundle's own name),
    /// showing the other name when they differ, and says what the turn asked for.
    struct ComputerUseApp {
        let name: String
        /// Set only when both names agree on one known app: what the user's yes is remembered by.
        let bundle: String?
        let never: Bool
        let browser: Bool
        let title: String
        let detail: String
    }

    static func computerUseApp(meta: [String: Any], tool: String, request: String) -> ComputerUseApp {
        let shown = (meta["tool_params_display"] as? [[String: Any]])?.first { $0["name"] as? String == "app" }?["value"] as? String
        let named = (meta["tool_params"] as? [String: Any])?["app"] as? String
        let namedBundle = named.flatMap(ArisAppIdentity.bundle(for:))
        let bundle = ArisAppIdentity.identity(shown: shown, named: named)
        let asked = request.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if tool == "start_audio_recording", named == nil {
            let detail = "컴퓨터 소리를 녹음해요" + (asked.isEmpty ? "" : "\n요청: \(asked.prefix(80))")
            return ComputerUseApp(name: "녹음", bundle: nil, never: false, browser: false, title: "녹음", detail: detail)
        }
        let name = namedBundle.flatMap(ArisAppIdentity.name(ofBundle:)) ?? named ?? shown ?? "?"
        // A path is never resolved, but its file's name still counts for what's never allowed.
        let pathName = named.map { ($0 as NSString).lastPathComponent }.map { $0.hasSuffix(".app") ? String($0.dropLast(4)) : $0 }
        let names: [String?] = [name, shown, named, namedBundle, pathName]
        let never = ArisRiskPolicy.computerUseIsNever(names)
        let browser = names.compactMap { $0 }.contains { ArisRiskPolicy.isBrowser(name: $0, bundle: $0, webHandlers: ArisAppIdentity.webHandlers) }
        let label = shown.map { $0.lowercased() == name.lowercased() ? "" : " · 표시: \($0)" } ?? ""
        let purpose = asked.isEmpty ? "" : "\(name)에서: \(asked.prefix(80))\n"
        return ComputerUseApp(name: name, bundle: bundle, never: never, browser: browser, title: "\(name) 사용" + label,
                              detail: purpose + "화면을 보고 \(ArisJosa.attach(name, "을", "를")) 직접 클릭하고 입력해요")
    }

    /// An app the code names, resolved, and whether code for it may never be judged.
    static func target(_ name: String) -> ArisJSTarget {
        let bundle = ArisAppIdentity.bundle(for: name)
        let names: [String?] = [name, bundle]
        let offLimits = ArisRiskPolicy.computerUseIsNever(names)
            || names.compactMap { $0 }.contains { ArisRiskPolicy.isBrowser(name: $0, bundle: $0, webHandlers: ArisAppIdentity.webHandlers) }
        return ArisJSTarget(name: name, bundle: bundle, offLimits: offLimits, sending: ArisRiskPolicy.isSendingApp(bundle: bundle, name: name))
    }
}
