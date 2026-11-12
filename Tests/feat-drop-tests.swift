//
//  feat-drop-tests.swift
//  Dropping a file on Aris brings up the chips for what Aris can really do with it (ArisDropChips): which chips each
//  kind of file gets, in Korean and English, that every chip's request reaches the brain as the user's own words with
//  the file, that a chip which makes files is one aris-tools really performs (run on tiny fixtures in a temporary
//  home folder, never on the user's files), that a file Aris holds back from reading gets the file tools' own rules
//  (ArisFiles.looksSecret, ArisProtectedPlaces), and what twenty files, an alias and a file that is gone come to.
//  Called from main.swift.
//

import CoreGraphics
import CoreText
import Foundation
import ImageIO

func runFeatDropTests() {
    dropKindTests()
    dropOfferTests()
    dropSeveralTests()
    dropGuardTests()
    dropWordsTests()
    dropRequestTests()
    dropEdgeTests()
    dropToolTests()
    dropReadingTests()
    dropWiringTests()
}

private let dropHome = "/Users/p"

/// A dropped file as the app would have found it: readable where its kind is read, in the user's Downloads.
private func dropped(_ name: String, in folder: String = dropHome + "/Downloads", folder isFolder: Bool = false, size: Int? = 2_000,
                     pdfHasText: Bool = true, allowed: Bool = false, pictureWords: Bool? = nil) -> ArisDropFile {
    var file = ArisDropFile.inspect(folder + "/" + name, isFolder: isFolder, size: size, home: dropHome, allowed: allowed,
                                    isKeynote: { _ in false }, pdfHasText: { _ in pdfHasText })
    if let pictureWords, file.text == .looking { file.text = pictureWords ? .found : .none }
    return file
}

private func labels(_ chips: [ArisDropChip]) -> [String] { chips.map(\.label) }

private func offer(_ files: [ArisDropFile], english: Bool = false) -> ArisDropOffer { ArisDropChips.offer(files, english: english) }

// MARK: - Kinds

