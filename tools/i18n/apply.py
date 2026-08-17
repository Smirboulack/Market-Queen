"""Folds a batch of translations into a language catalogue, safely.

    python tools/i18n/catalogue.py es > es-todo.json   # what is missing
    ...translate it into {"english": "spanish"} ...
    python tools/i18n/apply.py es es-done.json

Two checks, and both exist because the failure they catch is silent:

  * a key that is not a live source string is refused. A catalogue entry whose
    English no longer appears in the app is dead weight, and one with a typo in
    it is a string that stays English forever with nothing to show for it;

  * a translation that loses or invents a `%1` is refused. The placeholders are
    filled in at run time by position, so a missing one is a sentence with a
    hole in it and an extra one is a literal "%2" on somebody's screen.

Existing entries are kept unless the batch overwrites them, and the file is
written back sorted, so a review shows what changed rather than where it landed.
"""

import io
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import catalogue as cat  # noqa: E402

PLACEHOLDER = re.compile(r"%\d")


def main(argv):
    if len(argv) != 2:
        sys.stdout.write(__doc__)
        return 2

    language, path = argv
    if language not in cat.languages():
        sys.stdout.write("no catalogue for %r\n" % language)
        return 2

    batch = json.load(io.open(path, encoding="utf-8"))
    live = set(cat.sources())
    problems = []

    for key, value in batch.items():
        if key not in live:
            problems.append("no source string: %s" % key)
            continue
        if not value.strip():
            problems.append("empty translation: %s" % key)
            continue
        if set(PLACEHOLDER.findall(key)) != set(PLACEHOLDER.findall(value)):
            problems.append("placeholders differ:\n    %s\n    %s" % (key, value))

    if problems:
        for problem in problems:
            sys.stdout.write("  %s\n" % problem)
        sys.stdout.write("%d problem(s); nothing written\n" % len(problems))
        return 1

    entries = cat.catalogue(language)
    before = len(entries)
    entries.update(batch)
    cat.write(language, entries)

    missing = len([k for k in sorted(live) if k not in entries])
    sys.stdout.write(
        "%s: %d in, %d entries (was %d), %d still missing\n"
        % (language, len(batch), len(entries), before, missing)
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
