#!/usr/bin/env python3
"""Extract WeirdLoot loot-priority lines from the guild loot sheet.

The sheet tab is a pair of side-by-side blocks (25-man, 10-man), each six columns wide:
item name, spacer, then three priority columns (tier 1, 2, 3), then a spare. A ">" inside a cell is
a tier boundary just like a column boundary. Tokens within a tier are slash separated.

A token is one of three things, and the addon keeps two separate lists for them:
  * a raider name, or the LC / rest keywords  -> the NAMED list (defaultNamedItemsText)
  * a class or spec  ("Ret", "RestoSham", "Rogue")  -> the SPEC list (defaultLootPriorityText)
The addon resolves the named rule first and falls through to the spec rule, so an item may appear in
both lists. That ordering is the one thing it cannot bend: every name tier must come before every
spec tier, and a single tier cannot hold both. Sheet cells that ask for either are reported and the
offending half is dropped rather than silently reordered.

Spec shorthand is translated here, not in the addon. A word two classes share ("Frost", "Holy",
"Resto", "Prot") is refused with a warning: write it the way the sheet already writes HolyPal. A bare
class ("Rogue") is passed through as-is; the addon matches it against every spec of that class.

Usage:
    tools/sheet_named_items.py [--gid GID ...] [--sheet ID] [--csv FILE] [--txt PATH] [--lua [PATH]]

Reads the public CSV export (no auth). --csv reads a saved export instead of downloading. With no
output flag the lines go to stdout. --txt writes the named list to a gitignored paste file for the
addon's Import Named Items window. --lua rewrites BOTH blocks in Data/LootPrios.lua: the named block
wholesale, and a marked generated region inside the spec block, leaving hand-written spec rules for
raids the sheet does not cover untouched.
"""
import argparse, csv, io, os, re, sys, urllib.request

SHEET = "1p_MZ7c8IU1D2V2lp6Sovbif0KOMxL0px2pT8VhTwsqo"
GID = "1419766178"        # the "Ulduar_Untrimmed" tab
BLOCK = 6                  # columns per size block
TIER_COLS = (2, 3, 4)      # the three priority columns inside a block, in order
NAME = re.compile(r"^[A-Za-z]{2,12}$")   # a WoW character name; anything else is class text or a note
KEYWORDS = {"lc", "rest"}                # named-list tokens the addon parser understands besides names

# Sheet shorthand -> the addon's "class spec" form. A bare class maps to itself: the resolver treats a
# class with no spec as every spec of that class, which keeps the popup short.
SPEC_VOCAB = {
    "unholy": "death knight unholy", "blood": "death knight blood", "dkfrost": "death knight frost",
    # "Frost" is the death knight here, not the mage: the guild's BiS tabs field Arcane and Fire mages
    # only, and put Frost in the physical block beside Ret, Fury/Arms and Unholy. Write MageFrost if
    # that ever changes.
    "frost": "death knight frost",
    "ret": "paladin retribution", "retribution": "paladin retribution",
    "holypal": "paladin holy", "protpal": "paladin protection", "prot pala": "paladin protection",
    "disc": "priest discipline", "discipline": "priest discipline",
    "shadow": "priest shadow", "holypriest": "priest holy",
    "arcane": "mage arcane", "fire": "mage fire", "magefrost": "mage frost",
    "combat": "rogue combat", "assa": "rogue assassination", "assassination": "rogue assassination",
    "sub": "rogue subtlety", "subtlety": "rogue subtlety",
    "enhance": "shaman enhancement", "enhancement": "shaman enhancement",
    "ele": "shaman elemental", "elemental": "shaman elemental",
    "restosham": "shaman restoration", "restoshaman": "shaman restoration",
    "restodruid": "druid restoration", "restodru": "druid restoration",
    "feral": "druid feral", "cat": "druid feral", "bear": "druid feral",
    "balance": "druid balance", "boomkin": "druid balance", "moonkin": "druid balance", "boomie": "druid balance",
    "survival": "hunter survival", "surv": "hunter survival",
    "marksmanship": "hunter marksmanship", "marks": "hunter marksmanship", "mm": "hunter marksmanship",
    "bm": "hunter beast mastery", "beastmastery": "hunter beast mastery",
    "fury": "warrior fury", "arms": "warrior arms", "protwar": "warrior protection", "prot war": "warrior protection",
    "affliction": "warlock affliction", "aff": "warlock affliction",
    "demonology": "warlock demonology", "demo": "warlock demonology",
    "destruction": "warlock destruction", "destro": "warlock destruction",
    # bare classes: matched against every spec of the class
    "rogue": "rogue", "mage": "mage", "paladin": "paladin", "pal": "paladin", "priest": "priest",
    "druid": "druid", "shaman": "shaman", "sham": "shaman", "hunter": "hunter", "warrior": "warrior",
    "warlock": "warlock", "lock": "warlock", "dk": "death knight", "deathknight": "death knight",
    "death knight": "death knight",
}

