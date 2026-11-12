//
//  ArisSpawn.swift
//  aris-agent
//
//  One child process started with posix_spawn, its argv handed over as the exact UTF-8 bytes of each word. Foundation's
//  Process passes arguments through fileSystemRepresentation, which decomposes Hangul into jamo (NFD): typed Korean
//  reached the app as a different string (the benchmark's ime_korean and ime_textedit). Its stdin and stderr are
//  /dev/null, nothing else of the parent's leaks in (POSIX_SPAWN_CLOEXEC_DEFAULT), and it is ended at its time limit.
//

import Darwin
import Foundation

enum ArisSpawn {
    /// Runs `executable` with `arguments` in `directory`; what it printed on stdout (at most `maxOutput` bytes).
    /// Status 124 when it ran out of time, 127 when it couldn't start.
    static func run(_ executable: String, _ arguments: [String], environment: [String: String], directory: String,
                    timeout: TimeInterval, maxOutput: Int) -> (status: Int32, output: Data) {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { return (127, Data()) }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, fds[1], 1)
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addchdir_np(&actions, directory)
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))
        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }
        var pid: pid_t = 0
        let started = ArisChildren.spawn(&pid, executable, &actions, &attributes, argv, envp)
        close(fds[1])
        guard started == 0 else { close(fds[0]); return (127, Data()) }
        nonisolated(unsafe) var printed = Data()
        let reading = DispatchSemaphore(value: 0)
        let readEnd = fds[0]
        DispatchQueue.global().async {
            var buffer = [UInt8](repeating: 0, count: 65_536)
            while true {
                let count = read(readEnd, &buffer, buffer.count)
                if count <= 0 { break }
                if printed.count < maxOutput { printed.append(contentsOf: buffer[0..<count]) }
            }
            close(readEnd)
            reading.signal()
        }
        let deadline = Date().addingTimeInterval(timeout)
        var status: Int32 = 0
        var ended = false
        while Date() < deadline {
            if waitpid(pid, &status, WNOHANG) == pid { ended = true; break }
            Thread.sleep(forTimeInterval: 0.02)
        }
        if !ended {
            kill(pid, SIGTERM)
            let grace = Date().addingTimeInterval(1)
            while Date() < grace, waitpid(pid, &status, WNOHANG) != pid { Thread.sleep(forTimeInterval: 0.02) }
            kill(pid, SIGKILL)
            _ = waitpid(pid, &status, 0)
            _ = reading.wait(timeout: .now() + 2)
            return (124, Data())
        }
        _ = reading.wait(timeout: .now() + 5)
        let exited = status & 0x7f == 0
        return (exited ? (status >> 8) & 0xff : 128 + (status & 0x7f), printed.prefix(maxOutput))
    }
}
