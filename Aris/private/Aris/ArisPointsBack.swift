//
//  ArisPointsBack.swift
//  Aris (also built into aris-agent)
//
//  Words that name nothing by themselves and only point back at what was said or shown: "that", "this one", "it",
//  "them", "the above", "the same thing", "그거", "이거", "방금 그거". What they mean is in the conversation, which
//  only the AI has, so a thing named by nothing else is never the argument of something Aris does by itself (third VM
//  run, bug A: after a weather answer, "add that to my to-dos" saved a to-do called "that"). The rule is one place for
//  every local act that takes words: a to-do added or ticked, an app opened, a step put into a routine. Foundation
//  only, so it is tested.
//

import Foundation

enum ArisPointsBack {
    private static let pointer = #"(?:that|this|it|them|those|these|the\s+above|the\s+same|the\s+(?:former|latter)|the\s+(?:last|previous|other)\s+(?:one|ones|thing|things)|what\s+(?:you|i|we)\s+(?:just\s+)?(?:said|told\s+(?:me|you)|mentioned|found|wrote|showed\s+me))"#
    private static let english = #"^(?:(?:all|both|each|any|some|one|just|only)\s+(?:of\s+)?)*"# + pointer
        + #"(?:\s+(?:one|ones|thing|things|stuff|answer|reply|result|results|info|information))?"#
        + #"(?:\s+(?:too|also|as\s+well|again|there|here|above|up\s+there|all|both|please|now|you\s+(?:just\s+)?(?:said|mentioned|found|showed\s+me)))*$"#
    private static let korean = #"^(?:(?:방금|아까|좀\s?전에?|위에?|위의|앞에?|앞의|지금)\s*)?(?:(?:말한|말해\s?준|알려\s?준|찾은|찾아\s?준|보여\s?준)\s*)?"#
        + #"(?:(?:그|이|저|요|고)\s?(?:거|것|걸|건|게|내용|얘기|이야기|말|답|답변|결과|정보)|거|것|걸|같은\s?(?:거|것|걸)|얘|걔|쟤|이것저것)(?:들)?"#
        + #"(?:을|를|도|만|은|는|이|가)?(?:\s*(?:다|전부|모두|좀|그대로))*$"#
    private static let edges = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'“”‘’:,.!?-–—"))

    /// Whether `words` only point back and name nothing: true for "that", "This one", "all of those", "the same thing",
    /// "그거", "방금 그거", "이것들도"; false for anything with a name of its own ("that report for Kim", "it support",
    /// "그 회의 자료") and for nothing at all.
    static func only(_ words: String) -> Bool {
        let said = words.replacingOccurrences(of: "’", with: "'").trimmingCharacters(in: edges).lowercased()
        guard !said.isEmpty else { return false }
        return said.range(of: english, options: .regularExpression) != nil || said.range(of: korean, options: .regularExpression) != nil
    }

    /// The same for what a reminder is about: "remind me to do that", "remind me about it tomorrow" (the day is
    /// already taken off by the caller) point back as a bare "that" does.
    static func onlyAsTask(_ words: String) -> Bool {
        let said = words.trimmingCharacters(in: edges)
        if only(said) { return true }
        guard let verb = said.range(of: #"^(?:do|finish|handle|take\s+care\s+of|deal\s+with|look\s+(?:at|into)|check(?:\s+on)?)\s+"#, options: [.regularExpression, .caseInsensitive]) else { return false }
        return only(String(said[verb.upperBound...]))
    }
}
