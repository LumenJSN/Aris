//
//  ArisLiveSlots.swift
//  Aris
//
//  The views other branches build for AI · 모델, drawn in their places by ArisAIThinkPart (ArisLivePart). Its own file
//  so the offscreen renders, which can't link the app's packages, put a stand-in beside them.
//

import SwiftUI

/// jv-models puts its view in AI · 모델 by filling this (one line); nil draws nothing.
@MainActor
enum ArisLiveSlots {
    /// jv-models (landed): the model and effort for each role. (다른 AI로 넘기기 is a plain row: ArisSettingsSlots.fallback.)
    static var models: AnyView? { AnyView(ArisModelChoiceSection()) }
}
