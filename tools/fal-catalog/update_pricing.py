"""Writes the live fal.ai prices into the app's price catalogue.

Only the models the registry actually offers are touched, and only when the
fal billing unit maps cleanly onto one the estimator understands. A unit we
cannot convert honestly -- "compute seconds", which depends on how long the GPU
takes, or "1m tokens" for a video model, which depends on the clip -- is
recorded as unknown rather than converted with a made-up factor. An invented
number on a spending estimate is worse than an admitted gap.
"""

import collections
import io
import json
import re
import sys

FAL = sys.argv[1]
APP = sys.argv[2]
TODAY = "2026-08-10"
SOURCE = "https://api.fal.ai/v1/models/pricing"

# A 9:16 still at the size the studio asks for is about this many megapixels,
# which is what turns a per-megapixel price into a per-image one.
MEGAPIXELS_PER_IMAGE = 1.8


def mapped(amount, unit, category):
    """(unit, amount, approx) for the estimator, or None when unmappable."""
    if amount is None or not unit:
        return None

    unit = unit.strip()

    if unit == "seconds":
        return ("second", amount, False)
    if unit == "images":
        return ("image", amount, False)
    if unit == "videos":
        return ("video", amount, False)
    if unit == "1000 characters":
        return ("kchars", amount, False)
    if unit == "minutes":
        return ("minute", amount, False)

    # "5 seconds", "10 seconds", "30 seconds": a block price.
    block = re.fullmatch(r"(\d+) seconds", unit)
    if block:
        return ("second", amount / int(block.group(1)), False)

    # Billed by the area produced. One generation is one image of about the
    # size the studio asks for, so this converts -- but it is an estimate.
    if unit in ("megapixels", "processed megapixels"):
        return ("image", amount * MEGAPIXELS_PER_IMAGE, True)

    # "units", "generations", "credits", "video segments" and the token
    # buckets are deliberately NOT converted. They look like a flat price per
    # generation and are not: Seedance 2.0 bills 0.014 "units" for a clip that
    # actually costs cents-to-dollars depending on its length and resolution,
    # so treating a unit as a video would print a penny on the confirmation
    # screen. A gap is recoverable; a figure that is wrong by two orders of
    # magnitude is what makes somebody press Generate ten times.

    # Everything else -- compute seconds, token buckets, credits, steps -- has
    # no fixed relationship to anything the estimator can count in advance.
    return None


def registry_ids(path):
    source = io.open(path, encoding="utf-8").read()
    return re.findall(r"ModelEntry\(\s*'([^']+)'", source)


def main():
    catalogue = {
        c["endpoint_id"]: c
        for c in json.load(io.open(FAL + "/fal_catalog.json", encoding="utf-8"))
    }

    pricing_path = APP + "/assets/resources/pricing.json"
    pricing = json.load(
        io.open(pricing_path, encoding="utf-8"),
        object_pairs_hook=collections.OrderedDict,
    )
    models = pricing["models"]

    wanted = [i for i in registry_ids(APP + "/lib/providers/registry.dart")
              if i in catalogue]

    written = unknown = skipped = 0
    for endpoint in wanted:
        entry = catalogue[endpoint]
        price = entry["pricing"]
        conversion = mapped(price["amount"], price["unit"] or "", entry["category"])

        if conversion is None:
            # The live figure cannot be converted honestly. Whatever estimate
            # the catalogue already carried stays -- an approximation in the
            # right order of magnitude beats a blank on an estimate, and this
            # pass must only ever add coverage.
            if endpoint in models and models[endpoint].get("unknown") is not True:
                skipped += 1
            else:
                models[endpoint] = {"unknown": True, "source": SOURCE}
                unknown += 1
            continue

        unit, amount, approx = conversion
        record = collections.OrderedDict(
            [("unit", unit), ("amount", round(amount, 6))]
        )
        if approx:
            record["approx"] = True
        record["source"] = SOURCE
        models[endpoint] = record
        written += 1

    # Claude Sonnet 5 is on introductory pricing until 2026-08-31; the estimate
    # should say what is billed today.
    models["claude-sonnet-5"] = collections.OrderedDict([
        ("unit", "tokens"),
        ("in", 2.0),
        ("out", 10.0),
        ("source", "https://platform.claude.com/docs/en/about-claude/pricing"),
    ])

    pricing["updated"] = TODAY
    io.open(pricing_path, "w", encoding="utf-8", newline="\n").write(
        json.dumps(pricing, ensure_ascii=False, indent=2) + "\n"
    )

    print("registry models found on fal:", len(wanted))
    print("priced:", written)
    print("recorded as unknown:", unknown)
    print("left on their existing estimate:", skipped)
    print("catalogue entries now:", len(models))
    print()
    print("unmappable units among them:")
    for endpoint in wanted:
        p = catalogue[endpoint]["pricing"]
        if mapped(p["amount"], p["unit"] or "", catalogue[endpoint]["category"]) is None:
            print("   %-58s %s %s" % (endpoint, p["amount"], p["unit"]))


main()
