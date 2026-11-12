# Guard (QA BUG-37): AppleScript never compiles or runs inside Aris or aris-agent. NSAppleScript/OSAKit compile in
# process (OSACompile -> SystemPolicy's script scanner over XPC), and that blocked forever holding the runtime's
# locks: the main thread froze. Raw Apple Events (NSAppleEventDescriptor sends: ArisAppleEvents) load no OSA and
# are allowed; scripts never compile in process.
# Scans the app's, the helper's and the agent's Swift code (comments aside); prints file:line and exits 1 on a hit.
import re, sys, pathlib
root = pathlib.Path(sys.argv[1])
folders = ['Aris', 'Shared', 'ArisXPCHelper', 'ArisAgent']
banned = re.compile(r'\bNSAppleScript\b|\bOSAScript\b|\bimport\s+OSAKit\b|\bOSACompile\b|\bOSAExecute\b|\bOSALanguage\b')
bad = []
for folder in folders:
    for path in sorted((root / folder).rglob('*.swift')):
        for number, line in enumerate(path.read_text().split('\n'), 1):
            code = line.split('//')[0]
            if banned.search(code):
                bad.append(f'{path.relative_to(root)}:{number}: in-process AppleScript (use ArisAppleScript, out of process)')
print('\n'.join(bad) if bad else 'applescript: out of process only')
sys.exit(1 if bad else 0)
