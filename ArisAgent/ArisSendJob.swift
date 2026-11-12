//
//  ArisSendJob.swift
//  aris-agent
//
//  Whose work a message the agent itself sends is logged as (POST /message-tool: the agent runs `aris-tools message`
//  for a Claude turn, outside that brain's process). The conversation's send is the conversation's ("대화", as
//  ArisAgentRunner names its brain's own commands), so the notch's receipt for that turn shows it; a background job's
//  is not, so a job that sends while the user talks to Aris never puts "…에게 보냄" under their answer. Before, both were
//  logged as plain "Aris". Foundation only, so it is tested with the app's reading of the log.
//

import Foundation

enum ArisSendJob {
    /// The conversation's job in the activity log.
    static let conversation = "대화"
    /// A background job's send: the job's own title stays in ArisAgentRunner; the log files it under its brain.
    static let background = "백그라운드 작업"

    static func job(task: Bool) -> String { task ? background : conversation }
}