private func dropKindTests() {
    let kinds: [(String, ArisDropKind)] = [("a.pdf", .pdf), ("A.PDF", .pdf), ("a.docx", .document), ("a.md", .document), ("a.txt", .document),
                                           ("a.csv", .text), ("a.json", .text), ("a.swift", .text), ("a.HEIC", .image), ("a.jpeg", .image),
                                           ("a.mov", .video), ("a.m4v", .video), ("a.mp3", .audio), ("a.xlsx", .other), ("a.zip", .other),
                                           ("a.mkv", .other), ("noextension", .other)]
    check(kinds.allSatisfy { ArisDropKind.of("/x/" + $0.0) == $0.1 }, "drop kinds: a file is a PDF, a document, text, a picture, a video or a sound by its extension, else nothing Aris has a chip for")
    check(ArisDropKind.of("/x/Photos", isFolder: true) == .folder && ArisDropKind.of("/x/note.rtfd", isFolder: true) == .document,
          "drop kinds: a folder is a folder, but an RTFD package is a document")
    // The kinds are the ones the two things behind the chips really take: aris-tools' convert, and the app's own reader.
    let converted = ArisDropKind.imageTypes.union(ArisDropKind.videoTypes).union(ArisDropKind.audioTypes).union(["pdf"])
    check(converted.allSatisfy { ArisConvert.kind("/x/a." + $0) != nil } && ArisDropKind.imageTypes == ArisConvert.imageInputs
          && ArisDropKind.videoTypes == ArisConvertWords.videoTypes && ArisDropKind.audioTypes == ArisConvertWords.audioTypes,
          "drop kinds: pictures, videos and sounds are exactly the ones aris-tools converts")
    check(converted.allSatisfy { ArisDropKind.format("/x/a." + $0) == ArisConvert.ownFormat("/x/a." + $0) },
          "drop kinds: a file's own format is spelled as aris-tools spells it (jpeg is jpg, m4v is mp4)")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-drop-kinds-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let plain = ArisDropKind.textTypes.union(["txt", "md", "markdown", "tex"])
    let unread = plain.filter { type in
        let url = folder.appendingPathComponent("a." + type)
        try? Data("hello from a file".utf8).write(to: url)
        return ArisAttachmentText.extract(url) != "hello from a file"
    }
    check(unread.isEmpty, "drop kinds: every plain-text kind with a 요약 chip is one the app reads (\(unread.sorted().joined(separator: " ")))")
    let rtf = folder.appendingPathComponent("a.rtf"), html = folder.appendingPathComponent("a.html")
    try? Data(#"{\rtf1\ansi hello rich}"#.utf8).write(to: rtf)
    try? Data("<html><body><p>hello page</p></body></html>".utf8).write(to: html)
    check(ArisAttachmentText.extract(rtf)?.contains("hello rich") == true && ArisAttachmentText.extract(html)?.contains("hello page") == true,
          "drop kinds: an RTF and a web page are read too")
    check(ArisDropFile.largestRead == ArisAttachmentText.largestFile, "drop kinds: a document too big for the app to read gets no reading chip")
}

// MARK: - One file

private func dropOfferTests() {
    let pdf = offer([dropped("report.pdf")])
    check(labels(pdf.main) == ["요약", "한국어로 번역", "PNG로 변환"] && labels(pdf.more) == ["영어로", "일본어로", "중국어로", "JPG로"] && pdf.caption == nil,
          "drop chips: a PDF gets 요약 · 한국어로 번역 · PNG로 변환, and the other languages and JPG on the second row")
    let english = offer([dropped("report.pdf")], english: true)
    check(labels(english.main) == ["Summarize", "Translate to English", "Convert to PNG"] && labels(english.more) == ["to Korean", "to Japanese", "to Chinese", "to JPG"],
          "drop chips: in English the PDF's chips are English, and the obvious language is English")
    let scan = offer([dropped("scan.pdf", pdfHasText: false)])
    check(labels(scan.main) == ["PNG로 변환"] && labels(scan.more) == ["JPG로"], "drop chips: a scanned PDF (no words in it) gets only 변환")
    let word = offer([dropped("letter.docx")])
    check(labels(word.main) == ["요약", "한국어로 번역"] && labels(word.more) == ["영어로", "일본어로", "중국어로"],
          "drop chips: a Word document gets 요약 and 번역, and no 변환 (aris-tools can't convert one)")
    check(labels(offer([dropped("data.csv")]).main) == ["요약"] && offer([dropped("data.csv")]).more.isEmpty && labels(offer([dropped("main.swift")]).main) == ["요약"],
          "drop chips: a data file or code gets 요약 alone")
    let heic = offer([dropped("IMG_1.HEIC", pictureWords: false)])
    check(labels(heic.main) == ["JPG로 변환"] && labels(heic.more) == ["PNG로", "PDF로"], "drop chips: a HEIC photo gets JPG로 변환, with PNG and PDF beside it")
    check(labels(offer([dropped("a.png", pictureWords: false)]).main) == ["JPG로 변환"] && labels(offer([dropped("a.jpg", pictureWords: false)]).main) == ["PNG로 변환"]
          && labels(offer([dropped("a.jpg", pictureWords: false)]).more) == ["PDF로", "HEIC로"],
          "drop chips: a picture is never offered the format it already is")
    check(labels(offer([dropped("shot.png")]).main) == ["JPG로 변환"], "drop chips: while a picture's words are still being read, 변환 is already there")
    check(labels(offer([dropped("shot.png", pictureWords: true)]).main) == ["JPG로 변환", "글자 뽑기"],
          "drop chips: a picture with words in it gets 글자 뽑기 after 변환 (nothing moves under the pointer when it arrives)")
    check(labels(offer([dropped("clip.mov")]).main) == ["MP4로 변환"] && labels(offer([dropped("clip.mov")]).more) == ["소리만 M4A로"]
          && labels(offer([dropped("clip.mp4")]).main) == ["소리만 M4A로"] && labels(offer([dropped("clip.mp4")]).more) == ["MOV로"],
          "drop chips: a video gets the other video format and its sound alone")
    check(labels(offer([dropped("song.mp3")]).main) == ["M4A로 변환"] && offer([dropped("song.m4a")]).main.isEmpty,
          "drop chips: a sound becomes M4A, and one that already is gets no chip")
    for nothing in [dropped("book.xlsx"), dropped("archive.zip"), dropped("movie.mkv"), dropped("Photos", folder: true), dropped("noextension")] {
        let none = offer([nothing])
        check(none.main.isEmpty && none.more.isEmpty && none.caption == nil, "drop chips: \(nothing.name) has nothing Aris can do today, so no chip (the composer waits for what the user types)")
    }
    check(offer([]) == ArisDropOffer(), "drop chips: no files, no chips")
    // Where aris-tools won't make files, and what the app can't open.
    check(labels(offer([dropped("report.pdf", in: "/private/tmp")]).main) == ["요약", "한국어로 번역"],
          "drop chips: a PDF outside the home folder and off any external disk gets no 변환 (aris-tools refuses there)")
    check(labels(offer([dropped("a.png", in: "/Volumes/USB/Photos", pictureWords: false)]).main) == ["JPG로 변환"]
          && offer([dropped("a.png", in: "/Volumes/USB/.Trashes", pictureWords: false)]).main.isEmpty,
          "drop chips: a picture on an external disk converts, but not in the disk's hidden folders")
    check(labels(offer([dropped("report.pdf", size: nil)]).main) == ["PNG로 변환"] && offer([dropped("notes.txt", size: 0)]).main.isEmpty,
          "drop chips: a file the app can't open, or an empty one, gets no reading chip")
    check(offer([dropped("big.txt", size: ArisDropFile.largestRead + 1)]).main.isEmpty, "drop chips: a document over 30 MB gets no reading chip")
}

// MARK: - Several files

private func dropSeveralTests() {
    let pdfs = offer([dropped("a.pdf"), dropped("b.pdf"), dropped("c.pdf")])
    check(labels(pdfs.main) == ["하나로 합치기", "요약", "한꺼번에 PNG로"] && labels(pdfs.more) == ["JPG로"],
          "drop chips: several PDFs get 하나로 합치기 first, then 요약 and 한꺼번에 PNG로")
    check(labels(offer([dropped("a.pdf"), dropped("b.pdf", pdfHasText: false)]).main) == ["하나로 합치기", "한꺼번에 PNG로"],
          "drop chips: 요약 only when every PDF has words")
    let photos = offer((1...20).map { dropped("IMG_\($0).HEIC", pictureWords: false) })
    check(labels(photos.main) == ["PDF 하나로 합치기", "한꺼번에 JPG로"] && labels(photos.more) == ["PNG로"],
          "drop chips: twenty photos get 한꺼번에 JPG로 and PDF 하나로 합치기")
    let mixedPictures = offer([dropped("a.jpg", pictureWords: true), dropped("b.png", pictureWords: true)])
    check(labels(mixedPictures.main) == ["PDF 하나로 합치기", "한꺼번에 HEIC로"] && mixedPictures.more.isEmpty,
          "drop chips: pictures of different formats are only offered a format none of them is, and never 글자 뽑기 for several")
    check(labels(offer([dropped("a.pdf"), dropped("b.png", pictureWords: false)]).main) == ["PDF 하나로 합치기"],
          "drop chips: PDFs and pictures together get PDF 하나로 합치기")
    check(labels(offer([dropped("a.mov"), dropped("b.mov")]).main) == ["하나로 합치기", "한꺼번에 MP4로"]
          && labels(offer([dropped("a.mp3"), dropped("b.wav")]).main) == ["하나로 합치기", "한꺼번에 M4A로"],
          "drop chips: clips of one kind merge into one, and convert together")
    check(labels(offer([dropped("a.pdf"), dropped("notes.md"), dropped("data.csv")]).main) == ["요약"],
          "drop chips: documents of different kinds get 요약 together")
    for files in [[dropped("a.pdf"), dropped("clip.mov")], [dropped("a.png", pictureWords: false), dropped("b.zip")], [dropped("a.pdf"), dropped("Folder", folder: true)],
                  [dropped("a.mov"), dropped("b.mp3")]] {
        check(offer(files).main.isEmpty, "drop chips: \(files.map(\.name).joined(separator: " + ")) have nothing in common Aris can do, so no chip")
    }
    check(labels(offer([dropped("a.pdf"), dropped("b.pdf")], english: true).main) == ["Merge into one", "Summarize", "All to PNG"]
          && labels(offer([dropped("a.png", pictureWords: false), dropped("b.png", pictureWords: false)], english: true).main) == ["Merge into one PDF", "All to JPG"],
          "drop chips: several files' chips in English")
}

// MARK: - Files Aris holds back from reading

private func dropGuardTests() {
    // The file tools' own rule for a name that looks like a key or a secret, name by name.
    let names = ["passwords.txt", "my-passwords.csv", "api-key.txt", "apiKey.json", "token.json", "notes.txt", "monkey.txt", "Keyboard shortcuts.md",
                 "tokenomics.md", "tokenizer.py", "secretary.txt", "passwordless.md", "passwordlist.txt", "sshkey.txt", "answer key.txt", "key findings.md",
                 "key.txt", "keys.json", "id_rsa", "id_ed25519.pub", ".env", "prod.env", "server.pem", "cert.p12", "vault.kdbx", "known_hosts",
                 "recovery codes.txt", "seed phrase.txt", "비밀번호 모음.txt", "와이파이 비번.md", "암호.txt", "report.pdf", "token-design.pdf", "password.png",
                 "secrets.mov", "deck.key", "wallet key.txt", "license-key.txt", "authtoken", "credentials", "Credentials.json", "README", "data.csv",
                 "client_secret_123.json", "token2.txt", "mypasswords", "keynote-token-design.pptx", "backup codes.txt", "master key.rtf"]
    let differing = names.filter { ArisDropGuard.looksSecret("/Users/p/Downloads/" + $0, isKeynote: { _ in false }) != ArisFiles.looksSecret("/Users/p/Downloads/" + $0, isKeynote: { _ in false }) }
    check(differing.isEmpty, "drop guard: a name looks like a secret to the app exactly when it does to the file tools (\(differing.joined(separator: ", ")))")
    check(ArisDropGuard.looksSecret("/x/passwords.txt", isKeynote: { _ in false }) && !ArisDropGuard.looksSecret("/x/monkey.txt", isKeynote: { _ in false })
          && !ArisDropGuard.looksSecret("/x/deck.key", isKeynote: { _ in true }) && ArisDropGuard.looksSecret("/x/deck.key", isKeynote: { _ in false }),
          "drop guard: passwords.txt and a private key look secret; monkey.txt and a Keynote deck don't")
    // The protected places, as aris-tools and the risk gate know them (a home folder that isn't on disk: by name alone).
    let home = "/Users/nobody-\(UUID().uuidString)"
    let places = ArisProtectedPlaces.relative.flatMap { [$0, $0 + "/inside.txt", $0.uppercased()] }
        + ["Downloads/a.pdf", "Desktop", ".config", ".config/other/x.json", "Library", "Library/Preferences/a.plist", "bin2/x", ".sshx/id", "Documents/.ssh/x", ""]
    let unlike = places.filter { ArisDropGuard.inProtectedPlace(home + "/" + $0, home: home) != ArisProtectedPlaces.blocks(home + "/" + $0, home: home) }
    check(unlike.isEmpty && ArisDropGuard.protectedPlaces == ArisProtectedPlaces.relative,
          "drop guard: a place is protected for the app exactly when it is for aris-tools (\(unlike.joined(separator: ", ")))")
    check(ArisDropGuard.inProtectedPlace(home, home: home) && !ArisDropGuard.inProtectedPlace("/tmp/x", home: home), "drop guard: the home folder itself is protected; a path outside it isn't one of its places")

    // What the chips make of them.
    let secret = dropped("passwords.txt")
    let held = offer([secret])
    check(secret.hold == .secretName && secret.text == .none && !secret.isReadable && labels(held.main) == ["읽어도 돼요"] && held.more.isEmpty
          && held.caption == "이름이 비밀번호·키 파일처럼 보여서 아직 읽지 않았어요.",
          "drop guard: a file named like a password file is not opened, gets no 요약, and says why with 읽어도 돼요")
    let allowed = offer([dropped("passwords.txt", allowed: true)])
    check(labels(allowed.main) == ["요약", "한국어로 번역"] && allowed.caption == nil, "drop guard: after 읽어도 돼요 it is a document like any other")
    let own = dropped("notes.txt", in: dropHome + "/.config/aris")
    check(own.hold == .protectedPlace && own.isHeld && offer([own]).main.isEmpty && offer([own]).caption == "Aris가 손대지 않는 곳(키·설정)에 있는 파일이라 읽지 않아요.",
          "drop guard: a file in a protected place is never read, has no chip, and says why")
    let stillHeld = dropped("notes.txt", in: dropHome + "/.ssh", allowed: true)
    check(stillHeld.isHeld && offer([stillHeld]).main.isEmpty, "drop guard: a protected place stays unread whatever was pressed")
    let picture = dropped("a.png", in: dropHome + "/.config/aris", pictureWords: true)
    check(picture.text == .none && !picture.convertible && offer([picture]).main.isEmpty, "drop guard: a picture in a protected place is neither read nor converted")
    let both = offer([dropped("a.pdf"), dropped("api-key.txt")])
    check(labels(both.main) == ["읽어도 돼요"] && both.caption != nil, "drop guard: one held file among several holds back the chips that would read them all")
    check(offer([secret], english: true).caption == "The name looks like a password or key file, so Aris hasn't read it."
          && labels(offer([secret], english: true).main) == ["Read it anyway"], "drop guard: the same in English")
    // Where aris-tools makes files.
    check(ArisDropGuard.convertible("/Users/p/Desktop/a.png", home: dropHome) && !ArisDropGuard.convertible("/Users/p/.ssh/a.png", home: dropHome)
          && !ArisDropGuard.convertible("/Users/other/a.png", home: dropHome) && !ArisDropGuard.convertible("/Volumes/USB", home: dropHome)
          && ArisDropGuard.convertible("/Volumes/USB/a.png", home: dropHome) && !ArisDropGuard.convertible("/Volumes/.hidden/a.png", home: dropHome),
          "drop guard: new files are made in the home folder outside the protected places, or on an external disk")
    check((try? ArisActivity.checkedPath("/private/tmp/a.png", home: dropHome)) == nil && !ArisDropGuard.convertible("/private/tmp/a.png", home: dropHome),
          "drop guard: where aris-tools refuses to work (outside the home folder, off any disk), no 변환 chip shows")
}

// MARK: - The words a chip asks with

private func dropWordsTests() {
    let sets: [[ArisDropFile]] = [[dropped("a.pdf")], [dropped("a.docx")], [dropped("a.csv")], [dropped("a.heic", pictureWords: true)], [dropped("a.png", pictureWords: true)],
                                  [dropped("a.mov")], [dropped("a.mp4")], [dropped("a.wav")], [dropped("a.pdf"), dropped("b.pdf")],
                                  [dropped("a.png", pictureWords: false), dropped("b.png", pictureWords: false)], [dropped("a.mov"), dropped("b.mov")],
                                  [dropped("a.mp3"), dropped("b.mp3")], [dropped("a.pdf"), dropped("b.jpg", pictureWords: false)]]
    var asked = 0
    for english in [false, true] {
        for files in sets {
            let offered = offer(files, english: english)
            for chip in offered.main + offered.more {
                guard let words = ArisDropCopy.words(chip.act, files: files, english: english) else { check(false, "drop words: \(chip.label) asks something"); continue }
                asked += 1
                let whole = ArisPendingFiles().adding(files.map { URL(fileURLWithPath: $0.path) }).request(with: words)
                var isAsk = false
                if case .ask = ArisIntent.guarded(ArisIntent.parse(words), said: words) { isAsk = true }
                check(isAsk && !ArisHandoff.isHandoff(words) && !ArisIntent.isRecurring(words) && !ArisFollowUp.isDone(words) && ArisBrain.pick(from: words) == nil
                      && !ArisDeixis.refersToScreen(whole) && !ArisDeixis.refersToClipboard(words) && ArisSpeech.language(of: words) == (english ? "en-US" : "ko-KR"),
                      "drop words: “\(words)” goes to the brain as a plain \(english ? "English" : "Korean") request about the file, never a local action, a job or the screen")
            }
        }
    }
    check(asked > 60, "drop words: every chip of every kind was checked (\(asked))")
    let pdf = [dropped("a.pdf")]
    check(ArisDropCopy.words(.summarize, files: pdf, english: false) == "이 파일 요약해 줘"
          && ArisDropCopy.words(.translate(to: "ko", orElse: "en"), files: pdf, english: false) == "이 파일 한국어로 번역해 줘. 이미 한국어면 영어로 번역해 줘."
          && ArisDropCopy.words(.translate(to: "ja", orElse: nil), files: pdf, english: false) == "이 파일 일본어로 번역해 줘"
          && ArisDropCopy.words(.convert(to: "png"), files: pdf, english: false) == "이 PDF를 쪽마다 PNG 그림으로 바꿔 줘",
          "drop words: a PDF's chips ask in plain Korean; the first 번역 says what to do when it is already Korean")
    check(ArisDropCopy.words(.convert(to: "jpg"), files: [dropped("a.heic")], english: false) == "이 파일 JPG로 바꿔 줘"
          && ArisDropCopy.words(.convert(to: "m4a"), files: [dropped("a.mov")], english: false) == "이 영상에서 오디오만 M4A로 뽑아 줘"
          && ArisDropCopy.words(.convert(to: "jpg"), files: [dropped("a.heic"), dropped("b.heic")], english: false) == "이 파일들 한꺼번에 JPG로 바꿔 줘"
          && ArisDropCopy.words(.merge, files: [dropped("a.pdf"), dropped("b.png")], english: false) == "이 파일들 PDF 하나로 합쳐 줘"
          && ArisDropCopy.words(.merge, files: [dropped("a.mov"), dropped("b.mov")], english: false) == "이 영상들 하나로 합쳐 줘"
          && ArisDropCopy.words(.extractText, files: [dropped("a.png")], english: false) == "이 그림에 있는 글자 그대로 적어 줘",
          "drop words: converting, merging and reading a picture, as the user would say them")
    check(ArisDropCopy.words(.translate(to: "en", orElse: "ko"), files: pdf, english: true) == "Translate this file into English. If it is already in English, translate it into Korean."
          && ArisDropCopy.words(.convert(to: "png"), files: pdf, english: true) == "Turn each page of this PDF into a PNG picture"
          && ArisDropCopy.words(.merge, files: [dropped("a.pdf"), dropped("b.pdf")], english: true) == "Merge these files into one PDF",
          "drop words: the same in English")
    check(ArisDropCopy.words(.allowReading, files: [dropped("passwords.txt")], english: false) == nil, "drop words: 읽어도 돼요 asks nothing of a brain")
    // The words the user might have expected ("소리만 M4A로") are the Mac's volume to the local rules: "소리" and the 4 of M4A.
    if case .volume = ArisIntent.parse("이 영상에서 소리만 M4A로 뽑아 줘") {
        check(true, "drop words: which is why the sound-only chip says 오디오만 (소리 … M4A would set the volume to 4)")
    }
}

// MARK: - The request

private func dropRequestTests() {
    let url = URL(fileURLWithPath: "/Users/p/Downloads/IMG_1.HEIC")
    let pending = ArisPendingFiles().adding([url])
    let convert = ArisDropChips.request(words: "이 파일 JPG로 바꿔 줘", pending: pending, makesFile: true, text: nil)
    check(convert.hasPrefix("이 파일 JPG로 바꿔 줘\n\n" + ArisPendingFiles.note + url.path + " — ") && ArisPendingFiles.carriesFiles(convert)
          && convert.contains("--finder, --shelf 아님") && convert.hasSuffix(")"),
          "drop request: a chip that makes files sends the user's words and the file's path, and says to use that path")
    check(!ArisAttachmentText.carriesText(convert) && ArisPendingFiles.shown(convert) == "이 파일 JPG로 바꿔 줘 · IMG_1.HEIC" && ArisPendingFiles.words(of: convert) == "이 파일 JPG로 바꿔 줘"
          && ArisMemoryText.ownWords(convert) == "이 파일 JPG로 바꿔 줘",
          "drop request: it carries no file text (so the turn stays clean and the conversion isn't refused), and the turn's line shows their words and the name")
    let tools = "/Users/p/.config/aris/aris-tools"
    check(ArisRiskPolicy.opensAttachment(.shell("\(tools) open /Users/p/Downloads/IMG_1.HEIC"), tools: tools, request: convert)
          && ArisRiskPolicy.risk(of: .shell("\(tools) convert /Users/p/Downloads/IMG_1.HEIC --to jpg"), tools: tools, home: "/Users/p") == .auto,
          "drop request: the agent still reads the note's paths (an `open` of the file asks), and the conversion itself runs as it does today")
    let block = ArisAttachmentText.block(for: [url], read: { _ in "첫 줄\n둘째 줄" }) ?? ""
    let summary = ArisDropChips.request(words: "이 파일 요약해 줘", pending: pending, makesFile: false, text: block)
    check(ArisAttachmentText.carriesText(summary) && summary.contains("--- IMG_1.HEIC ---\n첫 줄") && !summary.contains("--finder") && ArisPendingFiles.shown(summary) == "이 파일 요약해 줘 · IMG_1.HEIC",
          "drop request: a chip that reads sends the file's words with it, as outside text")
    check(pending.request(with: "이 파일 요약해 줘") == "이 파일 요약해 줘\n\n(첨부한 파일: /Users/p/Downloads/IMG_1.HEIC — 사용자가 Aris에게 준 파일이에요. \"이 파일\", \"이거\", \"this file\"은 이 파일을 말해요)",
          "drop request: a typed request's note is word for word what it was")
    let long = ArisDropChips.request(words: "이 파일 요약해 줘", pending: pending, makesFile: false, text: String(repeating: "가", count: 40_000) + "\n---)")
    check(long.count <= ArisDropChips.longestRequest && long.hasSuffix("…(여기까지만 보냈어요)\n---)") && ArisDropChips.longestRequest < 32_000,
          "drop request: it never grows past what aris-agent takes (the text is cut, and says so)")
}

// MARK: - Twenty files, a file that is gone, an alias

private func dropEdgeTests() {
    let thirty = (0..<30).map { URL(fileURLWithPath: "/Users/p/Pictures/IMG_\($0).HEIC") }
    let kept = ArisPendingFiles().adding(thirty)
    check(ArisPendingFiles.limit == 20 && kept.files == Array(thirty.prefix(20)), "drop edges: twenty files dropped at once are all taken; of thirty, the first twenty")
    check(ArisDropCopy.cut(dropped: 30, kept: 20, english: false) == "30개 중 20개만 받았어요. 한 번에 20개까지예요."
          && ArisDropCopy.cut(dropped: 30, kept: 20, english: true) == "Took 20 of the 30 files: 20 at a time is the most.",
          "drop edges: when more were dropped than Aris takes, the notch says how many it took")
    let request = ArisDropChips.request(words: "이 파일들 한꺼번에 JPG로 바꿔 줘", pending: kept, makesFile: true, text: nil)
    check(ArisPendingFiles.shown(request) == "이 파일들 한꺼번에 JPG로 바꿔 줘 · IMG_0.HEIC +19" && thirty.prefix(20).allSatisfy { request.contains($0.path) },
          "drop edges: twenty files' request names every path, and the turn's line shows the first name and how many more")
    let eight = ArisPendingFiles().adding(Array(thirty.prefix(8))).request(with: "요약")
    check(ArisPendingFiles.shown(eight).components(separatedBy: ", ").count == 8, "drop edges: up to eight names are still shown in full")
    let files = [dropped("a.pdf"), dropped("b.pdf")]
    check(ArisDropChips.gone(files, exists: { $0.hasSuffix("a.pdf") }).map(\.name) == ["b.pdf"] && ArisDropChips.gone(files, exists: { _ in true }).isEmpty,
          "drop edges: a file that is no longer there when its chip is pressed is found out before any turn starts")
    check(ArisDropCopy.gone(["b.pdf"], english: false) == "b.pdf 파일이 없어졌어요. 다시 끌어다 놓아 주세요." && ArisDropCopy.gone(["b.pdf", "c.pdf"], english: false) == "b.pdf 외 1개가 없어졌어요. 다시 끌어다 놓아 주세요."
          && ArisDropCopy.gone(["b.pdf"], english: true) == "b.pdf isn't there any more. Drop it again.",
          "drop edges: and the notch says which, and what to do")
    // A link stands for the file it points at; a broken one for itself.
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-drop-links-\(UUID().uuidString)").resolvingSymlinksInPath()
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let real = folder.appendingPathComponent("report.pdf"), link = folder.appendingPathComponent("shortcut"), broken = folder.appendingPathComponent("lost")
    try? Data("%PDF".utf8).write(to: real)
    try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
    try? FileManager.default.createSymbolicLink(at: broken, withDestinationURL: folder.appendingPathComponent("nothing.pdf"))
    check(ArisDropFile.original(of: link).path == real.path && ArisDropFile.original(of: real) == real && ArisDropFile.original(of: broken) == broken,
          "drop edges: a link dropped on Aris is the file it points at (its kind, its place); a broken link stays itself and gets no chip")
    if let bookmark = try? real.bookmarkData(options: .suitableForBookmarkFile) {
        let alias = folder.appendingPathComponent("report alias")
        try? URL.writeBookmarkData(bookmark, to: alias)
        check(ArisDropFile.original(of: alias).path == real.path, "drop edges: a Finder alias is the file it points at")
    } else {
        check(false, "drop edges: an alias could be made")
    }
}

// MARK: - aris-tools really does what the chips offer

private func dropToolTests() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("aris-drop-tools-\(UUID().uuidString)")
    let home = root.resolvingSymlinksInPath().path, desk = home + "/Desktop"
    try? FileManager.default.createDirectory(atPath: desk, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let run = { (words: [String]) -> String? in
        guard let call = ArisConvertWords.parse(words) else { return "malformed" }
        do { _ = try ArisConvert.run(call, home: home, cwd: desk); return nil } catch { return (error as? LocalizedError)?.errorDescription ?? "\(error)" }
    }
    let file = { (name: String) in ArisDropFile.inspect(desk + "/" + name, isFolder: false, size: 1_000, home: home) }
    /// The call the brain's convert rule makes for a chip.
    let call = { (chip: ArisDropChip, files: [ArisDropFile]) -> [String] in
        if case .convert(let to) = chip.act { return ["convert"] + files.map(\.path) + ["--to", to] }
        return ["merge"] + files.map(\.path)
    }
    let picture = dropPicture()
    var written: [String: Bool] = [:]
    for (name, type) in [("a.png", "public.png"), ("b.png", "public.png"), ("a.jpg", "public.jpeg"), ("a.heic", "public.heic"), ("a.tiff", "public.tiff")] {
        written[name] = dropWrite(picture, to: desk + "/" + name, type: type)
    }
    dropWritePDF(desk + "/a.pdf", words: "hello")
    dropWritePDF(desk + "/b.pdf", words: "again")
    var ran = 0
    for names in [["a.png"], ["a.jpg"], ["a.heic"], ["a.tiff"], ["a.pdf"], ["a.png", "b.png"], ["a.pdf", "b.pdf"], ["a.pdf", "a.png"], ["a.jpg", "a.png"]] {
        guard names.allSatisfy({ written[$0] ?? true }) else { continue } // a Mac that can't write HEIC has no fixture for it
        let files = names.map(file)
        let offered = offer(files)
        for chip in (offered.main + offered.more) where chip.makesFile {
            let failure = run(call(chip, files))
            ran += 1
            check(failure == nil, "drop tools: “\(chip.label)” on \(names.joined(separator: " + ")) is something aris-tools does (\(failure ?? "made"))")
        }
    }
    check(ran >= 15, "drop tools: every picture and PDF chip that makes a file was run for real (\(ran))")
    // Clips: the fixtures here aren't real media, so aris-tools gets as far as trying (its plan took the call) and then
    // says it couldn't; a format it never makes from that kind would be refused before, in other words.
    for names in [["a.mov"], ["a.mp4"], ["a.m4v"], ["a.mp3"], ["a.wav"], ["a.aiff"], ["a.caf"], ["a.aac"], ["a.mov", "b.mov"], ["a.mp3", "b.mp3"]] {
        for name in names { try? Data("not really media".utf8).write(to: URL(fileURLWithPath: desk + "/" + name)) }
        let files = names.map(file)
        let offered = offer(files)
        check(!offered.main.isEmpty, "drop tools: \(names.joined(separator: " + ")) has a chip")
        for chip in (offered.main + offered.more) where chip.makesFile {
            let failure = run(call(chip, files)) ?? ""
            check(failure.hasPrefix("couldn't convert") || failure.hasPrefix("couldn't merge"),
                  "drop tools: “\(chip.label)” on \(names.joined(separator: " + ")) is a call aris-tools takes on (\(failure))")
        }
    }
    try? Data("not really media".utf8).write(to: URL(fileURLWithPath: desk + "/a.m4a"))
    check(run(["convert", desk + "/a.m4a", "--to", "m4a"])?.contains("already M4A") == true && offer([file("a.m4a")]).main.isEmpty,
          "drop tools: an M4A has no 변환 chip because aris-tools has nothing to make of it")
    check(run(["convert", desk + "/a.png", "--to", "png"])?.contains("already PNG") == true, "drop tools: a format the file already is would be refused, which is why it is never offered")
}

private func dropPicture() -> CGImage {
    let context = CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
    return context.makeImage()!
}

private func dropWrite(_ image: CGImage, to path: String, type: String) -> Bool {
    guard let writer = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, type as CFString, 1, nil) else { return false }
    CGImageDestinationAddImage(writer, image, nil)
    return CGImageDestinationFinalize(writer)
}

