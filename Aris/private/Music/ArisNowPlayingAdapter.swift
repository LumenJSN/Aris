//
//  ArisNowPlayingAdapter.swift
//  Aris
//
//  The system's Now Playing, read through the bundled mediaremote-adapter (ungive, BSD-3-Clause): the system Perl
//  runs its script with its framework and prints now-playing changes as JSON lines. Transport goes in-process to
//  Apple's MediaRemote framework (loaded at run time); only if that can't be loaded or refuses a command does the
//  adapter's own `send` carry it. A self-test (with the bundled test client) says whether reading works here.
//

import Foundation

/// Where the adapter's pieces sit in the app bundle.
struct ArisAdapterFiles {
    static let perl = URL(fileURLWithPath: "/usr/bin/perl")

    let script: URL
    let framework: URL
    let testClient: URL

    /// The bundled files, or nil if any is missing.
    static func bundled(_ bundle: Bundle = .main) -> ArisAdapterFiles? {
        guard let resources = bundle.resourceURL, let frameworks = bundle.privateFrameworksURL else { return nil }
        let files = ArisAdapterFiles(script: resources.appendingPathComponent("mediaremote-adapter.pl"),
                                     framework: frameworks.appendingPathComponent("MediaRemoteAdapter.framework"),
                                     testClient: resources.appendingPathComponent("MediaRemoteAdapterTestClient"))
        let manager = FileManager.default
        guard [files.script, files.framework, files.testClient].allSatisfy({ manager.fileExists(atPath: $0.path) }) else { return nil }
        return files
    }

    func arguments(_ command: [String]) -> [String] {
        [script.path, framework.path] + command
    }

