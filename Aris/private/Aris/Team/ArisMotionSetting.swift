//
//  ArisMotionSetting.swift
//  Aris
//
//  모션 줄이기: the characters hold still (no turn, no poke, no glance, no lift); only their poses cross-fade. The
//  system's Reduce Motion does the same (ArisCharacterView reads both).
//

import Defaults

extension Defaults.Keys {
    static let arisReduceMotion = Key<Bool>("arisReduceMotion", default: false)
}
