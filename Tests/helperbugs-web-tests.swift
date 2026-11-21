// Tests for jv-helperbugs (web): audited aris-tools bugs 12–14. A fetch through a proxy or fake-IP DNS is checked
// at the hop it really made (the proxy's), while local targets stay refused; a page is read in its own charset (CP949
// too) and a long one is cut with a line that says so; Yahoo's 429 is "busy", not "no such stock"; the weather is said
// in °F on a Mac set to it; timer and board are told as done only once the app took them; a mailbox is junk or trash
// by a whole word of its name, and a list looks past a run of junk; a read-only calendar can't be chosen; an unchecked
// send carries Full Disk Access's pane; an HTML file is read with nothing fetched. No network, no app.
// Called from main.swift; uses its check().
import Foundation
import SQLite3

private let webRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func webSource(_ path: String) -> String { (try? String(contentsOf: webRoot.appendingPathComponent(path), encoding: .utf8)) ?? "" }

private func webFolder() -> String {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-helperbugs-web-\(UUID().uuidString.prefix(8))")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.resolvingSymlinksInPath().path
}

func runHelperbugsWebTests() {
    webProxyTests()
    webCharsetTests()
    webCapTests()
    webHTMLFileTests()
    webStockWeatherTests()
    webAckTests()
    webMailTests()
    webCalendarMessageTests()
}

// MARK: - 12: proxy and fake-IP