    /// Perl run before the script for the stream: a watcher that ends the stream when Aris is gone. The stream only
    /// writes when something plays, so after Aris was killed it ran on with no one to read it (VM run 2026-11-18: an
    /// orphaned mediaremote-adapter.pl beside the new Aris's). The watcher waits on standard input, a pipe only Aris
    /// writes to: when Aris ends, however it ends, the pipe closes and the stream is told to stop. It also goes when
    /// the stream ends on its own. Then the script runs as it would from the command line.
    static let streamGuard = #"""
    my $stream = $$;
    my $watcher = fork();
    if (defined $watcher && $watcher == 0) {
      close STDOUT; close STDERR;
      my $wanted = ''; vec($wanted, fileno(STDIN), 1) = 1;
      while (getppid() == $stream) {
        my $ready = select(my $got = $wanted, undef, undef, 1);
        next unless $ready > 0;
        my $read = sysread(STDIN, my $bytes, 64);
        last if !$read;
      }
      kill('TERM', $stream) if getppid() == $stream;
      exit 0;
    }
    my $script = shift @ARGV; $0 = $script;
    do $script; die $@ if $@; exit 0;
    """#

    /// The stream's arguments for the system Perl: the watcher first, then the script's own.
    func streamArguments(_ command: [String]) -> [String] {
        ["-e", Self.streamGuard, "--"] + arguments(command)
    }

    /// Runs the adapter's self-test up to `attempts` times, pausing `backoff` × the attempt number between tries;
    /// true as soon as one passes.
    func probe(attempts: Int = ArisMusicRules.probeAttempts, timeout: TimeInterval = ArisMusicRules.probeTimeout,
               backoff: Duration = ArisMusicRules.probeBackoff) async -> Bool {
        let tries = max(attempts, 1)
        for attempt in 1...tries {
            let status = await ArisProcessRun.status(Self.perl, [script.path, framework.path, testClient.path, "test"], timeout: timeout)
            if status == 0 { return true }
            Log.music.notice("Now Playing self-test \(attempt, privacy: .public) failed (\(status.map(String.init) ?? "timeout", privacy: .public))")
            if attempt < tries { try? await Task.sleep(for: backoff * attempt) }
        }
        return false
    }
}

/// Where transport commands go when they don't need the adapter.
protocol ArisTransport {
    /// True when the command was handed over.
    func send(_ command: ArisMusicCommand) -> Bool
}

/// Apple's private MediaRemote framework, loaded at run time; commands are sent in-process (no helper to start, so no
/// extra delay). Reading now-playing information this way no longer works for apps, which is why the stream uses
/// the adapter.
struct ArisMediaRemoteTransport: ArisTransport, @unchecked Sendable {
    typealias SendCommand = @convention(c) (UInt32, CFDictionary?) -> UInt8

    static let frameworkPath = "/System/Library/PrivateFrameworks/MediaRemote.framework"
    static let system: ArisMediaRemoteTransport? = load()

    /// Held so the framework (and the function pointer into it) stays loaded.
    private let bundle: CFBundle
    private let sendCommand: SendCommand

    /// The framework's `MRMediaRemoteSendCommand`, or nil if it can't be found.
    static func load(path: String = frameworkPath) -> ArisMediaRemoteTransport? {
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, URL(fileURLWithPath: path) as CFURL),
              let pointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) else {
            Log.music.error("MediaRemote send command unavailable; transport goes through the adapter")
            return nil
        }
        return ArisMediaRemoteTransport(bundle: bundle, sendCommand: unsafeBitCast(pointer, to: SendCommand.self))
    }

    /// MediaRemote's command numbers (the adapter's `send` ids are the same).
    static func id(_ command: ArisMusicCommand) -> UInt32 {
        switch command {
        case .play: 0
        case .pause: 1
        case .toggle: 2
        case .next: 4
        case .previous: 5
        }
    }

    func send(_ command: ArisMusicCommand) -> Bool {
        sendCommand(Self.id(command), nil) != 0
    }
}

@MainActor
final class ArisNowPlayingAdapter: ArisMusicSource {
    var onUpdate: ((ArisPlayback) -> Void)?
    var onFailure: (() -> Void)?

    private let files: ArisAdapterFiles
    private let transport: ArisTransport?
    private var process: Process?
    /// The stream's standard input, held for its life (ArisAdapterFiles.streamGuard).
    private var lifeline: Pipe?
    private var state = ArisAdapterState()
    private var stopping = false

    init(files: ArisAdapterFiles, transport: ArisTransport? = ArisMediaRemoteTransport.system) {
        self.files = files
        self.transport = transport
    }

    func start() {
        guard process == nil else { return }
        stopping = false
        let process = Process()
        process.executableURL = ArisAdapterFiles.perl
        process.arguments = files.streamArguments(["stream", "--micros"])
        // Its standard input is a pipe only this process holds open: the stream's watcher ends it once Aris is gone.
        let lifeline = Pipe()
        process.standardInput = lifeline
        self.lifeline = lifeline
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let reader = ArisLineReaderBox()
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { handle.readabilityHandler = nil; return }
            let (objects, broken) = reader.feed(chunk)
            nonisolated(unsafe) let messages = objects
            Task { @MainActor [weak self] in
                self?.receive(messages)
                if broken { self?.process?.terminate() }
            }
        }
        process.terminationHandler = { [weak self] _ in
            output.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor [weak self] in self?.ended() }
        }
        do {
            try process.run()
            self.process = process
        } catch {
            Log.music.error("Now Playing stream did not start: \(error.localizedDescription, privacy: .public)")
            closeLifeline()
            output.fileHandleForReading.readabilityHandler = nil
            onFailure?()
        }
    }

    func stop() {
        stopping = true
        process?.terminate()
        process = nil
        closeLifeline()
    }

    private func closeLifeline() {
        try? lifeline?.fileHandleForWriting.close()
        lifeline = nil
    }

    /// The stream is live; there is nothing newer to ask for.
    func refresh() {}

    func send(_ command: ArisMusicCommand) {
        if transport?.send(command) == true { return }
        ArisProcessRun.launch(ArisAdapterFiles.perl, files.arguments(["send", String(ArisMediaRemoteTransport.id(command))]))
    }

    private func receive(_ messages: [[String: Any]]) {
        guard !stopping, !messages.isEmpty else { return }
        for message in messages { state.apply(message) }
        onUpdate?(state.playback())
    }

    private func ended() {
        process = nil
        closeLifeline()
        guard !stopping else { return }
        Log.music.error("Now Playing stream ended")
        onFailure?()
    }
}

/// The line reader, used only from the pipe's handler (which runs one call at a time).
private final class ArisLineReaderBox: @unchecked Sendable {
    private var lines = ArisJSONLines()

    func feed(_ chunk: Data) -> ([[String: Any]], Bool) {
        let objects = lines.feed(chunk)
        return (objects, lines.isBroken)
    }
}
