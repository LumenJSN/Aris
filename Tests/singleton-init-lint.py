# Guard: a singleton's init (a type with `static let shared`) must not post notifications or touch another
# singleton (`X.shared`) synchronously — doing so can re-enter a singleton still being created (dispatch_once
# recursion, the launch crash fixed in b827faf2). Work that needs them goes in a Task or a later call.
# Also flags assigning, inside such an init, a stored property that has a didSet (observers can run there).
# Scans the clean-room folders; prints offending lines with file:line and exits 1 if any.
import re, sys, pathlib
root = pathlib.Path(sys.argv[1])
folders = ['Aris/private/Music', 'Aris/private/Notch', 'Aris/private/Shelf', 'Aris/private/Platform', 'Aris/private/Calendar', 'Aris/private/App']
bad = []

def init_bodies(text):
    for m in re.finditer(r'\n(\s*)(?:private |override |convenience |nonisolated )*init\([^)]*\)[^{]*\{', text):
        indent, i, depth = m.group(1), m.end(), 1
        while depth and i < len(text):
            depth += {'{': 1, '}': -1}.get(text[i], 0); i += 1
        yield m.end(), text[m.end():i - 1]

for folder in folders:
    for path in sorted((root / folder).glob('*.swift')):
        text = path.read_text()
        if 'static let shared' not in text: continue
        observed = set(re.findall(r'var (\w+)[^\n{]*\{\s*\n?\s*didSet', text))
        for start, body in init_bodies(text):
            depth = 0
            for offset, line in enumerate(body.split('\n')):
                code = line.split('//')[0]
                inside_closure = depth > 0
                depth += code.count('{') - code.count('}')
                if inside_closure or re.search(r'\bTask\b|\.sink|\{\s*\[weak self\]', code):
                    continue
                number = text.count('\n', 0, start) + offset + 1
                if re.search(r'\.post\(', code):
                    bad.append(f'{path.relative_to(root)}:{number}: posts a notification in a singleton init')
                for other in re.findall(r'\b([A-Z]\w+)\.shared\b', code):
                    bad.append(f'{path.relative_to(root)}:{number}: touches {other}.shared in a singleton init')
                for name in observed:
                    if re.search(rf'^\s*(self\.)?{name}\s*=(?!=)', code):
                        bad.append(f'{path.relative_to(root)}:{number}: assigns observed property {name} in a singleton init')

print('\n'.join(bad) if bad else 'singleton inits: clean')
sys.exit(1 if bad else 0)
