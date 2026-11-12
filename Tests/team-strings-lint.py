# The teammates redesign's strings: every String(localized: "team.…", defaultValue: …) in the app has a Korean and an
# English value in Aris/Localizable.xcstrings, the English one equal to the Swift default, with the same format
# arguments in both languages; and no team.* key is left in the catalog unused.
import glob, json, re, sys
root = sys.argv[1]
src = "".join(open(p).read() for p in glob.glob(f"{root}/Aris/**/*.swift", recursive=True))
cat = json.load(open(f"{root}/Aris/Localizable.xcstrings"))["strings"]
pairs = re.findall(r'String\(localized: "(team\.[^"]+)", defaultValue: "((?:[^"\\]|\\.)*)"', src)
problems = []
def args(s): return sorted(re.findall(r'%(?:\d\$)?(?:lld|@)', s))
for key, default in pairs:
    en_default = re.sub(r'\\\((?:count|index)\)', '%lld', default)
    en_default = re.sub(r'\\\([a-zA-Z]+\)', '%@', en_default).replace('\\"', '"').replace('\\n', '\n')
    loc = cat.get(key, {}).get("localizations", {})
    en = loc.get("en", {}).get("stringUnit", {}).get("value")
    ko = loc.get("ko", {}).get("stringUnit", {}).get("value")
    if en is None or ko is None: problems.append(f"{key}: missing en or ko"); continue
    if en != en_default: problems.append(f"{key}: Swift default {en_default!r} != catalog en {en!r}")
    if args(en) != args(ko): problems.append(f"{key}: format arguments differ between en and ko")
used = {k for k, _ in pairs}
for key in cat:
    if key.startswith("team.") and key not in used: problems.append(f"{key}: in the catalog, not used")
print("\n".join(problems) or f"team strings: {len(set(used))} keys, ko + en")
sys.exit(1 if problems else 0)
