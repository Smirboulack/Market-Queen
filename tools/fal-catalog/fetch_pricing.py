"""Fetches the unit price of every model in fal_models.json.

/v1/models/pricing takes repeated endpoint_id parameters -- forty at a time is
accepted and answered in one page -- and rate-limits hard, so every call backs
off and retries rather than dropping a batch on the floor. A model the endpoint
says nothing about simply has no price; that is recorded as such rather than
guessed at.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

KEY = os.environ.get("FAL_KEY", "")
OUT = sys.argv[1]
BATCH = 40
PAUSE = 2.0

if not KEY:
    raise SystemExit("FAL_KEY is not set")

requests_made = 0


def get(url):
    global requests_made
    delay = PAUSE
    for attempt in range(8):
        request = urllib.request.Request(
            url, headers={"Authorization": "Key " + KEY, "Accept": "application/json"}
        )
        try:
            with urllib.request.urlopen(request, timeout=90) as response:
                requests_made += 1
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as error:
            requests_made += 1
            if error.code in (429, 500, 502, 503, 504) and attempt < 7:
                time.sleep(delay)
                delay = min(delay * 1.8, 30)
                continue
            print("  ! HTTP %d on a batch, skipping it" % error.code)
            return {}
        except (urllib.error.URLError, TimeoutError):
            if attempt < 7:
                time.sleep(delay)
                delay = min(delay * 1.8, 30)
                continue
            return {}
    return {}


def main():
    models = json.load(open(OUT + "/fal_models.json", encoding="utf-8"))
    ids = [m["endpoint_id"] for m in models]

    prices = {}
    for start in range(0, len(ids), BATCH):
        chunk = ids[start:start + BATCH]
        query = "&".join(
            "endpoint_id=" + urllib.parse.quote(i, safe="") for i in chunk
        )
        page = get("https://api.fal.ai/v1/models/pricing?" + query)
        for price in page.get("prices", []):
            prices[price["endpoint_id"]] = price

        print("%d/%d  priced %d" % (start + len(chunk), len(ids), len(prices)))
        time.sleep(PAUSE)

    with open(OUT + "/fal_models_pricing.json", "w", encoding="utf-8") as handle:
        json.dump(prices, handle, ensure_ascii=False, indent=1)

    complete = []
    catalogue = []
    for model in models:
        endpoint = model["endpoint_id"]
        meta = model.get("metadata", {})
        price = prices.get(endpoint)

        complete.append({**model, "pricing": price})
        catalogue.append({
            "id": endpoint,
            "name": meta.get("display_name") or endpoint,
            "provider": endpoint.split("/")[0],
            "category": meta.get("category", ""),
            "endpoint_id": endpoint,
            "description": (meta.get("description") or "").strip(),
            "status": meta.get("status", ""),
            "pricing": {
                "amount": price.get("unit_price") if price else None,
                "unit": price.get("unit") if price else None,
                "currency": price.get("currency", "USD") if price else "USD",
            },
            "model_url": meta.get("model_url", ""),
            "raw": model,
        })

    for name, payload in (
        ("fal_models_complete.json", complete),
        ("fal_catalog.json", catalogue),
    ):
        with open(OUT + "/" + name, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=False, indent=1)

    print("---")
    print("models found:", len(models))
    print("models with pricing:", len(prices))
    print("models without pricing:", len(models) - len(prices))
    print("api requests (pricing):", requests_made)


main()
