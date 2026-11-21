//
//  ArisAppsEffectOrder.swift
//  Shared/Core/Apps
//
//  The app layer's name for the effect class (jv-hands' ArisEffectClass) and its order, mildest first, the same order
//  as ArisEffectClass.strongest: an app call's effect is the strongest of what it can do.
//

import Foundation

extension ArisApps {
    typealias Effect = ArisEffectClass
}

extension ArisEffectClass: Comparable {
    private static let order: [ArisEffectClass] = [.observe, .changeReversible, .changePermanent, .outward, .never]
    private var rank: Int { Self.order.firstIndex(of: self) ?? Self.order.count }
    static func < (lhs: ArisEffectClass, rhs: ArisEffectClass) -> Bool { lhs.rank < rhs.rank }
}