private func webProxyTests() {
    let fake: (String) -> [String]? = { _ in ["198.18.0.7"] }
    check(ArisWebFetch.allows("https://news.example.kr/a", resolve: fake, fakeIP: false) == nil
          && ArisWebFetch.allows("https://news.example.kr/a", resolve: fake, fakeIP: true) != nil,
          "12 fake-IP: a name answered in 198.18/15 passes only while this Mac runs a fake-IP resolver")
    check(ArisWebFetch.allows("https://x.example/", resolve: { _ in ["198.18.0.7", "10.0.0.2"] }, fakeIP: true) == nil
          && ArisWebFetch.allows("https://x.example/", resolve: { _ in ["127.0.0.1"] }, fakeIP: true) == nil
          && ArisWebFetch.allows("https://x.example/", resolve: { _ in ["192.168.1.1"] }, fakeIP: true) == nil,
          "12 fake-IP: a name that resolves here to a private or loopback address is still refused")
    for local in ["http://198.18.0.7/", "http://127.0.0.1:23351/ask", "http://localhost/", "http://router.lan/", "http://printer.local/", "http://10.0.0.1/"] {
        check(ArisWebFetch.allows(local, resolve: fake, fakeIP: true) == nil, "12 fake-IP: \(local) as written is still refused")
    }
    check(ArisWebRoute.isFakeIP("198.18.0.1") && ArisWebRoute.isFakeIP("198.19.255.254") && !ArisWebRoute.isFakeIP("198.20.0.1")
          && !ArisWebRoute.isFakeIP("8.8.8.8") && !ArisWebRoute.isFakeIP("::ffff:198.18.0.1") && !ArisWebRoute.isFakeIP("nonsense"),
          "12 fake-IP: the range is 198.18.0.0/15")
    check(ArisWebRoute.holdsFakeIP(["127.0.0.1", "192.168.0.4", "198.18.0.1"]) && !ArisWebRoute.holdsFakeIP(["127.0.0.1", "192.168.0.4"]),
          "12 fake-IP: in use when one of the Mac's own addresses is in the range (the proxy's tunnel)")

    typealias Hop = ArisWebRoute.Hop
    check(ArisWebFetch.connectedSafely([Hop(address: "127.0.0.1", viaProxy: true)], proxies: ["127.0.0.1"], fakeIP: false)
          && ArisWebFetch.connectedSafely([Hop(address: "[::1]", viaProxy: true)], proxies: ["::1"], fakeIP: false),
          "12 proxy: a hop the system made to its configured proxy counts (127.0.0.1:7890 and the like)")
    check(!ArisWebFetch.connectedSafely([Hop(address: "127.0.0.1", viaProxy: true)], proxies: ["10.0.0.9"], fakeIP: false)
          && !ArisWebFetch.connectedSafely([Hop(address: "127.0.0.1", viaProxy: false)], proxies: ["127.0.0.1"], fakeIP: false),
          "12 proxy: a proxy hop elsewhere than the configured proxy, or a direct hop to a local address, still throws the page away")
    check(ArisWebFetch.connectedSafely([Hop(address: "127.0.0.1", viaProxy: true)], proxies: nil, fakeIP: false),
          "12 proxy: a proxy script's choice (its host isn't known beforehand) counts when the system made it a proxy hop")
    check(ArisWebFetch.connectedSafely([Hop(address: "198.18.3.4", viaProxy: false)], proxies: [], fakeIP: true)
          && !ArisWebFetch.connectedSafely([Hop(address: "198.18.3.4", viaProxy: false)], proxies: [], fakeIP: false),
          "12 fake-IP: a connection into the fake-IP range counts only while the resolver runs")
    check(!ArisWebFetch.connectedSafely([], proxies: nil, fakeIP: true) && !ArisWebFetch.connectedSafely([Hop(address: nil, viaProxy: true)], proxies: nil, fakeIP: true)
          && !ArisWebFetch.connectedSafely([Hop(address: "93.184.216.34", viaProxy: false), Hop(address: "10.0.0.1", viaProxy: false)], proxies: [], fakeIP: true),
          "12 proxy: no transaction, one without an address, or one local hop among good ones fails closed")
    check(ArisWebFetch.connectedPublicly(["93.184.216.34"]) && !ArisWebFetch.connectedPublicly(["198.18.0.1"]),
          "12: the old direct check is unchanged (no fake-IP, no proxy)")

    let listed: [[String: Any]] = [[kCFProxyTypeKey as String: kCFProxyTypeHTTPS as String, kCFProxyHostNameKey as String: "127.0.0.1",
                                    kCFProxyPortNumberKey as String: 7890],
                                   [kCFProxyTypeKey as String: kCFProxyTypeNone as String]]
    check(ArisWebRoute.proxies(from: listed) == ArisWebRoute.Proxies(hosts: ["127.0.0.1"], scripted: false)
          && ArisWebRoute.proxies(from: [[kCFProxyTypeKey as String: kCFProxyTypeAutoConfigurationURL as String]]).scripted
          && !ArisWebRoute.proxies(from: [[kCFProxyTypeKey as String: kCFProxyTypeNone as String]]).any,
          "12 proxy: the system's list gives the proxy hosts, a PAC as scripted, and direct as none")
    check(ArisWebRoute.proxyAddresses(ArisWebRoute.Proxies(hosts: ["proxy.home", "127.0.0.1"]), resolve: { $0 == "proxy.home" ? ["192.168.0.2"] : nil })
              == ["192.168.0.2", "127.0.0.1"]
          && ArisWebRoute.proxyAddresses(ArisWebRoute.Proxies(hosts: [], scripted: true)) == nil,
          "12 proxy: a proxy's address is its host resolved (a numeric one as it is); a script's is unknown")
    let command = webSource("ArisTools/ArisWebCommand.swift")
    check(command.contains("$0.isProxyConnection") && command.contains("ArisWebRoute.proxies(for: url)")
          && command.contains("ArisWebFetch.allows(next.absoluteString, fakeIP: fakeIP)"),
          "12 proxy: web fetch checks each hop as it really went, and a redirect the same way")
}

// MARK: - 12: charset

