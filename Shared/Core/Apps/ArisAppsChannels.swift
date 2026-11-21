//
//  ArisAppsChannels.swift
//  Shared/Core/Apps
//
//  Which channel runs a command, with macOS permission prompts counted as a cost (the owner: the number of approvals a
//  person must click is the real problem). The Accessibility channels (menu bar, the tree, the engine) need only the
//  one Accessibility grant Aris already has; Apple Events to an app bring up that app's Automation prompt the first
//  time and fail silently once denied. So the scripting dictionary comes first only when its grant is already there;
//  otherwise every channel that needs no new permission is tried first, and the scripting dictionary is used only
//  when nothing else can do it, after one short sentence saying why the prompt is coming (said once per app, and never
//  in a background task, which cannot be interrupted by a prompt). What each app's channels did is recorded, so the
//  same prompt is never caused twice. Pure.
//

import Foundation

extension ArisApps {
    /// The Automation grant for one target app, as AEDeterminePermissionToAutomateTarget answers without asking.
    enum Grant: String, Codable, Sendable {
        case granted
        case denied
        /// Asking would bring up the prompt (errAEEventWouldRequireUserConsent).
        case notAsked = "not-asked"
        /// The app isn't running, so it can't be asked about yet.
        case unknown

        /// The channel book's word for the permission layer's reading (ArisAutomationAccess.state(of:), never asking).
        init(_ state: ArisPermissionState) {
            switch state {
            case .granted: self = .granted
            case .denied: self = .denied
            case .notAsked: self = .notAsked
            case .unknown: self = .unknown
            }
        }
    }

    /// What is known about one app's channels.
    struct AppChannels: Codable, Equatable, Sendable {
        var automation: Grant = .unknown
        /// The one sentence before its prompt has been said.
        var noticeSaid = false
        /// Channels that failed for this app (channel → why), and the version they failed at.
        var failed: [String: String] = [:]
        var worked: [String] = []
        var versionKey = ""
    }

    struct ChannelBook: Codable, Equatable, Sendable {
        var apps: [String: AppChannels] = [:]

        func record(_ bundle: String) -> AppChannels { apps[bundle.lowercased()] ?? AppChannels() }

        func updating(_ bundle: String, _ change: (inout AppChannels) -> Void) -> ChannelBook {
            var copy = self
            var record = copy.record(bundle)
            change(&record)
            copy.apps[bundle.lowercased()] = record
            return copy
        }

        /// A new version of the app: what failed before is tried again (the grant stays: macOS keeps it per app).
        func seeing(_ bundle: String, versionKey: String) -> ChannelBook {
            guard record(bundle).versionKey != versionKey else { return self }
            return updating(bundle) { record in
                record.failed = [:]
                record.worked = []
                record.versionKey = versionKey
            }
        }

        func noting(_ bundle: String, grant: Grant) -> ChannelBook {
            // A known answer is never replaced by "can't tell" (the app quit since).
            guard grant != .unknown || record(bundle).automation == .unknown else { return self }
            return updating(bundle) { $0.automation = grant }
        }

        func noting(_ bundle: String, channel: Channel, worked: Bool, why: String = "") -> ChannelBook {
            updating(bundle) { record in
                if worked {
                    record.failed[channel.rawValue] = nil
                    if !record.worked.contains(channel.rawValue) { record.worked.append(channel.rawValue) }
                } else {
                    record.failed[channel.rawValue] = why.isEmpty ? "failed" : why
                }
            }
        }

        func notingNoticeSaid(_ bundle: String) -> ChannelBook { updating(bundle) { $0.noticeSaid = true } }
    }

    enum Choice {
        struct Step: Equatable, Sendable {
            var command: Command
            /// Running it brings up a macOS permission prompt (an Automation grant not given yet).
            var prompts: Bool
        }

        struct Plan: Equatable, Sendable {
            var steps: [Step]
            /// Why nothing at all can run (every channel failed, was denied or would prompt in a background task).
            var blocked: String?
        }

