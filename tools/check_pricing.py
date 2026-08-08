#!/usr/bin/env python3
"""Keeps resources/pricing.json in step with the model catalogue.

A model the price list has never heard of drops out of the cost estimate
silently, which is the one failure the estimate must not have. So every id in
Registry.cpp has to appear here, either with a price or explicitly marked
"unknown": true -- and an entry for a model that no longer exists is dead
weight worth deleting.

Run directly, or through ctest as the `pricing_catalogue` test.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REGISTRY = ROOT / "src" / "providers" / "Registry.cpp"
PRICING = ROOT / "resources" / "pricing.json"


def registry_models():
    """Every model id in the catalogue. They all go through the M() shorthand;
    "auto" is a placeholder resolved before any call, so it never appears."""
    text = REGISTRY.read_text(encoding="utf-8")
    return {match.group(1) for match in re.finditer(r'\bM\("([^"]+)"\s*,', text)}


def main():
    models = registry_models()
    if not models:
        print("check_pricing: no models found in Registry.cpp -- did M() change?")
        return 1

    catalogue = json.loads(PRICING.read_text(encoding="utf-8"))["models"]

    missing = sorted(model for model in models if model not in catalogue)
    stale = sorted(key for key in catalogue if key not in models)
    priced = sorted(
        model for model in models
        if model in catalogue and not catalogue[model].get("unknown")
    )

    for model in missing:
        print(f"check_pricing: {model} is in the registry but not in pricing.json")
    for key in stale:
        print(f"check_pricing: {key} is priced but no longer in the registry")

    print(
        f"check_pricing: {len(priced)}/{len(models)} models priced, "
        f"{len(models) - len(priced)} unknown"
    )
    return 1 if missing or stale else 0


if __name__ == "__main__":
    sys.exit(main())
