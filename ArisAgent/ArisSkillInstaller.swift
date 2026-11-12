//
//  ArisSkillInstaller.swift
//  aris-agent
//
//  The live setup (ArisSkillSetup's installer): everything pinned and checked, everything inside the runtime folder.
//  1. uv (Astral's, a fixed release, its archive's SHA-256 checked) unpacked by Aris itself.
//  2. Python 3.12.12 through uv (uv checks its own download), with uv's cache, config and home all inside the folder:
//     no PATH links, no shell files, nothing system-wide.
//  3. SkillSpector's dependencies from wheels only (no build scripts run), every one by hash (--require-hashes, the
//     list's own SHA-256 checked), then SkillSpector itself from its tagged source archive (SHA-256 checked) with no
//     index and no dependencies, so nothing unpinned can come in.
//  A marker records the versions; the download cache is removed at the end.
//

import CryptoKit
import Foundation

enum ArisSkillPins {
    static let uvVersion = "0.13.7"
    static let uvArm = (url: "https://github.com/astral-sh/uv/releases/download/0.13.7/uv-aarch64-apple-darwin.tar.gz",
                        sha256: "81b811b57e4624df7ed3aac148e0359100d9962f3d9dce00aec533dc2e086731")
    static let uvIntel = (url: "https://github.com/astral-sh/uv/releases/download/0.13.7/uv-x86_64-apple-darwin.tar.gz",
                          sha256: "20c47e4c1f630b8abaff8c291fa9b9aa300fef92c4fbff95adf198b55287cda7")
    static let python = "3.12.12"
    static let skillSpectorVersion = "2.13.4"
    static let skillSpector = (url: "https://github.com/NVIDIA/skillspector/archive/refs/tags/v2.13.4.tar.gz",
                               sha256: "0dae54aa348a2fc9dcfd870e4f73c1896c91eded7b4907a47ea596761acf3bfd")
    /// The hashed requirements list (ArisSkills/runtime-requirements.txt): in the app's Resources beside the built-in skill.
    static let requirementsSHA256 = "c55ed7adc70d8e9f6128ff09f8c5a689ef65bc71f8bbeed56ffb84a518400a6d"
    /// About what the setup downloads: uv 14, Python 17, the wheels 42, SkillSpector 2.
    static let downloadMB = 75
    static let downloadHosts: Set<String> = ["github.com", "codeload.github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com"]

    static var marker: String { "uv \(uvVersion), python \(python), skillspector \(skillSpectorVersion), requirements \(requirementsSHA256)" }

    static func requirementsFile(home: String) -> URL {
        ArisAppBundle.skillsFolder(home: home).appendingPathComponent("runtime-requirements.txt")
    }

    static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

final class ArisSkillInstaller: ArisSkillInstalling {
    private let downloader: ArisSkillDownloading
    private let home: String

    init(downloader: ArisSkillDownloading = ArisSkillDownloader(), home: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        self.downloader = downloader
        self.home = home
    }

    func isInstalled(_ folder: URL) -> Bool {
        let marker = (try? String(contentsOf: folder.appendingPathComponent("ready.txt"), encoding: .utf8)) ?? ""
        return marker == ArisSkillPins.marker && FileManager.default.isExecutableFile(atPath: folder.appendingPathComponent("venv/bin/skillspector").path)
            && FileManager.default.isExecutableFile(atPath: folder.appendingPathComponent("venv/bin/python").path)
            && FileManager.default.fileExists(atPath: ArisSkillManifestFile.file(home: home).path)
    }

    func verify(_ folder: URL) -> Bool {
        guard let saved = try? String(contentsOf: ArisSkillManifestFile.file(home: home), encoding: .utf8) else { return false }
        return ArisSkillManifestFile.make(folder) == saved
    }

    /// uv's environment: every place it writes inside `folder`.
    static func environment(_ folder: URL) -> [String: String] {
        let at = { (name: String) in folder.appendingPathComponent(name).path }
        return ["HOME": at("home"), "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8", "TMPDIR": at("tmp"),
                "UV_CACHE_DIR": at("cache"), "UV_PYTHON_INSTALL_DIR": at("python"), "UV_PYTHON_BIN_DIR": at("python/bin"),
                "UV_TOOL_DIR": at("tools"), "UV_TOOL_BIN_DIR": at("tools/bin"), "UV_NO_CONFIG": "1", "UV_NO_PROGRESS": "1",
                "XDG_CACHE_HOME": at("home/.cache"), "XDG_CONFIG_HOME": at("home/.config"),
                "XDG_DATA_HOME": at("home/.local/share"), "XDG_BIN_HOME": at("home/.local/bin")]
    }