# Drops whose 10 and 25 versions share one name. Rules key on the item name, so one of the two would
# always be discarded. Only the size listed here is emitted keyed by ITEM ID, which the addon prefers
# over a name; the other keeps the plain name, and the two no longer collide. The sheet is untouched:
# the ids live here, not in a cell.
SIZE_ITEM_IDS = {
    "reply-code alpha": {"10": 46052},   # Algalon's chest, Gift of the Observer; 25-man stays by name
}

# Words the guild's own BiS tabs show under two different classes, so the sheet has to say which, the
# way it already writes HolyPal. Frost is deliberately absent: only one class here has it.
AMBIGUOUS = {
    "holy": "HolyPal or HolyPriest",
    "resto": "RestoSham or RestoDruid",
    "restoration": "RestoSham or RestoDruid",
    "prot": "ProtPal or ProtWar",
    "protection": "ProtPal or ProtWar",
}

def classify(token, warn, item):
    """-> ("name"|"spec", value) or (None, None) when the token cannot be used."""
    key = token.lower().replace("-", "").replace("_", "")
    if key in KEYWORDS:
        return "name", token
    if key in AMBIGUOUS:
        warn(f"{item}: {token!r} is used by two classes, write {AMBIGUOUS[key]}")
        return None, None
    spaced = token.lower().strip()
    if key in SPEC_VOCAB:
        return "spec", SPEC_VOCAB[key]
    if spaced in SPEC_VOCAB:
        return "spec", SPEC_VOCAB[spaced]
    if NAME.match(token):
        return "name", token
    warn(f"{item}: skipped unrecognised token {token!r}")
    return None, None

def fetch(sheet, gid):
    url = f"https://docs.google.com/spreadsheets/d/{sheet}/export?format=csv&gid={gid}"
    return urllib.request.urlopen(url).read().decode("utf-8")

def block_lines(rows, base, warn, size=None):
    """-> [(item, line)] for one size block. Names and spec tokens share one line: the addon parses
    the list twice and routes each token, so one paste provides both."""
    out = []
    for r in rows:
        cells = [(r[base + i] if base + i < len(r) else "").strip() for i in range(BLOCK)]
        item = cells[0]
        if not item:
            continue
        tiers = []
        seen_spec = False
        for c in TIER_COLS:
            raw = cells[c]
            if not raw:
                continue
            for part in raw.split(">"):
                names, specs = [], []
                for tok in (t.strip() for t in part.split("/")):
                    if not tok:
                        continue
                    kind, value = classify(tok, warn, item)
                    if kind == "name":
                        names.append(value)
                    elif kind == "spec":
                        specs.append(value)
                if names and specs:
                    warn(f"{item}: a tier holding both names and specs ranks the names first, not equally")
                if names and seen_spec:
                    warn(f"{item}: the addon tries every name before any spec, so {names!r} "
                         f"cannot rank below a spec tier")
                if specs:
                    seen_spec = True
                entries = names + specs
                if entries:
                    tiers.append(" / ".join(entries))
        if tiers:
            ids = SIZE_ITEM_IDS.get(item.lower())
            key = ids.get(size) if (ids and size) else None
            head = str(key) if key else item
            out.append((head, f"{head}, {' > '.join(tiers)}"))
    return out

