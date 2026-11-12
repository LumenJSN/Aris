//
//  ArisBuildStamp.swift
//  Aris
//
//  The commit a program was built from, as one whole string the install script can find in the program's bytes
//  without running it. In the repository it says "dev". When deploy.sh builds aris-agent and aris-tools, a generated
//  copy of this file with the real commit is compiled in its place (tests/build-agent.sh, ARIS_COMMIT); the app gets
//  its commit through Info.plist instead (ArisCommit). ArisBuildInfo reads both.
//

enum ArisBuildStamp {
    static let marked = "aris-build-commit:dev"
}
