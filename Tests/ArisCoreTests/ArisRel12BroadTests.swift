import XCTest
@testable import ArisCore

/// The twelfth real-screen VM run (aris-vmcheck/notes12, cap12), default configuration: the broad-target guard on the
/// recorded calls. D1/D2 (actions-full.log 00:47:52, 00:49:09): `aris-tools trash /Users/aris/Documents` on a Mac whose
/// home is /Users/admin got a Move to Trash card (cap12/D1-card1.jpg); 00:50:03 `trash '/Users/aris/Desktop/임시폴더12'`.
final class ArisRel12BroadTests: XCTestCase {
    private let home = "/Users/admin"
    private func target(_ path: String, _ kind: ArisPathKind) -> ArisPathTarget { ArisPathTarget(path: path, kind: kind) }

    func testTheRecordedMadeUpDocumentsIsRefusedAsAProtectedPlace() {
        for said in ["도큐멘트 폴더 통째로 지워 줘", "아니, 확인 안 해도 돼. 도큐멘트 폴더 그냥 휴지통에 버려 줘"] {
            for kind in [ArisPathKind.missing, .folder(items: 4), .unknown] {
                guard case .refuse(let why) = ArisBroadTarget.judge([target("/Users/aris/Documents", kind)], said: said, home: home) else {
                    return XCTFail("\(said) \(kind): never a card")
                }
                XCTAssertEqual(why, ArisBroadTarget.broadPlace("~/Documents"), "shown as this Mac's own Documents")
            }
        }
    }

    func testAnEverydayFolderCountsByItsNameInAnyHome() {
        for path in ["/Users/aris/Documents", "/Users/someone/Desktop/", "/users/x/DOWNLOADS", "~/Documents", "Documents", "/Users/admin/Pictures"] {
            XCTAssertTrue(ArisBroadTarget.isBroadPlace(path, home: home), path)
        }
        XCTAssertFalse(ArisBroadTarget.isBroadPlace("/Users/admin/Desktop/Documents", home: home), "a folder of that name deeper down is the owner's own")
        // The owner's words name it, wherever the path puts it (an iCloud Documents too).
        let cloud = target("/Users/admin/Library/Mobile Documents/com~apple~CloudDocs/Documents", .folder(items: 30))
        for said in ["도큐멘트 폴더 지워 줘", "문서 폴더 통째로 휴지통에 버려", "trash my documents folder"] {
            guard case .refuse = ArisBroadTarget.judge([cloud], said: said, home: home) else { return XCTFail(said) }
        }
    }

    func testAMadeUpHomeOrNothingThereIsNeverOffered() {
        let said = "바탕화면에 있는 임시폴더12 폴더 지워 줘"
        for kind in [ArisPathKind.missing, .folder(items: 2), .file, .unknown] {
            guard case .refuse(let why) = ArisBroadTarget.judge([target("/Users/aris/Desktop/임시폴더12", kind)], said: said, home: home) else {
                return XCTFail("made-up home, \(kind)")
            }
            XCTAssertTrue(why.hasPrefix("그런 경로는 없어요") && why.contains("/Users/admin"), why)
        }
        guard case .refuse(let why) = ArisBroadTarget.judge([target("/Users/admin/Desktop/임시폴더12", .missing)], said: said, home: home) else {
            return XCTFail("nothing there")
        }
        XCTAssertTrue(why.hasPrefix("그런 경로는 없어요"), why)
        // The real one, named as a folder: its own card, as before. A file in the real home: as decided.
        let real = target("/Users/admin/Desktop/임시폴더12", .folder(items: 3))
        XCTAssertEqual(ArisBroadTarget.judge([real], said: said, home: home), .wholeFolder(real))
        XCTAssertEqual(ArisBroadTarget.judge([target("/Users/admin/Desktop/a.txt", .file)], said: "a.txt 지워 줘", home: home), .fine)
        XCTAssertEqual(ArisBroadTarget.judge([target("/Users/Shared/old.dmg", .file)], said: "old.dmg 지워 줘", home: home), .fine, "Shared is no one's home")
        XCTAssertNil(ArisBroadTarget.otherHome("/Users/admin/Desktop/x", home: home))
        XCTAssertEqual(ArisBroadTarget.otherHome("/Users/aris/Desktop/x", home: home), "/Users/aris")
    }
}