        /// The cost of a channel: a permission prompt is the dearest thing there is short of not working.
        static func cost(_ channel: Channel, grant: Grant) -> Int? {
            switch channel {
            case .sdef:
                switch grant {
                case .granted: return 0
                case .denied: return nil
                case .notAsked, .unknown: return 10
                }
            case .menu: return 1
            case .url, .document: return 1
            case .shortcut: return 2
            case .service: return 3
            case .engine: return 6
            case .intent: return nil
            }
        }

        /// The order to try a command in: `target` and the same command on other channels (`alternatives`).
        /// `background`: a task nobody is watching; a step that would prompt is left out of it.
        static func plan(target: Command, alternatives: [Command], record: AppChannels, background: Bool) -> Plan {
            var seen = Set<String>(), candidates: [Command] = []
            for command in [target] + alternatives where !seen.contains(command.id) {
                seen.insert(command.id)
                candidates.append(command)
            }
            let order = Dictionary(uniqueKeysWithValues: Commands.channelOrder.enumerated().map { ($1, $0) })
            var reasons: [String] = []
            let ranked = candidates.compactMap { command -> (Command, Int)? in
                guard command.runnable, let cost = cost(command.channel, grant: record.automation) else {
                    if command.channel == .sdef { reasons.append("sdef: Automation for this app was turned off") }
                    return nil
                }
                if let why = record.failed[command.channel.rawValue] { reasons.append("\(command.channel.rawValue): \(why)"); return nil }
                if command.channel == .menu, command.enabled == false { reasons.append("menu: “\(command.title)” is greyed out now"); return nil }
                if background, command.channel == .sdef, record.automation != .granted {
                    reasons.append("sdef: it would ask for permission, and a background task never brings up a prompt")
                    return nil
                }
                return (command, cost)
            }.sorted { left, right in
                if left.1 != right.1 { return left.1 < right.1 }
                if (left.0.id == target.id) != (right.0.id == target.id) { return left.0.id == target.id }
                return (order[left.0.channel] ?? 9) < (order[right.0.channel] ?? 9)
            }
            let steps = ranked.map { Step(command: $0.0, prompts: $0.0.channel == .sdef && record.automation != .granted) }
            return Plan(steps: steps, blocked: steps.isEmpty ? (reasons.isEmpty ? "no channel can run it" : reasons.joined(separator: "; ")) : nil)
        }

        enum Next: Equatable, Sendable {
            case run(Step)
            /// Say this sentence first; run the step when called again with the go-ahead.
            case sayFirst(notice: String, noticeEnglish: String, step: Step)
            case done
        }

        /// The step to take at `index`: a prompting step waits for its sentence unless it was said for this app already
        /// or the caller says it was just said (`goAhead`).
        static func next(_ plan: Plan, at index: Int, record: AppChannels, appName: String, goAhead: Bool) -> Next {
            guard index < plan.steps.count else { return .done }
            let step = plan.steps[index]
            if step.prompts, !goAhead, !record.noticeSaid {
                let words = notice(appName)
                return .sayFirst(notice: words.ko, noticeEnglish: words.en, step: step)
            }
            return .run(step)
        }

        /// The one sentence before an Automation prompt.
        static func notice(_ appName: String) -> (ko: String, en: String) {
            ("\(appName)에 직접 명령하려면 macOS가 한 번 허락을 물어요. 허용하면 다음부터는 묻지 않아요.",
             "To give \(appName) this command directly, macOS will ask you once to allow it; after that it won't ask again.")
        }

        /// How an app's content is read, cheapest first: its Accessibility tree, its scripting dictionary when that grant
        /// is already there, and a picture of the window only when the tree is empty.
        static func readOrder(grant: Grant) -> [String] { grant == .granted ? ["ax", "sdef", "vision"] : ["ax", "vision"] }
    }
}
