//
//  ArisHelperInstallWords.swift
//  Aris
//
//  What the user is told about the helper's install, and when. The helper (aris-agent) lives inside Aris.app and the
//  app installs it by itself at launch (ArisHelperInstall), so on a good day nothing is said at all. A line comes only
//  when there is something for the user to do:
//   · the app is somewhere its helper can't run from (opened straight from a download, on a disk image, in the Trash):
//     "Move Aris to the Applications folder, then open it again", with a button that shows the app in Finder;
//   · the helper didn't start: the line that already has the restart button;
//   · once, after the switch from an install made the old way, and only for someone whose old helper could read
//     Messages and Mail: Full Disk Access needs one switch on "Aris", with the button that opens that list. Accessibility
//     and Screen Recording keep working through the switches "Aris" already has, and folders and Automation are asked
//     by macOS, naming Aris, when first used: nothing is said about those in advance;
//   · Aris's own Accessibility switch is on but the helper says its own is off (macOS no longer counts the helper as
//     the app): one log line, and where typing fails for it, the reason with the button that opens the list.
//   · once, to an install that had the old helper (the switch happens now, or Aris was already set up when this build
//     first ran: Aris cannot read macOS's lists, so every such install is told once): the old "aris-agent" rows in the
//     privacy lists still grant whatever is put back at the old path (security review 4, M4), so they are better
//     removed. The line's button opens the lists one after another, by the names this macOS shows.
//  Pure (tested).
//

import Foundation

enum ArisHelperInstallWords {
    /// Set once the Full Disk Access line has been said after the switch.
    static let diskSaidKey = "arisDiskAccessAfterSwitchSaid"

    static func move(english: Bool = ArisUIWords.english) -> String {
        ArisUIWords.text("Aris를 응용 프로그램 폴더로 옮긴 다음 다시 열어 주세요.", "Move Aris to the Applications folder, then open it again.", english: english)
    }

    static func diskAfterSwitch(english: Bool = ArisUIWords.english) -> String {
        ArisUIWords.text("메시지와 메일을 계속 읽으려면 \(ArisFix.Pane.disk.title(english: false)) 목록에서 Aris를 한 번 켜 주세요.",
                         "To keep reading Messages and Mail, turn on Aris once in Full Disk Access.", english: english)
    }

    /// Typing failed because the helper may not use Accessibility although Aris's switch is on.
    static func accessibilityLost(english: Bool = ArisUIWords.english) -> String {
        ArisUIWords.text("입력하지 못했어요. \(ArisFix.Pane.accessibility.title(english: false)) 목록에서 Aris를 껐다가 다시 켜 주세요.",
                         "I couldn't type that. Turn Aris off and on again in the \(ArisFix.Pane.accessibility.title(english: true)) list.", english: english)
    }

    /// Typing failed because Accessibility is simply off.
    static func accessibilityOff(english: Bool = ArisUIWords.english) -> String {
        ArisUIWords.text("입력하지 못했어요. \(ArisFix.Pane.accessibility.title(english: false)) 목록에서 Aris를 켜 주세요.",
                         "I couldn't type that. Turn on Aris in the \(ArisFix.Pane.accessibility.title(english: true)) list.", english: english)
    }

    /// The line for a dictation the helper would not type for want of Accessibility.
    static func notTyped(appSwitchOn: Bool, english: Bool = ArisUIWords.english) -> String {
        appSwitchOn ? accessibilityLost(english: english) : accessibilityOff(english: english)
    }

    /// What is said in the notch after the install at launch; nil when there is nothing for the user to do.
    static func atLaunch(_ outcome: ArisAgentInstallOutcome, english: Bool = ArisUIWords.english) -> String? {
        switch outcome {
        case .running, .started, .switched: nil
        // Another program sat under the helper's label and was replaced (security review 4, M7): said once, here.
        case .replaced: replaced(english: english)
        case .refused(.changed): changed(english: english)
        case .refused(.older): older(english: english)
        case .refused(.linkedFolder): linkedFolder(english: english)
        // A place others can write, or a second copy outside Applications: the same thing to do.
        case .refused(.translocated), .refused(.readOnly), .refused(.trash), .refused(.sharedPlace), .refused(.notInApplications): move(english: english)
        // A build with no helper inside it is said by ArisPrerequisites (the same line the Settings window shows).
        case .refused(.noHelper), .refused(.shape): nil
        case .failed: ArisAgentCopy.notRunning(english: english)
        }
    }

