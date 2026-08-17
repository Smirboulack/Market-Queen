"""Every string the app shows, and which catalogues are missing it.

The app's translations are flat `"english source": "translation"` JSON, one file
per language under assets/i18n. Nothing generates them and nothing checked them,
so a string added to the Dart source simply fell back to English in all ten
other languages -- silently, and only visible to somebody running the app in
that language.

This is the check that was missing. Run it from the repo root:

    python tools/i18n/catalogue.py            # coverage per language
    python tools/i18n/catalogue.py fr         # what French is missing
    python tools/i18n/catalogue.py --stale    # keys no source string uses

It reads `tr('...')` calls out of lib/, including the adjacent-literal form the
codebase uses to wrap long sentences:

    tr('a very long sentence that '
       'runs onto a second line')
"""

import io
import json
import os
import re
import sys

APP = "market_queen_flutter_app"
SOURCE = os.path.join(APP, "lib")
CATALOGUES = os.path.join(APP, "assets", "i18n")

_SINGLE = r"'(?:[^'\\]|\\.)*'"
_DOUBLE = r'"(?:[^"\\]|\\.)*"'
_LITERAL = "(?:" + _SINGLE + "|" + _DOUBLE + ")"

_CALL = re.compile(r"tr\(\s*(" + _LITERAL + r"(?:\s*" + _LITERAL + r")*)\s*[,)]", re.S)
_PIECE = re.compile(_LITERAL, re.S)

_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "'": "'", '"': '"', "\\": "\\", "$": "$"}

# Strings that reach tr() through a variable rather than as a literal, so the
# scan below cannot see them. There are exactly two such call sites -- the
# Models page translates `panel.title` and `panel.subtitle` -- and the values
# live untranslated in Registry.panels.
#
# They are listed by hand because the alternative is worse in both directions:
# left out, --stale offers to delete four live translations; guessed at by
# widening the scan, every ordinary Dart string in the registry looks like one.
# If a panel is renamed, rename it here too.
DYNAMIC = [
    "API keys",
    "Paste a key for each account you want to buy from. Everything the app "
    "can do is switched on by these.",
    "Information",
    "What each account is for, what it charges, and which of its models the "
    "app uses.",
]


def _unquote(token):
    """A Dart string literal, minus its quotes and escapes."""
    body, out, i = token[1:-1], [], 0
    while i < len(body):
        if body[i] == "\\" and i + 1 < len(body):
            out.append(_ESCAPES.get(body[i + 1], body[i + 1]))
            i += 2
        else:
            out.append(body[i])
            i += 1
    return "".join(out)


def sources(root=SOURCE):
    """Every string handed to tr(), in the order the files were walked."""
    found = list(DYNAMIC)
    for folder, _, files in os.walk(root):
        for name in sorted(files):
            if not name.endswith(".dart"):
                continue
            path = os.path.join(folder, name)
            text = io.open(path, encoding="utf-8").read()
            for call in _CALL.finditer(text):
                pieces = _PIECE.findall(call.group(1))
                found.append("".join(_unquote(p) for p in pieces))
    return found


def languages():
    return sorted(
        name[:-5]
        for name in os.listdir(CATALOGUES)
        if name.endswith(".json")
    )


def catalogue(language):
    path = os.path.join(CATALOGUES, language + ".json")
    return json.load(io.open(path, encoding="utf-8"))


def write(language, entries):
    """Writes a catalogue back, sorted, so a diff shows what changed rather
    than where it was inserted."""
    path = os.path.join(CATALOGUES, language + ".json")
    ordered = {key: entries[key] for key in sorted(entries)}
    io.open(path, "w", encoding="utf-8", newline="\n").write(
        json.dumps(ordered, ensure_ascii=False, indent=2) + "\n"
    )


def main(argv):
    wanted = sorted(set(sources()))

    if "--stale" in argv:
        live = set(wanted)
        for language in languages():
            entries = catalogue(language)
            extra = sorted(key for key in entries if key not in live)
            print("%s: %d translated string(s) nothing displays" % (language, len(extra)))
            for key in extra:
                print("   %s" % key.replace("\n", "\\n"))
        return 0

    asked = [a for a in argv if not a.startswith("-")]

    if asked:
        for language in asked:
            entries = catalogue(language)
            missing = [key for key in wanted if key not in entries]
            print("# %s: %d missing of %d" % (language, len(missing), len(wanted)))
            print(json.dumps(missing, ensure_ascii=False, indent=1))
        return 0

    print("%d strings in the source\n" % len(wanted))
    worst = 0
    for language in languages():
        entries = catalogue(language)
        missing = [key for key in wanted if key not in entries]
        worst = max(worst, len(missing))
        print(
            "  %-3s %5.1f%%   %d missing"
            % (language, 100 * (1 - len(missing) / len(wanted)), len(missing))
        )
    return 1 if worst else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
