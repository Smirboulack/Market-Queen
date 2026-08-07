#!/usr/bin/env python3
"""Fill the .ts catalogues from the compact per-language JSON dictionaries.

Qt's .ts format is verbose XML; keeping the actual translations in
`i18n/<lang>.json` (a flat "english source" -> "translation" map) makes them
readable in a diff and easy to contribute to.

Workflow:
    cmake --build build --target update_translations   # lupdate: refresh sources
    python tools/fill_translations.py                  # inject the JSON
    cmake --build build                                # lrelease: compile .qm

Run with --list to dump the source strings that still need a translation.
"""

import argparse
import json
import pathlib
import sys
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
I18N = ROOT / "i18n"


def ts_path(lang):
    return I18N / f"superinfinity_{lang}.ts"


def languages():
    return sorted(p.stem.split("_", 1)[1] for p in I18N.glob("superinfinity_*.ts"))


def sources(lang):
    """Every source string in a catalogue, in file order, deduplicated."""
    tree = ET.parse(ts_path(lang))
    seen, out = set(), []
    for message in tree.iter("message"):
        text = message.findtext("source")
        if text and text not in seen:
            seen.add(text)
            out.append(text)
    return out


def fill(lang):
    dictionary_path = I18N / f"{lang}.json"
    if not dictionary_path.exists():
        return None

    dictionary = json.loads(dictionary_path.read_text(encoding="utf-8"))

    path = ts_path(lang)
    tree = ET.parse(path)
    translated = missing = 0

    for message in tree.iter("message"):
        source = message.findtext("source")
        target = dictionary.get(source)
        translation = message.find("translation")
        if translation is None:
            translation = ET.SubElement(message, "translation")

        if target:
            translation.text = target
            translation.attrib.pop("type", None)
            translated += 1
        else:
            # Qt falls back to the source string for unfinished entries.
            translation.set("type", "unfinished")
            missing += 1

    tree.write(path, encoding="utf-8", xml_declaration=True)

    # ElementTree drops the DOCTYPE; Qt tools accept the file without it, but
    # keeping it makes Linguist and diffs match what lupdate writes.
    text = path.read_text(encoding="utf-8")
    if "<!DOCTYPE TS>" not in text:
        text = text.replace("?>", "?>\n<!DOCTYPE TS>", 1)
        path.write_text(text, encoding="utf-8")

    return translated, missing


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--list", action="store_true",
                        help="print the source strings and exit")
    parser.add_argument("--lang", help="only process this language")
    args = parser.parse_args()

    all_languages = languages()
    if not all_languages:
        sys.exit("no .ts files: run the update_translations target first")

    if args.list:
        for text in sources(all_languages[0]):
            print(json.dumps(text, ensure_ascii=False))
        return

    for lang in [args.lang] if args.lang else all_languages:
        result = fill(lang)
        if result is None:
            print(f"{lang}: no i18n/{lang}.json, skipped")
        else:
            done, missing = result
            print(f"{lang}: {done} translated, {missing} missing")


if __name__ == "__main__":
    main()
