import XCTest
@testable import ArisCore

/// The eleventh VM run, E2 (aris-vmcheck/notes11/E2.log): "router skipped: Failure(message: "deepseek auth:
/// Authentication Fails, Your api key: ****11ab is invalid (request_id: 0918…)"" went to the unified log as it came.
final class ArisProviderWordsTests: XCTestCase {
    func testTheRecordedLineLosesItsKeyCharactersAndRequestId() {
        let recorded = #"Failure(message: "deepseek auth: Authentication Fails, Your api key: ****11ab is invalid (request_id: 09185337-7ddb-42a2-b619-5af39a7b4459)", status: nil)"#
        let logged = ArisProviderWords.loggable(recorded)
        XCTAssertFalse(logged.contains("11ab"), logged)
        XCTAssertFalse(logged.contains("09185337"), logged)
        XCTAssertTrue(logged.contains("deepseek auth"), logged)
    }

    func testOtherShapesOfAKeyAreMaskedToo() {
        for (text, secret) in [("Incorrect API key provided: sk-abc***********wxyz.", "wxyz"), ("invalid x-api-key \"abcd1234\"", "abcd1234"),
                               ("token=eyJhbGciOi rejected", "eyJhbGciOi"), ("Bearer abc.def.ghi is expired", "abc.def.ghi"),
                               ("Authorization: Basic dXNlcjpwYXNz", "dXNlcjpwYXNz"), ("key ending in 9f3c", "9f3c")] {
            XCTAssertFalse(ArisProviderWords.loggable(text).contains(secret), text)
        }
        XCTAssertEqual(ArisProviderWords.loggable("groq timeout: no answer in time"), "groq timeout: no answer in time")
        XCTAssertLessThanOrEqual(ArisProviderWords.loggable(String(repeating: "a ", count: 900)).count, ArisProviderWords.longest + 1)
    }
}
