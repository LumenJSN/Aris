//
//  ArisBlur.swift
//  Aris
//
//  A behind-window blur for SwiftUI (the notch glass before macOS 26's glass effect).
//

import AppKit
import SwiftUI

enum ArisBlur {
    /// Always active (not only in the key window) and emphasised.
    static func configure(_ view: NSVisualEffectView, material: NSVisualEffectView.Material,
                          blending: NSVisualEffectView.BlendingMode) {
        view.material = material
        view.blendingMode = blending
        view.state = .active
        view.isEmphasized = true
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        ArisBlur.configure(view, material: material, blending: blendingMode)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        ArisBlur.configure(view, material: material, blending: blendingMode)
    }
}