private func webCharsetTests() {
    let korean = "안녕하세요, 똠방각하 뷁 공지사항"
    guard let cp949 = korean.data(using: ArisTextDecoding.cp949) else { return check(false, "12 charset: CP949 is on this Mac") }
    check(ArisTextDecoding.decode(cp949, contentType: "text/html; charset=EUC-KR") == korean
          && ArisTextDecoding.decode(cp949, contentType: "text/html; charset=\"ks_c_5601-1987\"") == korean,
          "12 charset: a page the server says is EUC-KR is read as CP949 (똠 and 뷁 too)")
    let meta = Data("<html><head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=euc-kr\"></head><body>".utf8) + cp949
    check(ArisTextDecoding.decode(meta).contains(korean), "12 charset: a <meta> charset near the top is used when the server said none")
    let meta5 = Data("<meta charset='EUC-KR'>".utf8) + cp949
    check(ArisTextDecoding.decode(meta5).contains(korean), "12 charset: <meta charset=…> too")
    check(ArisTextDecoding.decode(cp949) == korean, "12 charset: unlabelled bytes that aren't UTF-8 but read as Korean are CP949")
    check(ArisTextDecoding.decode(Data(korean.utf8)) == korean && ArisTextDecoding.decode(Data(korean.utf8), contentType: "text/html") == korean,
          "12 charset: UTF-8 stays UTF-8")
    check(ArisTextDecoding.decode(Data(korean.utf8).dropLast(1)).hasPrefix("안녕하세요"), "12 charset: a body cut inside a character is still UTF-8")
    check(ArisTextDecoding.decode(Data([0x63, 0x61, 0x66, 0xE9, 0x20, 0x93, 0x71, 0x94])) == "café “q”", "12 charset: unlabelled Latin bytes are Windows-1252")
    check(ArisTextDecoding.decode(Data([0xEF, 0xBB, 0xBF]) + Data("가".utf8), contentType: "text/html; charset=euc-kr").hasSuffix("가"),
          "12 charset: a byte-order mark wins")
    check(ArisTextDecoding.charset(contentType: "text/html; Charset=UTF-8") == "utf-8" && ArisTextDecoding.charset(contentType: "text/html") == nil
          && ArisTextDecoding.encoding(named: "bogus-charset") == nil && ArisTextDecoding.encoding(named: "Shift_JIS") != nil,
          "12 charset: the header's charset; an unknown label is ignored, a known one used")
    check(webSource("ArisTools/ArisWebCommand.swift").contains("ArisTextDecoding.decode(body, contentType: type)")
          && !webSource("ArisTools/ArisWebCommand.swift").contains("String(decoding: body, as: UTF8.self)"),
          "12 charset: web fetch decodes by charset, never UTF-8 alone")
}

// MARK: - 12: cut

private func webCapTests() {
    check(ArisWebFetch.maxText >= 15_000, "12 cut: a fetch hands on more than 6,000 characters (\(ArisWebFetch.maxText))")
    let long = String(repeating: "가나다라 ", count: 10_000)
    let cut = ArisWebFetch.capped(long)
    check(cut.hasPrefix("[truncated: the first \(ArisWebFetch.maxText) of \(long.count) characters") && cut.hasSuffix("…[truncated]")
          && cut.count <= ArisWebFetch.maxText + 120, "12 cut: a long text says first that it was cut, and from how much")
    check(ArisWebFetch.capped("짧은 글") == "짧은 글" && !ArisWebFetch.text(fromHTML: "<p>짧은</p>").contains("truncated"), "12 cut: a short one is as it was")
    check(ArisWebFetch.text(fromHTML: "<p>" + long + "</p>").hasPrefix("[truncated"), "12 cut: a long page too")
    check(ArisWebFetch.text(fromHTML: "<p>" + long + "</p>", limit: .max).count >= long.count - 10, "12 cut: no limit reads it whole (a file)")
}

// MARK: - 14: HTML files

