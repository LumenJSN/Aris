//
//  ArisBundleVersion.swift
//  Aris
//
//  The version strings shown in About and in diagnostics.
//

import Foundation

struct ArisBundleVersion {
    /// `CFBundleShortVersionString`, e.g. "2.8".
    let release: String?
    /// `CFBundleVersion`, the build number.
    let build: String?

    init(info: [String: Any]) {
        release = info["CFBundleShortVersionString"] as? String
        build = info["CFBundleVersion"] as? String
    }
}

extension Bundle {
    var releaseVersionNumber: String? { ArisBundleVersion(info: infoDictionary ?? [:]).release }
    var buildVersionNumber: String? { ArisBundleVersion(info: infoDictionary ?? [:]).build }
}