# The rightmost block ("BIG ITEMS") is derived from the raid blocks and is a truncated copy of them,
# so reading it would double every item and lose the tiers its narrower columns drop.
def raid_block_bases(rows, warn):
    """-> [(base, size)] where size is the raid size read from the block header, e.g. "25"."""
    header = rows[0] if rows else []
    bases = []
    for base in range(0, max((len(r) for r in rows), default=0), BLOCK):
        title = (header[base] if base < len(header) else "").strip()
        if not title:
            continue
        if "BIG ITEMS" in title.upper():
            continue
        m = re.search(r"\((\d+)\)", title)
        bases.append((base, m.group(1) if m else None))
    if not bases:
        warn("no raid blocks found: check the tab header row")
    return bases

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
LUA_PATH = os.path.join(ROOT, "Data", "LootPrios.lua")
TXT_PATH = os.path.join(ROOT, "named_items.txt")   # gitignored paste file
NAMED_BLOCK = re.compile(r'addon\.defaultNamedItemsText = table\.concat\(\{\n.*?\n\}, "\\n"\)', re.S)

def write_lua(path, lines, source):
    src = open(path, encoding="utf-8").read()
    if not NAMED_BLOCK.search(src):
        sys.exit(f"{path}: defaultNamedItemsText block not found")
    body = "\n".join('    "%s",' % l.replace("\\", "\\\\").replace('"', '\\"') for l in lines)
    block = ('-- Generated by tools/sheet_named_items.py from the loot sheet (%s); rerun it rather\n'
             '-- than editing these lines. Lines may carry class/spec tokens as well as player names:\n'
             '-- the addon routes each token to the right rule set at parse time.\n'
             'addon.defaultNamedItemsText = table.concat({\n%s\n}, "\\n")') % (source, body)
    src = re.sub(r'-- Generated by tools/sheet_named_items\.py[^\n]*\n(-- [^\n]*\n)*', '', src)
    open(path, "w", encoding="utf-8").write(NAMED_BLOCK.sub(lambda _: block, src, count=1))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet", default=SHEET)
    ap.add_argument("--gid", action="append", help="tab gid; repeatable, default the Ulduar_Untrimmed tab")
    ap.add_argument("--csv", help="read this saved CSV export instead of downloading")
    ap.add_argument("--txt", nargs="?", const=TXT_PATH, help="write the named-list paste file (default named_items.txt in the addon root)")
    ap.add_argument("--lua", nargs="?", const=LUA_PATH, help="rewrite both shipped default blocks (default Data/LootPrios.lua)")
    args = ap.parse_args()

    warnings = []
    def warn(msg):
        warnings.append(msg)
        print("warning: " + msg, file=sys.stderr)

    gids = args.gid or [GID]
    all_lines, seen = [], {}
    for gid in gids:
        text = open(args.csv, encoding="utf-8").read() if args.csv else fetch(args.sheet, gid)
        rows = list(csv.reader(io.StringIO(text)))
        for base, size in raid_block_bases(rows, warn):
            for item, line in block_lines(rows, base, warn, size):
                if item in seen and seen[item] != line:
                    warn(f"conflicting repeat kept first: {seen[item]!r} vs {line!r}")
                elif item not in seen:
                    seen[item] = line
                    all_lines.append(line)

    if args.txt:
        with open(args.txt, "w", encoding="utf-8") as f:
            f.write("\n".join(all_lines) + "\n")
        print(f"{len(all_lines)} lines -> {args.txt}")
    if args.lua:
        write_lua(args.lua, all_lines, "gid " + ", ".join(gids))
        print(f"{len(all_lines)} lines -> {args.lua}")
    if not args.txt and not args.lua:
        for line in all_lines:
            print(line)

main()
