//
//  ArisReportLine+Route.swift
//  aris-agent
//
//  POST /report-line, live: the sealed one-shot on the conversation's brain (or the first one installed).
//

import Foundation

extension ArisReportLine {
    static func route(_ object: [String: Any], reply: @escaping (String, Data) -> Void) {
        guard let title = object["title"] as? String, let result = object["result"] as? String, !result.isEmpty else {
            return reply("400 Bad Request", Data())
        }
        let recent = object["recent"] as? String ?? ""
        let korean = object["korean"] as? Bool ?? true
        let requested = ArisBrain.named(object["brain"] as? String)
        let brain = ArisSealedOneShot.available(requested) ? requested : ArisBrain.allCases.first(where: ArisSealedOneShot.available)
        DispatchQueue.global(qos: .userInitiated).async {
            let started = Date()
            let line = brain.flatMap {
                cleaned(ArisSealedOneShot(environment: ArisAgentRunner.environment()).ask($0, instruction: instruction(korean: korean),
                                                                                        input: input(title: title, result: result, recent: recent), timeout: timeout))
            }
            try? FileHandle.standardError.write(contentsOf: Data("aris-agent: report line \(line == nil ? "none" : "worded") in \(Int(Date().timeIntervalSince(started) * 1000)) ms\n".utf8))
            reply("200 OK", (try? JSONSerialization.data(withJSONObject: ["line": line.map { $0 as Any } ?? NSNull()])) ?? Data("{}".utf8))
        }
    }
}
