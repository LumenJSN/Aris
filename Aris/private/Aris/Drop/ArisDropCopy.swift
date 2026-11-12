//
//  ArisDropCopy.swift
//  Aris
//
//  The words of the chips that come up when a file is dropped on Aris: each chip's label, the request it makes in
//  The user's place (shown as their words on the turn's line, and what the brain reads), and the short lines under the
//  chips. Korean or English with the rest of the notch (ArisUILanguage). Foundation only, so it is tested.
//

import Foundation

enum ArisDropCopy {
    // MARK: - Names

    /// A format as it is shown and said: "JPG", "PDF".
    static func formatName(_ format: String) -> String { format.uppercased() }

    private static let languageNames: [String: (korean: String, english: String)] = [
        "ko": ("한국어", "Korean"), "en": ("영어", "English"), "ja": ("일본어", "Japanese"), "zh": ("중국어", "Chinese"),
    ]

    static func languageName(_ code: String, english: Bool) -> String {
        guard let names = languageNames[code] else { return code }
        return english ? names.english : names.korean
    }

    // MARK: - Labels

    /// `main`: on the first row (it says what it does); false: an alternative on the second row (only its target).
    static func label(_ act: ArisDropChip.Act, files: [ArisDropFile], main: Bool, english: Bool) -> String {
        let several = files.count > 1
        switch act {
        case .summarize: return english ? "Summarize" : "요약"
        case .extractText: return english ? "Get the text" : "글자 뽑기"
        case .allowReading: return english ? "Read it anyway" : "읽어도 돼요"
        case .translate(let to, _):
            let name = languageName(to, english: english)
            if !main { return english ? "to \(name)" : "\(name)로" }
            return english ? "Translate to \(name)" : "\(name)로 번역"
        case .convert(let to):
            let name = formatName(to)
            if to == "m4a", files.first?.kind == .video { return english ? "Sound only (M4A)" : "소리만 M4A로" }
            if !main { return english ? "to \(name)" : "\(name)로" }
            if several { return english ? "All to \(name)" : "한꺼번에 \(name)로" }
            return english ? "Convert to \(name)" : "\(name)로 변환"
        case .merge:
            let mixed = files.contains { $0.kind == .image }
            if mixed { return english ? "Merge into one PDF" : "PDF 하나로 합치기" }
            return english ? "Merge into one" : "하나로 합치기"
        }
    }

    // MARK: - Requests

    /// What pressing the chip asks, as the user would say it. Nil for a chip that asks nothing (읽어도 돼요).
    static func words(_ act: ArisDropChip.Act, files: [ArisDropFile], english: Bool) -> String? {
        let several = files.count > 1, kind = files.first?.kind
        switch act {
        case .allowReading: return nil
        case .summarize:
            if english { return several ? "Summarize these files" : "Summarize this file" }
            return several ? "이 파일들 요약해 줘" : "이 파일 요약해 줘"
        case .extractText:
            return english ? "Write out the text in this picture" : "이 그림에 있는 글자 그대로 적어 줘"
        case .translate(let to, let orElse):
            return translate(to: to, orElse: orElse, english: english)
        case .convert(let to):
            return convert(to: formatName(to), kind: kind, several: several, english: english)
        case .merge:
            return merge(kind: kind, english: english)
        }
    }

    private static func translate(to: String, orElse: String?, english: Bool) -> String {
        let name = languageName(to, english: english)
        let first = english ? "Translate this file into \(name)" : "이 파일 \(name)로 번역해 줘"
        guard let other = orElse.map({ languageName($0, english: english) }) else { return first }
        return english ? "\(first). If it is already in \(name), translate it into \(other)." : "\(first). 이미 \(name)면 \(other)로 번역해 줘."
    }

    private static func convert(to name: String, kind: ArisDropKind?, several: Bool, english: Bool) -> String {
        if kind == .video, name == "M4A" {
            if english { return several ? "Take just the sound out of these videos as M4A files" : "Take just the sound out of this video as an M4A file" }
            // "오디오", never "소리": with the 4 of M4A the local volume rule would take "소리 … 4" for the Mac's volume.
            return several ? "이 영상들에서 오디오만 M4A로 뽑아 줘" : "이 영상에서 오디오만 M4A로 뽑아 줘"
        }
        if kind == .pdf {
            if english { return several ? "Turn each page of these PDFs into a \(name) picture" : "Turn each page of this PDF into a \(name) picture" }
            return several ? "이 PDF들을 쪽마다 \(name) 그림으로 바꿔 줘" : "이 PDF를 쪽마다 \(name) 그림으로 바꿔 줘"
        }
        if english { return several ? "Convert these files to \(name)" : "Convert this file to \(name)" }
        return several ? "이 파일들 한꺼번에 \(name)로 바꿔 줘" : "이 파일 \(name)로 바꿔 줘"
    }

    private static func merge(kind: ArisDropKind?, english: Bool) -> String {
        switch kind {
        case .video: return english ? "Merge these videos into one" : "이 영상들 하나로 합쳐 줘"
        case .audio: return english ? "Merge these recordings into one" : "이 녹음 파일들 하나로 합쳐 줘"
        default: return english ? "Merge these files into one PDF" : "이 파일들 PDF 하나로 합쳐 줘"
        }
    }

    /// Added to the files' note of a request that makes new files, for the brain: the files are these paths, never
    /// what is selected in Finder or what sits on the shelf.
    static let pathsAside = ". 변환하거나 합칠 때는 이 경로를 그대로 써요 (--finder, --shelf 아님)"

    /// What goes before a picture's words in the files' text: they were read off the picture on this Mac.
    static let readFromPicture = "(그림에서 읽은 글자예요)"

    // MARK: - Lines under the chips

    static func held(_ hold: ArisDropGuard.Hold, english: Bool) -> String {
        switch hold {
        case .secretName:
            return english ? "The name looks like a password or key file, so Aris hasn't read it."
                : "이름이 비밀번호·키 파일처럼 보여서 아직 읽지 않았어요."
        case .protectedPlace:
            return english ? "It is in a place Aris never touches (keys, settings), so it isn't read."
                : "Aris가 손대지 않는 곳(키·설정)에 있는 파일이라 읽지 않아요."
        }
    }

    /// More were dropped than Aris takes at once.
    static func cut(dropped: Int, kept: Int, english: Bool) -> String {
        english ? "Took \(kept) of the \(dropped) files: \(kept) at a time is the most." : "\(dropped)개 중 \(kept)개만 받았어요. 한 번에 \(kept)개까지예요."
    }

    /// Files that are no longer where they were when a chip was pressed.
    static func gone(_ names: [String], english: Bool) -> String {
        let first = names.first ?? "", more = names.count - 1
        if english { return more > 0 ? "\(first) and \(more) more aren't there any more. Drop them again." : "\(first) isn't there any more. Drop it again." }
        return more > 0 ? "\(first) 외 \(more)개가 없어졌어요. 다시 끌어다 놓아 주세요." : "\(first) 파일이 없어졌어요. 다시 끌어다 놓아 주세요."
    }

    /// A chip that sends the file's words found none in it after all.
    static func noText(english: Bool) -> String {
        english ? "Aris found no text it can read in it." : "읽을 수 있는 글을 찾지 못했어요."
    }
}
