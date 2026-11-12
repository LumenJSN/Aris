//
//  ArisExactProcess.swift
//  aris-agent
//
//  A child process whose command line and environment reach it byte for byte. Foundation's Process hands every
//  argument and variable over through fileSystemRepresentation, which takes Hangul apart into jamo (NFD): "엄마" arrived
//  at aris-tools as six code points, so a message pass minted from the user's own words was never found, a search for
//  "회의" matched nothing, and a brain read its Korean instructions as loose jamo (audit nfd-argv-1).
//
//  It is a Process in every other way (the same pipes, handler, status and terminate), so a call site changes one
//  word. What Foundation gives its children is kept: only stdin, stdout and stderr are inherited, every signal is back
//  at its default, and the child leads its own process group. A pipe to its stdin never raises SIGPIPE here.
//

import Darwin
import Foundation

final class ArisExactProcess: Process, @unchecked Sendable {
    private let state = NSCondition()
    private var program: URL?
    private var words: [String]?
    private var variables: [String: String]?
    private var folder: URL?
    private var input: Any?
    private var output: Any?
    private var errors: Any?
    private var handler: (@Sendable (Process) -> Void)?
    private var pid: pid_t = 0
    private var started = false
    private var ended = false
    private var status: Int32 = 0
    private var reason: Process.TerminationReason = .exit

    override init() { super.init() }

    override var executableURL: URL? {
        get { state.withLock { program } }
        set { state.withLock { program = newValue } }
    }

    override var arguments: [String]? {
        get { state.withLock { words } }
        set { state.withLock { words = newValue } }
    }

    override var environment: [String: String]? {
        get { state.withLock { variables } }
        set { state.withLock { variables = newValue } }
    }

    override var currentDirectoryURL: URL? {
        get { state.withLock { folder } }
        set { state.withLock { folder = newValue } }
    }

    override var standardInput: Any? {
        get { state.withLock { input } }
        set { state.withLock { input = newValue } }
    }

    override var standardOutput: Any? {
        get { state.withLock { output } }
        set { state.withLock { output = newValue } }
    }

    override var standardError: Any? {
        get { state.withLock { errors } }
        set { state.withLock { errors = newValue } }
    }

    override var terminationHandler: (@Sendable (Process) -> Void)? {
        get { state.withLock { handler } }
        set { state.withLock { handler = newValue } }
    }

    override var processIdentifier: Int32 { state.withLock { pid } }
    override var isRunning: Bool { state.withLock { started && !ended } }
    override var terminationStatus: Int32 { state.withLock { status } }
    override var terminationReason: Process.TerminationReason { state.withLock { reason } }

    override func run() throws {
        let (program, words, variables, folder, input, output, errors) = state.withLock {
            (self.program, self.words ?? [], self.variables ?? ProcessInfo.processInfo.environment, self.folder, self.input, self.output, self.errors)
        }
        guard let program, !state.withLock({ started }) else { throw CocoaError(.fileNoSuchFile) }
        guard FileManager.default.isExecutableFile(atPath: program.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: program.path])
        }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        // The child's ends, and the parent's copies of them that are closed once it runs (as Process does): a reader
        // of the child's output then sees its end, and a write to a child that has gone fails instead of waiting.
        var handed: [FileHandle] = []
        for (number, stream, childReads) in [(Int32(0), input, true), (1, output, false), (2, errors, false)] {
            if let pipe = stream as? Pipe {
                let end = childReads ? pipe.fileHandleForReading : pipe.fileHandleForWriting
                posix_spawn_file_actions_adddup2(&actions, end.fileDescriptor, number)
                handed.append(end)
                // Writing to a child that has already gone is an error the writer catches (EPIPE), never the signal
                // that would end the whole agent (audit sigpipe-1).
                if childReads { _ = fcntl(pipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) }
            } else if let handle = stream as? FileHandle {
                if handle.fileDescriptor >= 0 {
                    posix_spawn_file_actions_adddup2(&actions, handle.fileDescriptor, number)
                } else {
                    // FileHandle.nullDevice has no descriptor to hand over (-1): the child gets /dev/null opened there, as
                    // Process gives it. Left to the failed dup2 the stream was closed, and the first file or socket the
                    // child opened became its stdin, stdout or stderr (security review M1).
                    posix_spawn_file_actions_addopen(&actions, number, "/dev/null", number == 0 ? O_RDONLY : O_WRONLY, 0)
                }
            } else {
                posix_spawn_file_actions_addinherit_np(&actions, number)
            }
        }
        if let folder { posix_spawn_file_actions_addchdir_np(&actions, folder.path) }
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        var everySignal = sigset_t(), noSignal = sigset_t()
        sigfillset(&everySignal)
        sigemptyset(&noSignal)
        posix_spawnattr_setsigdefault(&attributes, &everySignal)
        posix_spawnattr_setsigmask(&attributes, &noSignal)
        posix_spawnattr_setpgroup(&attributes, 0)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETPGROUP))
        // strdup copies each word's own UTF-8: what the user typed or said (composed, NFC) arrives exactly so.
        let argv = ([program.path] + words).map { strdup($0) } + [nil]
        let envp = variables.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }
        var child: pid_t = 0
        let failed = posix_spawn(&child, program.path, &actions, &attributes, argv, envp)
        guard failed == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(failed)) }
        state.withLock {
            pid = child
            started = true
        }
        handed.forEach { try? $0.close() }
        // One thread waits for the end: a child that is already gone is still collected, so no end is ever missed.
        let waiter = Thread { [self] in
            var raw: Int32 = 0
            while waitpid(child, &raw, 0) == -1, errno == EINTR {}
            let signalled = raw & 0x7f != 0
            let after = state.withLock { () -> (@Sendable (Process) -> Void)? in
                status = signalled ? raw & 0x7f : (raw >> 8) & 0xff
                reason = signalled ? .uncaughtSignal : .exit
                ended = true
                state.broadcast()
                return handler
            }
            after?(self)
        }
        waiter.start()
    }

    override func terminate() { signalChild(SIGTERM) }
    override func interrupt() { signalChild(SIGINT) }

    private func signalChild(_ signal: Int32) {
        // Under the lock, so the signal never reaches a number the system has already given to someone else.
        state.withLock { if started, !ended { kill(pid, signal) } }
    }

    override func waitUntilExit() {
        state.withLock { while started, !ended { state.wait() } }
    }
}