/// Black words on white, drawn with Core Text into `context`.
private func dropDraw(_ words: String, size: CGFloat, at point: CGPoint, in context: CGContext) {
    let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: words, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
    context.textPosition = point
    CTLineDraw(line, context)
}

private func dropWritePDF(_ path: String, words: String?) {
    var box = CGRect(x: 0, y: 0, width: 300, height: 200)
    guard let consumer = CGDataConsumer(url: URL(fileURLWithPath: path) as CFURL), let pdf = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
    pdf.beginPage(mediaBox: &box)
    pdf.setFillColor(CGColor(gray: 0.9, alpha: 1))
    pdf.fill(CGRect(x: 10, y: 10, width: 40, height: 40))
    if let words { dropDraw(words, size: 24, at: CGPoint(x: 20, y: 100), in: pdf) }
    pdf.endPage()
    pdf.closePDF()
}

// MARK: - What the app finds by opening a file

private func dropReadingTests() {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-drop-reading-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let typed = folder.appendingPathComponent("typed.pdf").path, scanned = folder.appendingPathComponent("scanned.pdf").path
    dropWritePDF(typed, words: "Quarterly report")
    dropWritePDF(scanned, words: nil)
    check(ArisDropReading.pdfHasText(typed) && !ArisDropReading.pdfHasText(scanned) && !ArisDropReading.pdfHasText(folder.appendingPathComponent("none.pdf").path),
          "drop reading: a PDF with words has them, a PDF of pictures alone doesn't, and neither does one that isn't there")
    check(ArisAttachmentText.extract(URL(fileURLWithPath: typed))?.contains("Quarterly report") == true, "drop reading: and those words are what 요약 sends")
    // A picture's words, read on this Mac.
    let context = CGContext(data: nil, width: 900, height: 300, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 900, height: 300))
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    dropDraw("HELLO ARIS 2026", size: 72, at: CGPoint(x: 40, y: 120), in: context)
    let sign = folder.appendingPathComponent("sign.png").path, blank = folder.appendingPathComponent("blank.png").path
    check(dropWrite(context.makeImage()!, to: sign, type: "public.png") && dropWrite(dropPicture(), to: blank, type: "public.png"), "drop reading: fixtures written")
    let words = ArisDropReading.pictureWords(sign)
    check(words.uppercased().contains("HELLO") && words.contains("2026"), "drop reading: the words in a picture are read on this Mac (\(words))")
    check(ArisDropReading.pictureWords(blank).isEmpty && ArisDropReading.pictureWords(folder.appendingPathComponent("none.png").path).isEmpty,
          "drop reading: a picture without words, or one that isn't there, has none (so no 글자 뽑기 chip)")
}