private func webHTMLFileTests() {
    let folder = webFolder()
    let page = """
        <html><head><meta charset="euc-kr"><link rel="stylesheet" href="https://tracker.example/s.css"></head>
        <body><img src="https://tracker.example/open.gif"><iframe src="http://127.0.0.1:23351/ask"></iframe><p>
        """
    let html = folder + "/notice.html"
    let body = (Data(page.utf8) + ("공지: 내일 휴강" .data(using: ArisTextDecoding.cp949) ?? Data()) + Data("</p></body></html>".utf8))
    FileManager.default.createFile(atPath: html, contents: body)
    let read = ArisHTMLFileText.text(path: html) ?? ""
    check(read.contains("공지: 내일 휴강") && !read.contains("tracker") && !read.contains("<"), "14 html: an HTML file's text, in its own charset (\(read))")
    let archive = folder + "/saved.webarchive"
    let plist: [String: Any] = ["WebMainResource": ["WebResourceData": Data("<html><body><h1>저장한 페이지</h1><img src='https://x.example/a.png'></body></html>".utf8),
                                                    "WebResourceTextEncodingName": "UTF-8", "WebResourceMIMEType": "text/html",
                                                    "WebResourceURL": "https://x.example/"],
                                "WebSubresources": [["WebResourceURL": "https://x.example/a.png", "WebResourceData": Data([0, 1, 2])]]]
    if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) { FileManager.default.createFile(atPath: archive, contents: data) }
    check(ArisHTMLFileText.text(path: archive) == "저장한 페이지", "14 html: a web archive's main page, its resources never read")
    check(ArisHTMLFileText.handles("/a/B.HTM") && ArisHTMLFileText.handles("/a/x.webarchive") && !ArisHTMLFileText.handles("/a/x.docx"),
          "14 html: html, htm and web archives; Word files keep AppKit's reader")
    let command = webSource("ArisTools/ArisFileTextCommand.swift")
    check(command.contains("case .rich where ArisHTMLFileText.handles(path): text = ArisHTMLFileText.text(path: path)"),
          "14 html: files read takes HTML past AppKit's importer, which would fetch its remote resources")
    try? FileManager.default.removeItem(atPath: folder)
}

// MARK: - 13: stock, weather

private func webStockWeatherTests() {
    let busy = ArisStock.notFoundLine("AAPL", reached: true, limited: true)
    check(busy.contains("429") && busy.contains("busy") && !busy.contains("couldn't find"), "13 stock: Yahoo's 429 is busy, not \"no such stock\"")
    check(ArisStock.notFoundLine("zzz", reached: true, limited: false).contains("couldn't find")
          && ArisStock.notFoundLine("zzz", reached: false, limited: false).contains("didn't answer"), "13 stock: not found and no answer as before")
    let stockCommand = webSource("ArisTools/ArisStockCommand.swift")
    check(stockCommand.contains("case .limited: limited = true") && stockCommand.contains("ArisStock.notFoundLine(query, reached: reached, limited: limited)"),
          "13 stock: a 429 from either host is kept apart from a refusal")
    check(webSource("ArisTools/ArisCurrencyCommand.swift").contains("if limited { fail(\"the rate service is busy right now (Yahoo answered 429"),
          "13 stock: a currency rate behind the same 429 is busy too, not \"no rate found\"")

    check(ArisWeather.usesFahrenheit(appleUnit: "Fahrenheit", locale: Locale(identifier: "ko_KR"))
          && !ArisWeather.usesFahrenheit(appleUnit: "Celsius", locale: Locale(identifier: "en_US"))
          && ArisWeather.usesFahrenheit(appleUnit: nil, locale: Locale(identifier: "en_US"))
          && !ArisWeather.usesFahrenheit(appleUnit: nil, locale: Locale(identifier: "en_CA"))
          && !ArisWeather.usesFahrenheit(appleUnit: nil, locale: Locale(identifier: "ko_KR")),
          "13 weather: °F when the Mac is set to Fahrenheit, else when its region measures in it")
    let url = ArisWeather.forecastURL(latitude: 40.7, longitude: -74, timezone: "America/New_York", days: 1, fahrenheit: true).absoluteString
    check(url.contains("temperature_unit=fahrenheit") && url.contains("wind_speed_unit=mph")
          && !ArisWeather.forecastURL(latitude: 1, longitude: 1, timezone: "UTC", days: 1).absoluteString.contains("fahrenheit"),
          "13 weather: the forecast is asked in °F and mph only then")
    let json = #"{"current":{"temperature_2m":71.6,"apparent_temperature":70,"weather_code":0,"wind_speed_10m":5},"daily":{"time":["2026-11-18"],"weather_code":[0],"temperature_2m_max":[75],"temperature_2m_min":[60],"precipitation_probability_max":[10]}}"#
    if let forecast = try? JSONDecoder().decode(ArisWeather.Forecast.self, from: Data(json.utf8)) {
        let said = ArisWeather.summary(forecast, place: "New York", korean: false, fahrenheit: true)
        let saidKo = ArisWeather.summary(forecast, place: "뉴욕", korean: true, fahrenheit: true)
        check(said.contains("72°F") && said.contains("60–75°F") && said.contains("5 mph") && !said.contains("°C")
              && saidKo.contains("72°F") && saidKo.contains("5mph"), "13 weather: said in °F and mph (\(said))")
        check(ArisWeather.summary(forecast, place: "x", korean: false).contains("°C"), "13 weather: °C by default")
    } else { check(false, "13 weather: the fixture decodes") }
    check(webSource("ArisTools/main.swift").contains("let fahrenheit = ArisWeather.macUsesFahrenheit"),
          "13 weather: the command follows the Mac's setting; the notch's card keeps °C (the range it reads)")
}

