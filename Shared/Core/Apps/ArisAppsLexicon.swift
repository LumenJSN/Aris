//
//  ArisAppsLexicon.swift
//  Shared/Core/Apps
//
//  The meaning-bearing words of commands in Korean and English, as data: a request "새 창 열어" meets the menu item
//  "New Window" (and "새로운 윈도우" meets "새 윈도우") because both sides map to the same concepts. Each row is one
//  concept and every way it is said; to teach a word, add it to its row. Words that only make a request polite or
//  name the app carry nothing and are dropped. Pure.
//

import Foundation

extension ArisApps {
    enum Lexicon {
        /// concept → its words (Korean and English; folded with Text.key when compared).
        static let concepts: [String: [String]] = [
            "new": ["새", "새로운", "새로", "신규", "만들기", "만들어", "생성", "new", "create", "make"],
            "add": ["추가", "더하기", "넣기", "add", "insert"],
            "open": ["열기", "열어", "오픈", "open"],
            "close": ["닫기", "닫아", "close"],
            "save": ["저장", "세이브", "save"],
            "print": ["인쇄", "프린트", "출력", "print"],
            "undo": ["실행취소", "되돌리기", "되돌려", "undo"],
            "redo": ["실행복귀", "다시실행", "redo"],
            "cut": ["오려두기", "잘라내기", "cut"],
            "copy": ["복사", "카피", "copy"],
            "paste": ["붙여넣기", "붙여", "paste"],
            "all": ["전체", "모두", "전부", "all", "everything"],
            "select": ["선택", "select"],
            "find": ["찾기", "찾아", "검색", "find", "search", "look"],
            "replace": ["바꾸기", "대치", "replace"],
            "delete": ["삭제", "지우기", "지워", "제거", "delete", "remove", "erase"],
            "window": ["창", "윈도우", "window"],
            "tab": ["탭", "tab"],
            "document": ["문서", "도큐먼트", "document", "doc"],
            "folder": ["폴더", "folder", "directory"],
            "file": ["파일", "file"],
            "note": ["메모", "노트", "note"],
            "reminder": ["미리알림", "리마인더", "할일", "reminder", "todo"],
            "event": ["일정", "이벤트", "약속", "event", "appointment"],
            "message": ["메시지", "메세지", "문자", "message", "text"],
            "mail": ["메일", "이메일", "편지", "mail", "email"],
            "send": ["보내기", "보내", "전송", "send", "submit"],
            "reply": ["답장", "회신", "reply", "respond"],
            "forward": ["전달", "forward"],
            "play": ["재생", "틀어", "틀기", "플레이", "play", "resume"],
            "pause": ["일시정지", "멈춤", "멈춰", "정지", "pause", "stop"],
            "next": ["다음", "넘겨", "next", "skip"],
            "previous": ["이전", "previous", "prev"],
            "back": ["뒤로", "back"],
            "shuffle": ["셔플", "무작위", "랜덤", "shuffle", "random"],
            "repeat": ["반복", "repeat", "loop"],
            "volume": ["볼륨", "음량", "소리", "volume", "sound"],
            "up": ["올려", "높여", "크게", "up", "increase", "louder"],
            "down": ["내려", "낮춰", "작게", "down", "decrease", "quieter"],
            "zoomin": ["확대", "줌인", "zoomin", "bigger", "larger", "enlarge"],
            "zoomout": ["축소", "줌아웃", "zoomout", "smaller"],
            "zoom": ["줌", "zoom"],
            "fullscreen": ["전체화면", "풀스크린", "fullscreen"],
            "minimize": ["최소화", "내려놓기", "minimize", "minimise"],
            "bold": ["굵게", "볼드", "bold"],
            "italic": ["기울임", "기울임꼴", "이탤릭", "italic"],
            "underline": ["밑줄", "underline"],
            "font": ["서체", "폰트", "글꼴", "font"],
            "export": ["내보내기", "export"],
            "import": ["가져오기", "import"],
            "share": ["공유", "share"],
            "rename": ["이름변경", "이름바꾸기", "rename"],
            "duplicate": ["복제", "사본", "복사본", "duplicate"],
            "settings": ["설정", "환경설정", "preferences", "settings", "options"],
            "help": ["도움말", "help"],
            "view": ["보기", "view"],
            "show": ["보이기", "표시", "보여", "show", "display", "reveal"],
            "hide": ["숨기기", "숨겨", "가리기", "hide"],
            "quit": ["종료", "끄기", "꺼", "quit", "exit"],
            "run": ["실행", "실행해", "돌려", "run", "execute", "evaluate", "eval"],
            "history": ["기록", "방문기록", "history"],
            "bookmark": ["북마크", "즐겨찾기", "bookmark", "favorite", "favourite"],
            "reload": ["새로고침", "리로드", "reload", "refresh"],
            "sidebar": ["사이드바", "sidebar"],
            "list": ["목록", "리스트", "list"],
            "table": ["표", "테이블", "table"],
            "image": ["이미지", "사진", "그림", "image", "picture", "photo"],
            "attach": ["첨부", "attach", "attachment"],
            "spelling": ["맞춤법", "철자", "spelling", "spell"],
            "format": ["서식", "포맷", "format"],
            "account": ["계정", "account"],
            "trash": ["휴지통", "trash", "bin"],
            "empty": ["비우기", "비워", "empty"],
            "download": ["다운로드", "download", "downloads"],
            "private": ["비공개", "시크릿", "개인정보보호", "private", "incognito"],
            "go": ["이동", "가기", "가", "가줘", "go"],
            "info": ["정보", "info", "information", "inspector"],
            "chat": ["채팅", "대화", "채팅방", "chat", "conversation"],
            "call": ["통화", "전화", "call"],
            "mute": ["음소거", "뮤트", "mute"],
            "record": ["녹음", "녹화", "record"],
            "lock": ["잠금", "잠가", "lock"],
            "pin": ["고정", "pin"],
            "archive": ["보관", "아카이브", "archive"],
            "read": ["읽음", "read"],
            "playlist": ["재생목록", "플레이리스트", "playlist"],
            "song": ["노래", "곡", "음악", "song", "track", "music"],
            "contact": ["연락처", "contact"],
            "calendar": ["캘린더", "달력", "calendar"],
            "screenshot": ["스크린샷", "캡처", "screenshot", "capture"],
            "page": ["페이지", "page"],
            "text": ["텍스트", "글자", "글", "text"],
            "address": ["주소", "주소창", "address", "location", "url"],
        ]

