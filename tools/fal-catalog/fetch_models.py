"""Pulls the whole fal.ai model catalogue through the platform API.

Cursor pagination, exhausted until has_more goes false. No inference is ever
requested -- this only reads the catalogue. The key comes from FAL_KEY and is
never written to disk.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

KEY = os.environ.get("FAL_KEY", "")
OUT = sys.argv[1]

if not KEY:
    raise SystemExit("FAL_KEY is not set")


def get(url):
    request = urllib.request.Request(
        url, headers={"Authorization": "Key " + KEY, "Accept": "application/json"}
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.loads(response.read().decode("utf-8"))


def main():
    models = []
    cursor = ""
    requests = 0

    while True:
        url = "https://api.fal.ai/v1/models"
        if cursor:
            url += "?cursor=" + cursor
        page = get(url)
        requests += 1

        batch = page.get("models", [])
        models.extend(batch)
        print("page %d: +%d (total %d)" % (requests, len(batch), len(models)))

        if not page.get("has_more"):
            break
        cursor = page.get("next_cursor") or ""
        if not cursor:
            break
        time.sleep(0.15)

    with open(OUT + "/fal_models.json", "w", encoding="utf-8") as handle:
        json.dump(models, handle, ensure_ascii=False, indent=1)

    print("models:", len(models))
    print("requests:", requests)


main()