// MARK: - 13: timer and board

private func webAckTests() {
    let folder = webFolder()
    let file = URL(fileURLWithPath: folder + "/timer.json")
    FileManager.default.createFile(atPath: file.path, contents: Data("{}".utf8))
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { try? FileManager.default.removeItem(at: file) }
    check(ArisAppAck.taken(file, timeout: 2), "13 ack: a file the app removed is taken")
    FileManager.default.createFile(atPath: file.path, contents: Data("{}".utf8))
    let started = Date()
    check(!ArisAppAck.taken(file, timeout: 0.3) && Date().timeIntervalSince(started) < 1.5, "13 ack: a file still there after the wait is not taken")
    check(ArisAppAck.notTakenLine("the timer").contains("may not have happened") && ArisAppAck.notTakenLine("the timer").contains("don't say it was done"),
          "13 ack: what is said then")
    let timer = webSource("ArisTools/ArisTimerCommand.swift"), board = webSource("ArisTools/ArisBoardCommand.swift")
    check(timer.contains("guard ArisAppAck.taken(timerFile) else { fail(ArisAppAck.notTakenLine(\"the timer\")) }")
          && timer.range(of: "ArisAppAck.taken(timerFile)")!.lowerBound < timer.range(of: "logActivity(stopping")!.lowerBound,
          "13 ack: the timer is told as set (and logged for undo) only once the app took it")
    check(board.contains("guard ArisAppAck.taken(boardFile)") && board.range(of: "ArisAppAck.taken(boardFile)")!.lowerBound < board.range(of: "print(close ?")!.lowerBound,
          "13 ack: the board is told as shown only once the app took it")
    check(webSource("Aris/private/Aris/ArisBoard.swift").contains("try? FileManager.default.removeItem(at: Self.file)")
          && webSource("Aris/private/Aris/ArisTimerModel.swift").contains("try? FileManager.default.removeItem(at: file)"),
          "13 ack: the app removes each request once read")
    try? FileManager.default.removeItem(atPath: folder)
}

// MARK: - 14: mail

private func webDB(_ path: String, _ sql: String) {
    try? FileManager.default.removeItem(atPath: path)
    var db: OpaquePointer?
    guard sqlite3_open(path, &db) == SQLITE_OK else { return check(false, "fixture: open \(path)") }
    defer { sqlite3_close(db) }
    var error: UnsafeMutablePointer<CChar>?
    if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK { check(false, "fixture sql: \(String(cString: error!))") }
}

