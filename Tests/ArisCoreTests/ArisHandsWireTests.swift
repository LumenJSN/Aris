import XCTest
@testable import ArisCore

/// The MCP face's wire, effect classes and tool results (jv-hands). The server loop and the gates are tested in
/// tests/hands-tests.swift.
final class ArisHandsWireTests: XCTestCase {
    private let tools = [ArisMCPServerWire.Tool(name: "timer", description: "A timer", inputSchema: ["type": "object", "properties": [:]])]

    private func object(_ data: Data) -> [String: Any] {
        XCTAssertEqual(data.last, 0x0A)
        XCTAssertEqual(data.filter { $0 == 0x0A }.count, 1, "one message is one line")
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private func reply(_ line: String) -> [String: Any] {
        guard case .reply(let data) = ArisMCPServerWire.step(Data(line.utf8), tools: tools) else { XCTFail("no reply for \(line)"); return [:] }
        return object(data)
    }

    func testInitializeAnswersTheClientsVersionOrTheNewest() {
        let known = reply(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#)
        let result = known["result"] as? [String: Any]
        XCTAssertEqual(result?["protocolVersion"] as? String, "2025-06-18")
        XCTAssertEqual((result?["serverInfo"] as? [String: Any])?["name"] as? String, "aris")
        XCTAssertNotNil((result?["capabilities"] as? [String: Any])?["tools"])
        let unknown = reply(#"{"jsonrpc":"2.0","id":"a","method":"initialize","params":{"protocolVersion":"1999-01-01"}}"#)
        XCTAssertEqual((unknown["result"] as? [String: Any])?["protocolVersion"] as? String, ArisMCPServerWire.versions[0])
        XCTAssertEqual(unknown["id"] as? String, "a")
    }

    func testListPingAndErrors() {
        let list = reply(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        XCTAssertEqual(((list["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.first?["name"] as? String, "timer")
        XCTAssertNotNil(reply(#"{"jsonrpc":"2.0","id":3,"method":"ping"}"#)["result"])
        XCTAssertEqual((reply(#"{"jsonrpc":"2.0","id":4,"method":"resources/list"}"#)["error"] as? [String: Any])?["code"] as? Int, -32601)
        XCTAssertEqual((reply("not json")["error"] as? [String: Any])?["code"] as? Int, -32700)
        XCTAssertEqual((reply(#"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"rm"}}"#)["error"] as? [String: Any])?["code"] as? Int, -32602)
        XCTAssertEqual((reply(#"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"timer","arguments":[1]}}"#)["error"] as? [String: Any])?["code"] as? Int, -32602)
        XCTAssertEqual((reply(#"{"id":7,"method":"ping"}"#)["error"] as? [String: Any])?["code"] as? Int, -32600)
    }

    func testCallsCancelsAndNotifications() {
        guard case .call(let id, let name, let arguments) = ArisMCPServerWire.step(Data(#"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"timer","arguments":{"minutes":5}}}"#.utf8), tools: tools) else {
            return XCTFail("not a call")
        }
        XCTAssertTrue(ArisMCPServerWire.sameID(id, 8 as NSNumber))
        XCTAssertEqual(name, "timer")
        XCTAssertEqual(arguments["minutes"] as? Int, 5)
        guard case .cancel(let cancelled) = ArisMCPServerWire.step(Data(#"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":8}}"#.utf8), tools: tools) else {
            return XCTFail("not a cancel")
        }
        XCTAssertTrue(ArisMCPServerWire.sameID(cancelled, id))
        XCTAssertFalse(ArisMCPServerWire.sameID("8", 8 as NSNumber))
        guard case .nothing = ArisMCPServerWire.step(Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8), tools: tools) else { return XCTFail("a notification") }
        guard case .reply = ArisMCPServerWire.step(Data(repeating: 0x20, count: ArisMCPServerWire.longestLine + 1), tools: tools) else { return XCTFail("too long") }
    }

    func testCallResultCarriesTheContentSource() {
        let marked = ArisToolResult(text: "page", content: .init(kind: "web", source: "https://example.com"))
        let line = object(ArisMCPServerWire.callResult(id: 9, text: marked.text, isError: false, meta: marked.meta))
        let result = line["result"] as? [String: Any]
        XCTAssertEqual((result?["content"] as? [[String: Any]])?.first?["text"] as? String, "page")
        XCTAssertEqual(result?["isError"] as? Bool, false)
        XCTAssertEqual(((result?["_meta"] as? [String: Any])?["aris/content"] as? [String: Any])?["source"] as? String, "https://example.com")
        let plain = object(ArisMCPServerWire.callResult(id: 10, text: "done", isError: true))
        XCTAssertNil((plain["result"] as? [String: Any])?["_meta"])
        XCTAssertNil(ArisToolResult(text: "done").meta)
    }

    func testToolNames() {
        XCTAssertEqual(ArisMCPServerWire.clientName("timer"), "mcp__aris__timer")
        XCTAssertEqual(ArisMCPServerWire.function(clientName: "mcp__aris__shell_run"), "shell_run")
        XCTAssertNil(ArisMCPServerWire.function(clientName: "mcp__other__x"))
        XCTAssertNil(ArisMCPServerWire.function(clientName: "mcp__aris__"))
        XCTAssertNil(ArisMCPServerWire.function(clientName: "Bash"))
    }

    func testEffectClasses() {
        XCTAssertEqual(ArisEffectClass.allCases.map(\.rawValue), ["observe", "change-reversible", "change-permanent", "outward", "never"])
        XCTAssertEqual(ArisEffectClass.strongest([.observe, .changePermanent, .changeReversible]), .changePermanent)
        XCTAssertEqual(ArisEffectClass.strongest([.outward, .never]), .never)
        XCTAssertEqual(ArisEffectClass.strongest([]), .observe)
        let data = try? JSONEncoder().encode([ArisEffectClass.changeReversible])
        XCTAssertEqual(data.map { String(decoding: $0, as: UTF8.self) }, #"["change-reversible"]"#)
    }
}