        /// Words that only make a request polite or say "do it": dropped before matching.
        static let filler: Set<String> = ["해줘", "해", "줘", "좀", "주세요", "해주세요", "하기", "하자", "할래", "please", "the", "a", "an", "to",
                                          "in", "on", "of", "for", "my", "it", "this", "that", "and", "with", "now", "then", "거", "것", "이거", "그거"]

        /// Word key → its concepts.
        static let index: [String: Set<String>] = {
            var index: [String: Set<String>] = [:]
            for (concept, words) in concepts { for word in words { index[Text.key(word), default: []].insert(concept) } }
            return index
        }()

        /// The concepts a word stands for: its key, then without a trailing particle, then a Hangul compound split into
        /// known words ("새창" → 새 + 창).
        static func meanings(_ word: String) -> Set<String> {
            for form in Text.forms(word) {
                if let found = index[form] { return found }
            }
            let letters = Array(Text.key(word))
            guard Text.hasHangul(word), letters.count >= 2, letters.count <= 12 else { return [] }
            for cut in stride(from: letters.count - 1, through: 1, by: -1) {
                let head = String(letters[..<cut]), tail = String(letters[cut...])
                if let first = index[head] {
                    let rest = meanings(tail)
                    if !rest.isEmpty { return first.union(rest) }
                }
            }
            return []
        }

        /// Every piece folded, filler kept (for the joins of neighbours).
        static func pieces(_ text: String) -> [String] {
            text.precomposedStringWithCanonicalMapping.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
                .map(Text.key).filter { !$0.isEmpty }
        }

        /// Words and the joins of neighbours ("실행 취소" → 실행, 취소, 실행취소; "Zoom In" → zoom, zoomin), so a spaced
        /// phrase meets its compound.
        static func terms(_ text: String) -> [String] {
            let all = pieces(text)
            let joins = zip(all, all.dropFirst()).map { $0 + $1 }
            return words(text) + joins
        }

        /// The words a request asks for, a spaced compound that means something as one ("전체 화면", "실행 취소") taken
        /// as one word.
        static func units(_ text: String) -> [String] {
            let all = pieces(text)
            var out: [String] = [], at = 0
            while at < all.count {
                if at + 1 < all.count, Self.index[all[at] + all[at + 1]] != nil {
                    out.append(all[at] + all[at + 1])
                    at += 2
                    continue
                }
                if !filler.contains(all[at]) { out.append(all[at]) }
                at += 1
            }
            return out
        }

        /// A phrase's meaning-bearing words (folded), filler dropped.
        static func words(_ text: String) -> [String] {
            let pieces = text.precomposedStringWithCanonicalMapping.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
            return pieces.map(Text.key).filter { !$0.isEmpty && !filler.contains($0) }
        }
    }
}
