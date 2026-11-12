// Probes the skills sandboxes for real (sandbox-exec can't nest, so this runs before the sandboxed tests): a skill's
// script can't rename a folder above ~/.config/aris or the skills folder to reach them another way, can't write into
// the skills folder or runtime, can still write its scratch folder; the SkillSpector profile reaches no LaunchServices
// (nothing can be opened). Everything happens in a temp home; nothing opens on screen. Exit 0 = every probe held.
import Foundation

var failures = 0
func expect(_ ok: Bool, _ name: String) {
    print((ok ? "ok   " : "FAIL ") + name)
    if !ok { failures += 1 }
}

let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aris-probe-\(UUID().uuidString.prefix(6))")
let home = base.appendingPathComponent("home")
let aris = home.appendingPathComponent("Library/Application Support/Aris")
let skills = aris.appendingPathComponent("Skills"), runtime = aris.appendingPathComponent("skills-runtime")
let config = home.appendingPathComponent(".config/aris"), scratch = base.appendingPathComponent("scratch")
for folder in [skills.appendingPathComponent("s"), runtime, config, scratch] { try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
try? "secret".write(to: config.appendingPathComponent("key"), atomically: true, encoding: .utf8)
defer { try? FileManager.default.removeItem(at: base) }

func script(_ command: String) -> (status: Int32, output: String) {
    let sandbox = ArisSkillSandbox.arguments(profile: ArisSkillSandbox.scriptProfile, parameters: ArisSkillSandbox.scriptParameters(
        skills: skills.path, runtime: runtime.path, config: config.path, home: home.path))
    let result = ArisSkillProcess.run(ArisSkillSandbox.tool, sandbox + ["/bin/sh", "-c", command], environment: ["PATH": "/usr/bin:/bin", "H": home.path],
                                      directory: scratch.path, timeout: 20)
    return (result.status, result.stdout + result.stderr)
}

let readKey = script(#"cat "$H/.config/aris/key""#)
expect(readKey.status != 0 && !readKey.output.contains("secret"), "script: ~/.config/aris can't be read")
let renameConfig = script(#"mv "$H/.config" "$H/cfg" && cat "$H/cfg/aris/key""#)
expect(renameConfig.status != 0 && !renameConfig.output.contains("secret") && FileManager.default.fileExists(atPath: config.path),
       "script: renaming ~/.config to read it under another name is refused")
let renameAris = script(#"mv "$H/Library/Application Support/Aris" "$H/A2" && echo x > "$H/A2/Skills/s/x""#)
expect(renameAris.status != 0 && FileManager.default.fileExists(atPath: skills.path), "script: renaming …/Aris to write the skills folder is refused")
let renameLibrary = script(#"mv "$H/Library" "$H/L2""#)
let renameSupport = script(#"mv "$H/Library/Application Support" "$H/AS2""#)
expect(renameLibrary.status != 0 && renameSupport.status != 0, "script: ~/Library and Application Support can't be renamed either")
let writeSkill = script(#"echo x > "$H/Library/Application Support/Aris/Skills/s/x""#)
let writeRuntime = script(#"echo x > "$H/Library/Application Support/Aris/skills-runtime/x""#)
expect(writeSkill.status != 0 && writeRuntime.status != 0, "script: the skills folder and the runtime are read-only")
expect(script("echo ok > out.txt && cat out.txt").output.contains("ok"), "script: its scratch folder is writable")

let scan = ArisSkillSandbox.arguments(profile: ArisSkillSandbox.scanProfile, parameters: ArisSkillSandbox.scanParameters(
    runtime: runtime.path, target: skills.appendingPathComponent("s").path, work: scratch.path))
let launchServices = ArisSkillProcess.run(ArisSkillSandbox.tool, scan + ["/usr/bin/lsappinfo", "front"], environment: ["PATH": "/usr/bin:/bin"],
                                          directory: scratch.path, timeout: 20)
let outside = ArisSkillProcess.run("/usr/bin/lsappinfo", ["front"], environment: ["PATH": "/usr/bin:/bin"], directory: scratch.path, timeout: 20)
// Outside it names the app in front (an ASN); inside it reaches nothing ("[ NULL ]" or a failure).
expect(outside.stdout.contains("ASN:") && !launchServices.stdout.contains("ASN:"),
       "scan: LaunchServices is out of reach (nothing can be opened)")
let network = ArisSkillProcess.run(ArisSkillSandbox.tool, scan + ["/usr/bin/nc", "-z", "-G", "2", "1.1.1.1", "443"], environment: ["PATH": "/usr/bin:/bin"],
                                   directory: scratch.path, timeout: 20)
expect(!network.ok, "scan: no network")
print(failures == 0 ? "PROBE OK" : "PROBE FAILED")
exit(failures == 0 ? 0 : 1)
