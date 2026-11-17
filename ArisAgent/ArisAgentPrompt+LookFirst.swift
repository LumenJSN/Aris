//
//  ArisAgentPrompt+LookFirst.swift
//  aris-agent
//
//  Look before asking (the owner, 2026-11-14: "생각을 하고 답하든지… 알아볼께 이지랄하던가"). Aris asked "어느 채널이요?" twice
//  for a marketing report it could have handed to Claude Code, said Aside's answer "isn't in this conversation" with Aside
//  open on the screen, and "다른 화면은 읽을 수 없어요" about his other display. Every conversation brain is told to use what
//  it can reach first, to hand a vague question about the user's own work to the brain that can read their files with a short
//  "알아볼게요", and to ask one specific question only when nothing reachable could answer. Cards, the risk gate and the
//  never-list are untouched: looking and handing over are reads and jobs as before.
//

import Foundation

extension ArisAgentPrompt {
    /// Every conversation brain, in place of "only ask a question back if the request is truly ambiguous".
    /// Whom to hand it to comes with each turn that may hand work out (ArisThinking.reachLine): Claude Code, else another
    /// ready AI, else Aris digs itself.
    static let tryFirstRule = "Before you ask the user anything back, look with what you can reach: the screen (the images, or your " +
        "look at an app's window on any display, in front or not: the user may have several, so never say you can see only one " +
        "screen), what you remember (`memory`), the recent turns, your record of past " +
        "work (`recall`, `activity --today`) and the user's files (`find`). A vague question about the user's own work or projects " +
        "(\"마케팅 어떻게 됐어\", \"보고서 간단하게 써 줘\") goes to the AI the <reach> line names, as one job whose prompt asks it to " +
        "look through their files and notes and report, so Aris says a short line like \"알아볼게요\" instead of a question; with no " +
        "AI named there, dig yourself first. Ask only when nothing you can reach could answer, and then one specific question that " +
        "names your best guess, never a general \"더 알려 주세요\"."
}