    func install(into folder: URL, progress: @escaping (ArisSkillSetupProgress) -> Void, cancelled: @escaping () -> Bool) -> Result<Void, ArisSkillWhy> {
        let total = ArisSkillPins.downloadMB
        let report = { (step: String, mb: Double) in progress(ArisSkillSetupProgress(step: step, doneMB: Int(mb.rounded(.down)), totalMB: total)) }
        for name in ["home", "tmp", "cache", "python/bin", "tools/bin"] {
            try? FileManager.default.createDirectory(at: folder.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        let env = Self.environment(folder)
        // 1. uv
        let pin = isIntel ? ArisSkillPins.uvIntel : ArisSkillPins.uvArm
        report("uv 받는 중", 0)
        guard case .success(let uvArchive) = downloader.fetch(URL(string: pin.url)!, maxBytes: 40 * 1_048_576, hosts: ArisSkillPins.downloadHosts,
                                                              progress: { report("uv 받는 중", Double($0) / 1_048_576) }) else {
            return .failure(Self.cutLine(0))
        }
        guard ArisSkillPins.sha256(uvArchive) == pin.sha256 else { return .failure("받은 uv가 고정한 버전과 달라서 멈췄어요.") }
        guard case .success(let tar) = ArisSkillArchive.gunzip(uvArchive, limit: 120 * 1_048_576), case .success(let entries) = ArisSkillArchive.untar(tar),
              let binary = entries.first(where: { ($0.path as NSString).lastPathComponent == "uv" }) else { return .failure("uv를 풀지 못했어요.") }
        let uv = folder.appendingPathComponent("uv")
        guard FileManager.default.createFile(atPath: uv.path, contents: binary.data, attributes: [.posixPermissions: 0o755]) else {
            return .failure("uv를 저장하지 못했어요.")
        }
        guard !cancelled() else { return .failure("취소했어요.") }
        // 2. Python
        var base = 14.0
        let python = watching(folder.appendingPathComponent("python"), fullMB: 56, worthMB: 17) { report("파이썬 설치 중", base + $0) } run: {
            ArisSkillProcess.run(uv.path, ["python", "install", ArisSkillPins.python, "--no-bin"], environment: env, timeout: 600, cancelled: cancelled)
        }
        guard python.ok else { return .failure(Self.cutLine(Int(base))) }
        let venv = ArisSkillProcess.run(uv.path, ["venv", "--python", ArisSkillPins.python, "--managed-python", folder.appendingPathComponent("venv").path],
                                        environment: env, timeout: 120, cancelled: cancelled)
        guard venv.ok else { return .failure("파이썬 환경을 만들지 못했어요.") }
        base += 17
        // 3. SkillSpector's dependencies, by hash, wheels only.
        let requirements = ArisSkillPins.requirementsFile(home: home)
        guard let list = FileManager.default.contents(atPath: requirements.path), ArisSkillPins.sha256(list) == ArisSkillPins.requirementsSHA256 else {
            return .failure("고정한 설치 목록이 바뀌어 있어서 멈췄어요. Aris를 다시 설치해 주세요.")
        }
        let pythonPath = folder.appendingPathComponent("venv/bin/python").path
        let wheels = watching(folder.appendingPathComponent("cache"), fullMB: 135, worthMB: 42) { report("SkillSpector 설치 중", base + $0) } run: {
            ArisSkillProcess.run(uv.path, ["pip", "install", "--python", pythonPath, "--require-hashes", "--only-binary", ":all:", "-r", requirements.path],
                                 environment: env, timeout: 900, cancelled: cancelled)
        }
        guard wheels.ok else { return .failure(Self.cutLine(Int(base))) }
        base += 42
        guard !cancelled() else { return .failure("취소했어요.") }
        // SkillSpector itself, from its tag's archive.
        guard case .success(let source) = downloader.fetch(URL(string: ArisSkillPins.skillSpector.url)!, maxBytes: 20 * 1_048_576,
                                                           hosts: ArisSkillPins.downloadHosts, progress: { report("SkillSpector 설치 중", base + Double($0) / 1_048_576) }) else {
            return .failure(Self.cutLine(Int(base)))
        }
        guard ArisSkillPins.sha256(source) == ArisSkillPins.skillSpector.sha256 else { return .failure("받은 SkillSpector가 고정한 버전과 달라서 멈췄어요.") }
        let sourceFolder = folder.appendingPathComponent("src", isDirectory: true)
        guard case .success(let sourceTar) = ArisSkillArchive.gunzip(source), case .success(let files) = ArisSkillArchive.untar(sourceTar),
              case .success = ArisSkillArchive.write(files, to: sourceFolder) else { return .failure("SkillSpector를 풀지 못했어요.") }
        let own = ArisSkillProcess.run(uv.path, ["pip", "install", "--python", pythonPath, "--no-deps", "--no-build-isolation", "--no-index", sourceFolder.path],
                                       environment: env, timeout: 300, cancelled: cancelled)
        guard own.ok else { return .failure("SkillSpector를 설치하지 못했어요.") }
        let check = ArisSkillProcess.run(folder.appendingPathComponent("venv/bin/skillspector").path, ["--version"], environment: env, timeout: 60)
        guard check.ok, check.stdout.contains(ArisSkillPins.skillSpectorVersion) else { return .failure("SkillSpector가 실행되지 않아요.") }
        for leftover in ["cache", "src", "tmp"] { try? FileManager.default.removeItem(at: folder.appendingPathComponent(leftover)) }
        try? FileManager.default.createDirectory(at: folder.appendingPathComponent("tmp"), withIntermediateDirectories: true)
        guard (try? ArisSkillPins.marker.write(to: folder.appendingPathComponent("ready.txt"), atomically: true, encoding: .utf8)) != nil else {
            return .failure("설치를 마무리하지 못했어요.")
        }
        // Read-only from here on, and its hash manifest kept in Aris's own folder: every scan checks it first (I6).
        ArisSkillManifestFile.seal(folder)
        let manifest = ArisSkillManifestFile.file(home: home)
        try? FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? FileManager.default.removeItem(at: manifest)
        guard FileManager.default.createFile(atPath: manifest.path, contents: Data(ArisSkillManifestFile.make(folder).utf8), attributes: [.posixPermissions: 0o600]) else {
            return .failure("설치를 마무리하지 못했어요.")
        }
        report("다 됐어요", Double(total))
        return .success(())
    }

    static func cutLine(_ mb: Int) -> ArisSkillWhy { ArisSkillWhy("다운로드가 \(mb)MB에서 끊겼어요. 인터넷 연결을 확인하고 다시 시도해 주세요.") }

    private var isIntel: Bool {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) } == "x86_64"
    }

