# Guard (tenth VM run, item 1: a saved API key was found in the app's HTTP cache on disk): every request Aris makes
# goes through ArisNoStore (Shared/ArisNoStore.swift), a session with no URL cache, no cookie storage and no
# credential storage. So nowhere else may a source name the shared session, a default or bare ephemeral configuration,
# the shared URL cache, or give a configuration a cache, a cookie store or a credential store.
# The one exception is the artwork fetch, which keeps public pictures in a cache folder of its own.
# Prints offending lines with file:line and exits 1 if any.
import re, sys, pathlib
root = pathlib.Path(sys.argv[1])
folders = ['Aris', 'ArisAgent', 'ArisTools', 'ArisXPCHelper', 'Shared']
own = 'Shared/ArisNoStore.swift'
artwork = 'Aris/private/Music/ArisArtworkFetch.swift'
everywhere = [
    (r'URLSession\.shared', 'the shared session'),
    (r'URLSessionConfiguration\.(default|ephemeral|background)', 'a configuration not made by ArisNoStore'),
    (r'URLSession\(configuration:\s*\.', 'a configuration not made by ArisNoStore'),
    (r'URLSessionConfiguration\s*=\s*\.', 'a configuration not made by ArisNoStore'),
    (r'URLSessionConfiguration\(\)', 'a configuration not made by ArisNoStore'),
    (r'NSURLConnection|NSURLSession\b', 'a network path outside ArisNoStore'),
    (r'HTTPCookieStorage\.shared|URLCredentialStorage\.shared', 'a shared cookie or credential store'),
    (r'\.httpCookieStorage\s*=\s*(?!nil|\s)|\.urlCredentialStorage\s*=\s*(?!nil|\s)', 'a cookie or credential store on a configuration'),
]
not_artwork = [
    (r'URLCache\b', 'a URL cache'),
    (r'\.urlCache\s*=\s*(?!nil|\s)', 'a URL cache on a configuration'),
    (r'\.requestCachePolicy\s*=\s*(?!\.reloadIgnoringLocal|\s)', 'a caching request policy'),
]
bad = []
for folder in folders:
    for path in sorted((root / folder).rglob('*.swift')):
        name = str(path.relative_to(root))
        if name == own: continue
        for number, line in enumerate(path.read_text(errors='replace').split('\n'), 1):
            code = line.split('//')[0]
            for pattern, why in everywhere + ([] if name == artwork else not_artwork):
                if re.search(pattern, code): bad.append(f'{name}:{number}: {why}: {line.strip()[:120]}')
text = (root / own).read_text() if (root / own).exists() else ''
for needed in ['URLSessionConfiguration.ephemeral', 'configuration.urlCache = nil', 'configuration.requestCachePolicy = .reloadIgnoringLocalCacheData',
               'configuration.httpCookieStorage = nil', 'configuration.urlCredentialStorage = nil']:
    if needed not in text: bad.append(f'{own}: the no-store configuration lost: {needed}')
if 'ArisNoStore.configuration()' not in (root / artwork).read_text(): bad.append(f'{artwork}: must start from ArisNoStore.configuration()')
if bad:
    print('\n'.join(bad)); sys.exit(1)