// MARK: - Wired into the notch

private func dropWiringTests() {
    let source = { (path: String) -> String in
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        return (try? String(contentsOf: tests.appendingPathComponent("../" + path), encoding: .utf8)) ?? ""
    }
    let zones = source("Aris/private/Aris/Home/ArisShelfChips.swift"), composer = source("Aris/private/Aris/Home/ArisComposer.swift")
    let model = source("Aris/private/Aris/Drop/ArisDropModel.swift")
    check(zones.contains("ArisDropModel.shared.dropped(urls)") && model.contains("attachments.add(given)"),
          "drop wiring: a drop on Aris's half goes through the chips' model, which keeps the files for the next request as before")
    check(composer.contains("ArisDropChipsView()") && composer.components(separatedBy: "ArisAttachmentText.block(for: $0, read: ArisDropModel.shared.text)").count == 3,
          "drop wiring: the chips sit in the composer, and a typed or spoken request reads the files through the guard too")
    check(model.contains("aris.endConversation()\n        aris.submitTyped(request)") && model.contains("aris.session.question == nil"),
          "drop wiring: a chip starts an ordinary typed turn in a conversation of its own, never over a turn or a card")
    check(model.contains("text(of url: URL) -> String?") && model.contains("return held ? nil : ArisAttachmentText.extract(url)"),
          "drop wiring: a held file's text is never read for any request")
}