    /// Runs `run` while reporting how far `folder` has grown (as a share of `worthMB` download megabytes).
    private func watching(_ folder: URL, fullMB: Double, worthMB: Double, report: @escaping (Double) -> Void,
                          run: () -> ArisSkillProcessResult) -> ArisSkillProcessResult {
        let stop = ArisCancelFlag()
        DispatchQueue.global(qos: .utility).async {
            while !stop.isSet {
                report(min(worthMB, Self.megabytes(folder) / fullMB * worthMB))
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        let result = run()
        stop.set()
        return result
    }

    static func megabytes(_ folder: URL) -> Double {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var bytes = 0
        for case let url as URL in walker { bytes += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        return Double(bytes) / 1_048_576
    }
}

/// The installed runtime's hash manifest: every file of uv, Python and the scanner's venv with its SHA-256 (links by
/// where they point), kept in ~/.config/aris/aris, never inside the runtime. `tmp` and `home` (scans' scratch) aren't in it.
enum ArisSkillManifestFile {
    static let sealed = ["uv", "python", "venv", "ready.txt"]

    static func file(home: String) -> URL {
        URL(fileURLWithPath: home).appendingPathComponent(".config/aris/aris/skills-runtime.manifest")
    }

    static func make(_ folder: URL) -> String {
        var lines: [String] = []
        for top in sealed {
            let root = folder.appendingPathComponent(top)
            var info = stat()
            guard lstat(root.path, &info) == 0 else { lines.append("missing \(top)"); continue }
            if info.st_mode & S_IFMT == S_IFREG { lines.append(line(root, top)); continue }
            let names = (FileManager.default.subpaths(atPath: root.path) ?? []).sorted()
            for name in names {
                let url = root.appendingPathComponent(name)
                guard lstat(url.path, &info) == 0 else { continue }
                switch info.st_mode & S_IFMT {
                case S_IFLNK: lines.append("link \(top)/\(name) -> " + ((try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) ?? "?"))
                case S_IFREG: lines.append(line(url, top + "/" + name))
                case S_IFDIR: lines.append("dir \(top)/\(name)")
                default: lines.append("other \(top)/\(name)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func line(_ url: URL, _ name: String) -> String {
        let data = FileManager.default.contents(atPath: url.path) ?? Data()
        return ArisSkillPins.sha256(data) + "  " + name
    }

    /// Takes write access away from everything in the manifest.
    static func seal(_ folder: URL) {
        for top in sealed {
            let root = folder.appendingPathComponent(top)
            for name in [""] + (FileManager.default.subpaths(atPath: root.path) ?? []) {
                let url = name.isEmpty ? root : root.appendingPathComponent(name)
                var info = stat()
                guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT != S_IFLNK else { continue }
                _ = chmod(url.path, info.st_mode & 0o555)
            }
        }
    }
}
