//
//  ArisAgentInstallLive.swift
//  Aris
//
//  The real world behind ArisAgentInstaller: this XPC helper's own bundle, the user's real home, launchctl, the
//  helper's port, and the few files the install writes. Files are written beside their place and renamed over it, so
//  a link at the destination is replaced and never followed, and nothing is ever half-written.
//

import Darwin
import Foundation
import Security
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "install")

enum ArisAgentInstallLive {
    /// One install at a time.
    static let queue = DispatchQueue(label: "com.lumenjsn.aris.xpc.install")
    static let launchctlLimit: TimeInterval = 25

    static func world() -> ArisAgentInstallWorld {
        let home = ArisAgentRestart.realHome
        return ArisAgentInstallWorld(
            servicePath: Bundle.main.bundleURL.resolvingSymlinksInPath().path,
            home: home,
            uid: getuid(),
            launchctl: { run(ArisAgentKickstart.launchctl, $0) },
            listening: { listening(port: ArisAgentInstall.port) },
            sleep: { Thread.sleep(forTimeInterval: $0) },
            exists: { var info = stat(); return lstat($0, &info) == 0 },
            isFile: { var info = stat(); return lstat($0, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG },
            // The job file is small and a file of its own; a pipe, a link or anything larger at its path is not read.
            read: { ArisSafeFiles.readSmallFile($0) },
            linkTarget: { ArisSafeFiles.linkTarget($0) },
            isTranslocated: isTranslocated,
            isReadOnly: { path in
                var info = statfs()
                return statfs(path, &info) == 0 && (info.f_flags & UInt32(MNT_RDONLY)) != 0
            },
            makePrivateFolder: { ArisSafeFiles.makePrivateFolder($0) },
            write: { ArisSafeFiles.write($0, to: $1) },
            link: link,
            remove: { path in
                // Only a file or a link of its own goes; a folder at that name is left alone.
                var info = stat()
                guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) != S_IFDIR else { return }
                unlink(path)
            },
            appBuild: { app in
                (NSDictionary(contentsOfFile: "\(app)/Contents/Info.plist")?[ArisBuildInfo.plistKey] as? String)
                    .map { ArisBuildInfo.commit(plist: $0, marked: "") }
            },
            agentBuild: { ArisBuildInfo.runningAgent(in: URL(fileURLWithPath: ArisAgentInstall.dataFolder(home: home))) },
            mayKickstart: { ArisKickstartClock.shared.take() },
            note: { log.notice("\($0, privacy: .public)") },
            loadedJob: { capture(ArisAgentKickstart.launchctl, ArisAgentInstall.printArguments(uid: getuid())) },
            programOf: program(of:),
            verifies: { verifies($0) },
            isArisAgent: { verifies(file: $0, identifier: ArisAgentInstall.agentSigningId, flags: kSecCSStrictValidate | kSecCSCheckAllArchitectures) },
            othersCanWrite: { app in ArisSafeFiles.othersCanWrite(app) || ArisSafeFiles.othersCanWrite((app as NSString).deletingLastPathComponent) },
            builtAt: { app in ArisAgentInstall.builtAt(NSDictionary(contentsOfFile: "\(app)/Contents/Info.plist")?[ArisAgentInstall.builtAtKey]) })
    }

    /// The most of launchctl's print-out that is read.
    static let printLimit = 256 * 1_024

    /// launchctl's print-out for fixed arguments; nil when it could not start, failed, or ran too long.
    private static func capture(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { return nil }
        // Read while it runs (a full pipe would hold it), then wait for its end.
        let read = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var printed = Data()
        DispatchQueue.global(qos: .userInitiated).async {
            while let chunk = try? output.fileHandleForReading.read(upToCount: 65_536), !chunk.isEmpty {
                if printed.count < printLimit { printed.append(chunk) }
            }
            read.signal()
        }
        guard done.wait(timeout: .now() + launchctlLimit) == .success else {
            process.terminate()
            return nil
        }
        _ = read.wait(timeout: .now() + 2)
        return process.terminationStatus == 0 ? String(decoding: printed.prefix(printLimit), as: UTF8.self) : nil
    }

    /// The real program of a running process, as the kernel has it.
    private static func program(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        return proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : nil
    }

    /// Whether the code on disk at `path` is validly signed under `identifier` by this XPC helper's own team (with no
    /// team, an ad-hoc build: the identifier alone, as ArisXPCTrust does).
    private static func verifies(file path: String, identifier: String, flags: UInt32) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess, let code else { return false }
        var wanted: SecRequirement?
        guard SecRequirementCreateWithString(ArisXPCTrust.requirement(peer: identifier) as CFString, [], &wanted) == errSecSuccess, let wanted else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: flags), wanted) == errSecSuccess
    }

    /// The app whole (strictly, with its nested code and every sealed file) and both programs inside it.
    private static func verifies(_ app: String) -> Bool {
        verifies(file: app, identifier: ArisAgentInstall.appId, flags: kSecCSStrictValidate | kSecCSCheckNestedCode | kSecCSCheckAllArchitectures)
            && verifies(file: ArisAgentInstall.agentPath(app: app), identifier: ArisAgentInstall.agentSigningId, flags: kSecCSStrictValidate | kSecCSCheckAllArchitectures)
            && verifies(file: ArisAgentInstall.toolsPath(app: app), identifier: ArisAgentInstall.toolsSigningId, flags: kSecCSStrictValidate | kSecCSCheckAllArchitectures)
    }

    /// launchctl with fixed arguments, waited for; nil when it could not start or ran too long.
    private static func run(_ executable: String, _ arguments: [String]) -> Int32? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { return nil }
        guard done.wait(timeout: .now() + launchctlLimit) == .success else {
            process.terminate()
            return nil
        }
        return process.terminationStatus
    }

    /// Whether something accepts a TCP connection on 127.0.0.1 at `port`.
    static func listening(port: UInt16) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.stride)) == 0 }
        }
    }

    /// macOS's own answer to "is this app running from a translocated copy" (the path rule in ArisAgentInstall is the
    /// other half; either one refuses).
    private static func isTranslocated(_ path: String) -> Bool {
        typealias Call = @convention(c) (CFURL, UnsafeMutablePointer<Bool>, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Bool
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "SecTranslocateIsTranslocatedURL") else { return false }
        var translocated = false
        let asked = unsafeBitCast(symbol, to: Call.self)(URL(fileURLWithPath: path) as CFURL, &translocated, nil)
        return asked && translocated
    }

    /// A new link beside the path, renamed over whatever is at the path (a file, or an older link: replaced itself,
    /// never followed). A folder at the path is left alone and the link fails.
    private static func link(_ target: String, _ path: String) -> Bool {
        ArisSafeFiles.replaceLink(target: target, at: path)
    }
}
