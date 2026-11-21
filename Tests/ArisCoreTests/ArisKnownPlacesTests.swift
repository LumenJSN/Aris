import XCTest
@testable import ArisCore

/// Tenth VM run, items 2 and 5: known places by name in both languages, an invented home refused, and every way of
/// saying "the selected file" wanting the files.
final class ArisKnownPlacesTests: XCTestCase {
    private let home = "/Users/admin"
    private func resolve(_ said: String) -> ArisKnownPlaces.Resolved {
        ArisKnownPlaces.resolve(said, home: home, exists: { ["/Users/admin", "/Users/Shared"].contains($0) })
    }

    func testNamesInBothLanguages() {
        let table = ["다운로드": "/Users/admin/Downloads", "다운로드 폴더": "/Users/admin/Downloads", "Downloads": "/Users/admin/Downloads",
                     "문서": "/Users/admin/Documents", "documents folder": "/Users/admin/Documents", "바탕화면": "/Users/admin/Desktop",
                     "바탕 화면": "/Users/admin/Desktop", "desktop": "/Users/admin/Desktop", "홈": "/Users/admin", "home": "/Users/admin",
                     "응용 프로그램": "/Applications", "applications": "/Applications", "사진": "/Users/admin/Pictures", "음악": "/Users/admin/Music",
                     "동영상": "/Users/admin/Movies", "휴지통": "/Users/admin/.Trash"]
        for (said, path) in table { XCTAssertEqual(resolve(said), .path(path), said) }
    }

    func testPaths() {
        XCTAssertEqual(resolve("~"), .path("/Users/admin"))
        XCTAssertEqual(resolve("~/Downloads"), .path("/Users/admin/Downloads"))
        XCTAssertEqual(resolve("/Users/admin/Desktop/a.txt"), .path("/Users/admin/Desktop/a.txt"))
        XCTAssertEqual(resolve("/Users/Shared/a.txt"), .path("/Users/Shared/a.txt"))
        XCTAssertEqual(resolve("/tmp/a.txt"), .path("/tmp/a.txt"))
    }

    func testAnInventedHomeIsRefused() {
        XCTAssertEqual(resolve("/Users/me/Downloads"), .noSuchUser("me"))
        XCTAssertEqual(resolve("/Users/username"), .noSuchUser("username"))
        let line = ArisKnownPlaces.noSuchUserLine("me", home: home)
        XCTAssertTrue(line.contains("/Users/admin") && line.contains("~/Downloads"))
    }

    func testWhatIsNoPlace() {
        for said in ["", "보고서", "Downloads/setup.command", "Desktop/../x", "downloadsx", "문서들 정리"] { XCTAssertEqual(resolve(said), .unknown, said) }
    }

    func testSelectedFileWords() {
        for words in ["선택한 파일 이름을 new-name.txt로 바꿔 줘", "선택된 파일 이름 바꿔 줘", "고른 파일 버려 줘", "지금 고른 파일 이름 알려 줘",
                      "골라 놓은 파일 보여 줘", "이 파일 이름 바꿔 줘", "rename the selected file", "move these files", "rename the file I selected"] {
            let pointing = ArisFocusWords.parse(words)
            XCTAssertTrue(pointing.points, words)
            XCTAssertEqual(pointing.wants, .file, words)
        }
        XCTAssertFalse(ArisFocusWords.parse("파일 선택하는 법 알려 줘").points)
        XCTAssertTrue(ArisGrounding.pointsAtFocus("지금 고른 파일 이름 바꿔 줘"))
        XCTAssertFalse(ArisGrounding.pointsAtFocus("메뉴 고르는 중"))
    }
}