    // MARK: The old helper's rows (security review 4, M4)

    /// Set at the first launch of a build that knows about the old rows: from then on only a switch makes the line due.
    static let oldRowsCheckedKey = "arisOldHelperRowsChecked"
    /// The line is due and has not been said yet (it waits for a quiet notch, over launches if need be).
    static let oldRowsDueKey = "arisOldHelperRowsDue"
    /// It has been said: never again.
    static let oldRowsSaidKey = "arisOldHelperRowsSaid"

    static func oldRows(english: Bool = ArisUIWords.english) -> String {
        ArisUIWords.text("예전 도우미 줄(aris-agent)이 남아 있어요. 지금은 쓰지 않으니 지워 두는 게 안전해요.",
                         "The old helper's rows (aris-agent) are still there. Aris no longer uses them, so it is safer to remove them.", english: english)
    }

    /// The lists the old rows are in, in the order the button opens them.
    static let oldRowsLists: [ArisFix.Pane] = [.accessibility, .screen, .disk]

    /// Whether the line becomes due at this launch: the install is switched now, or this is the first launch of a
    /// build that knows about the rows on a Mac where Aris was already set up (it had the old helper, or may have).
    /// A new install never had the rows and is never told.
    static func oldRowsBecomeDue(_ outcome: ArisAgentInstallOutcome, checkedBefore: Bool, wasSetUp: Bool) -> Bool {
        outcome == .switched || (!checkedBefore && wasSetUp && outcome.isUp)
    }

    /// Whether it is said now: due, never said, and nothing else is in the notch.
    static func oldRowsSaidNow(due: Bool, saidBefore: Bool) -> Bool { due && !saidBefore }

    static func replaced(english: Bool = ArisUIWords.english) -> String {
        ArisUIWords.text("Aris의 도우미 자리에 다른 프로그램이 등록돼 있어서 바꿨어요.",
                         "Another program was registered in the place of Aris's helper, so Aris replaced it.", english: english)
    }

    static func older(english: Bool = ArisUIWords.english) -> String {
        ArisUIWords.text("지금 쓰는 Aris가 이것보다 새 빌드라서, 이 Aris로 바꾸지 않았어요.",
                         "The Aris in use is a newer build than this one, so this one did not take its place.", english: english)
    }

    static func linkedFolder(english: Bool = ArisUIWords.english) -> String {
        ArisUIWords.text("Aris의 폴더(~/.config/aris)가 다른 곳으로 연결돼 있어서 도우미를 켜지 않았어요.",
                         "Aris's folder (~/.config/aris) is a link to somewhere else, so its helper was not started.", english: english)
    }

    static func changed(english: Bool = ArisUIWords.english) -> String {
        ArisUIWords.text("이 Aris는 설치된 뒤에 바뀌어서 도우미를 켜지 않았어요. Aris를 다시 설치해 주세요.",
                         "This copy of Aris was changed after it was installed, so its helper was not started. Install Aris again.", english: english)
    }

    /// Whether the Full Disk Access line is due: the install was switched from the old way, the old helper could read
    /// Messages and Mail, the one inside the app can't yet, and it hasn't been said before. Anything not known is a no.
    static func diskLineDue(_ outcome: ArisAgentInstallOutcome, hadBefore: Bool?, hasNow: Bool?, saidBefore: Bool) -> Bool {
        outcome == .switched && hadBefore == true && hasNow == false && !saidBefore
    }

    /// The sign that macOS's mapping of the helper to the app changed: Aris's switch on, the helper's own answer off.
    static func mappingLost(appSwitchOn: Bool, helperSays: Bool?) -> Bool { appSwitchOn && helperSays == false }

    static let mappingLostLog = "accessibility: Aris's switch is on but the helper says its own is off (macOS no longer counts the helper inside the app as Aris?)"
}