private func webMailTests() {
    for kept in ["imap://me@x.com/Cabinet", "imap://me@x.com/Binance%20alerts", "imap://me@x.com/Robin", "imap://me@x.com/INBOX", "imap://bin@x.com/INBOX"] {
        check(!ArisMailRead.skipped(box: kept), "14 mail: \(kept) is listed (\"bin\" inside a word isn't the trash)")
    }
    for skipped in ["imap://me@gmail.com/%5BGmail%5D/Bin", "ews://x/Junk%20E-mail", "imap://x/Deleted%20Messages", "imap://x/Trash", "imap://x/%ED%9C%B4%EC%A7%80%ED%86%B5",
                    "imap://x/%EC%8A%A4%ED%8C%B8%ED%8E%B8%EC%A7%80%ED%95%A8", "imap://x/Recycle%20Bin"] {
        check(ArisMailRead.skipped(box: skipped), "14 mail: \(skipped) is junk or trash")
    }
    let folder = webFolder()
    let path = folder + "/Envelope Index"
    var junk: [String] = []
    for row in 1...120 { junk.append("(\(row), 2, 1, \(1_800_000_000 - row), 1, 2, 1, 0)") }
    webDB(path, """
        CREATE TABLE subjects (ROWID INTEGER PRIMARY KEY, subject TEXT);
        CREATE TABLE addresses (ROWID INTEGER PRIMARY KEY, address TEXT, comment TEXT);
        CREATE TABLE summaries (ROWID INTEGER PRIMARY KEY, summary TEXT);
        CREATE TABLE mailboxes (ROWID INTEGER PRIMARY KEY, url TEXT);
        CREATE TABLE messages (ROWID INTEGER PRIMARY KEY, subject INTEGER, sender INTEGER, date_received INTEGER, summary INTEGER,
                               mailbox INTEGER, read INTEGER, deleted INTEGER);
        INSERT INTO subjects VALUES (1, '등록금 안내'), (2, 'WIN A PRIZE');
        INSERT INTO addresses VALUES (1, 'office@uni.ca', '학사팀');
        INSERT INTO summaries VALUES (1, 'x');
        INSERT INTO mailboxes VALUES (1, 'imap://me@uni.ca/Cabinet'), (2, 'imap://me@uni.ca/Junk');
        INSERT INTO messages VALUES \(junk.joined(separator: ", ")), (500, 1, 1, 1700000000, 1, 1, 1, 0);
        """)
    let recent = (try? ArisMailRead.read(path: path, query: nil, limit: 10)) ?? []
    check(recent.map(\.subject) == ["등록금 안내"], "14 mail (13 window): a mail behind 120 junk ones is still found, in a folder named Cabinet (\(recent.map(\.subject)))")
    let searched = (try? ArisMailRead.read(path: path, query: "등록금", limit: 3)) ?? []
    check(searched.map(\.subject) == ["등록금 안내"], "14 mail: a search pages the same way")
    try? FileManager.default.removeItem(atPath: folder)
}

// MARK: - 14: calendar, message

private func webCalendarMessageTests() {
    check(ArisActions.calendarWritableScript("Holidays \"KR\"") == "tell application \"Calendar\" to get writable of calendar \"Holidays \\\"KR\\\"\"",
          "14 calendar: the writable check names the calendar quoted")
    check(ArisActions.readOnlyCalendarRefusal("대한민국 공휴일", writable: "false\n")?.contains("read-only") == true
          && ArisActions.readOnlyCalendarRefusal("Work", writable: "true") == nil,
          "14 calendar: a read-only calendar can't be the one new events go in")
    let mac = webSource("ArisTools/ArisMac.swift")
    // jv-prompts: the app's EventKit says which calendars take new events; Calendar's scripting only as the fallback.
    check(mac.contains("let canAdd = writable.map { $0.contains(name) ? \"true\" : \"false\" } ?? appleScript(ArisActions.calendarWritableScript(name), app: \"Calendar\")")
          && mac.contains("if let refusal = ArisActions.readOnlyCalendarRefusal(name, writable: canAdd) { fail(refusal) }"),
          "14 calendar: use-calendar checks the calendar takes new events before saving the choice")
    check(mac.contains("fail(result.line, fix: sent.attempt == .unchecked ? diskAccessFix(database) : nil)")
          && webSource("ArisTools/ArisTurnGate.swift").contains("couldn't check that it went out (Aris needs Full Disk Access"),
          "14 message: a send that couldn't be checked says why (Full Disk Access) and brings that pane's fix")
}
