//
//  ArisSettingsArt.swift
//  Aris
//
//  The characters the settings window draws (the app's baked sprites, given to the window; a stand-in where there
//  are none): Aris's star, Aris's face in a mood, and a teammate's face.
//

import SwiftUI

/// The characters the window draws (the app's baked sprites; a stand-in where there are none).
struct ArisSettingsArt {
    var star: (CGFloat) -> AnyView = { size in
        AnyView(Image(systemName: "star.fill").font(.system(size: size * 0.8)).foregroundStyle(Color(arisHex: 0xefdb8e)).frame(width: size, height: size))
    }
    /// Aris's face in a mood ("default", "working"), live (the 팀원 page's 미리보기 strip).
    var aris: (String, CGFloat) -> AnyView = { _, size in
        AnyView(Image(systemName: "star.fill").font(.system(size: size * 0.8)).foregroundStyle(Color(arisHex: 0xefdb8e)).frame(width: size, height: size))
    }
    /// A teammate's face; `still` holds its rest pose (picker tiles, roster rows).
    var face: (ArisCharacterLook, CGFloat, Bool) -> AnyView = { look, size, _ in
        AnyView(Circle().fill(Color(arisHexString: look.colorHex ?? "#41C4FF") ?? .blue).frame(width: size * 0.8, height: size * 0.8).frame(width: size, height: size))
    }
}

private struct ArtKey: EnvironmentKey { static let defaultValue = ArisSettingsArt() }

extension EnvironmentValues {
    var arisSettingsArt: ArisSettingsArt {
        get { self[ArtKey.self] }
        set { self[ArtKey.self] = newValue }
    }
}
