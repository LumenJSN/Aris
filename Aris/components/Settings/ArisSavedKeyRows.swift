//
//  ArisSavedKeyRows.swift
//  Aris
//
//  The rows of 저장된 키 while one is cleared (tenth VM run, item 10: 지우기 cleared a key at one press, and when its
//  row went, the page moved up and the red "Aris 제거" button was under the pointer). 지우기 pressed once only asks:
//  the row offers 정말 지우기 and 취소, with 취소 where 지우기 was, so a second press at the same place takes it back.
//  A cleared key's row stays in its place, saying so with no button, for as long as the page is open, so nothing
//  below moves up under the pointer. Pure (tested); ArisAISavedKeys draws it.
//

import Foundation

struct ArisSavedKeyRows: Equatable {
    enum Mode: Equatable { case saved, confirming, cleared }

    struct Row: Equatable {
        let key: ArisAISavedKey
        let mode: Mode
    }

    /// Every key shown since the page opened, each in the place it first had.
    private(set) var shown: [ArisAISavedKey] = []
    /// The key whose 지우기 was pressed once.
    private(set) var confirming: String?

    static let ask = "지우면 이 키를 쓰는 기능이 멈춰요. 정말 지울까요?"
    static let cleared = "지웠어요"

    /// The keys saved now, taken in: a new one gets a place after the others; none loses its place.
    mutating func sync(_ saved: [ArisAISavedKey]) {
        for key in saved {
            if let index = shown.firstIndex(where: { $0.holder == key.holder }) { shown[index] = key } else { shown.append(key) }
        }
        if let confirming, !saved.contains(where: { $0.holder == confirming }) { self.confirming = nil }
    }

    /// The rows to draw: the saved keys, and the ones cleared while the page was open, in their places.
    func rows(saved: [ArisAISavedKey]) -> [Row] {
        var taken = self
        taken.sync(saved)
        return taken.shown.map { key in
            guard saved.contains(where: { $0.holder == key.holder }) else { return Row(key: key, mode: .cleared) }
            return Row(key: key, mode: key.holder == taken.confirming ? .confirming : .saved)
        }
    }

    /// How many rows there are (the section keeps its heading while any is drawn).
    func count(saved: [ArisAISavedKey]) -> Int { rows(saved: saved).count }

    /// 지우기 on a row: only asks. Nothing is cleared.
    mutating func ask(_ holder: String) { confirming = holder }

    /// 취소, or the page left.
    mutating func cancel() { confirming = nil }

    /// 정말 지우기: true only for the row that is asking (the key is then cleared by the caller).
    mutating func confirm(_ holder: String) -> Bool {
        guard confirming == holder else { return false }
        confirming = nil
        return true
    }

    /// The page closed: cleared rows go.
    mutating func reset() { self = ArisSavedKeyRows() }
}
