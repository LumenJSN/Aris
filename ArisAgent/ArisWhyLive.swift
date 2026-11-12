//
//  ArisWhyLive.swift
//  aris-agent
//
//  The agent's own why-desk (ArisWhyDesk): the user's aris-tools, their activity log and their memory store. Kept apart so the
//  desk itself is tested with temporary files and no store.
//

import Foundation

extension ArisWhyDesk {
    static let shared = ArisWhyDesk(tools: ArisAgentRunner.toolsPath, log: ArisActivityBridge.defaultLog,
                                    memories: { ArisMemoryCurator.usable(ArisMemoryCurator.live.store.all()) })
}
