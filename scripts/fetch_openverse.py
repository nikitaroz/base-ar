#!/usr/bin/env python3
"""Download openly licensed meter and panel photos from Openverse (mostly Flickr).

Only licenses that allow commercial use and modification (CC0, CC BY, CC BY-SA, public domain), so
Base can keep training on them. Images land in training/openverse/{meter,panel}/
with training/openverse/sources.csv crediting each one. Standard library only.
Re-running skips files that already exist.
"""

from __future__ import annotations

import csv
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://api.openverse.org/v1/images/"
AGENT = "BaseAR-hackathon/0.1 (training data fetch)"
ROOT = Path(__file__).resolve().parents[1] / "training" / "openverse"
PER_CLASS = 250
# Anonymous requests stop at 240 results (12 pages of 20) per query.
PAGES = 12

QUERIES = {
    "meter": ["electric meter", "electricity meter", "electric meter house", "smart meter house",
              "utility meter", "power meter house", "watt hour meter"],
    "panel": ["breaker panel", "electrical panel", "breaker box", "circuit breaker panel",
              "load center electrical", "service panel electrical", "fuse box house"],
}
# Titles that are clearly some other kind of meter or panel.
SKIP = re.compile(
    r"aircraft|airplane|plane|cockpit|pilot|dc9|boeing|car |truck|boat|ship|yacht|rv |camper|"
    r"parking|taxi|gas meter|water meter|flow meter|light meter|multimeter|voltmeter|ammeter|"
    r"solar panel|control panel|dashboard|instrument|arduino|circuit board|pcb|guitar|synth|"
    r"poem|poetry|music|meter maid|parking meter",
    re.IGNORECASE,
)


def search(query: str, page: int) -> list[dict]:
    params = {"q": query, "page_size": "20", "page": str(page), "license_type": "commercial,modification"}
    request = urllib.request.Request(f"{API}?{urllib.parse.urlencode(params)}", headers={"User-Agent": AGENT})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.load(response).get("results", [])
        except urllib.error.HTTPError as error:
            if error.code in (400, 404):
                return []
            time.sleep(3 * (attempt + 1))
        except Exception:  # noqa: BLE001 - retry transient network errors
            time.sleep(3 * (attempt + 1))
    return []


def main() -> None:
    rows = []
    for kind, queries in QUERIES.items():
        folder = ROOT / kind
        folder.mkdir(parents=True, exist_ok=True)
        seen: dict[str, dict] = {}
        for query in queries:
            for page in range(1, PAGES + 1):
                results = search(query, page)
                if not results:
                    break
                for item in results:
                    if item["id"] in seen or SKIP.search(item.get("title") or ""):
                        continue
                    if min(item.get("width") or 0, item.get("height") or 0) < 400:
                        continue
                    seen[item["id"]] = item
                time.sleep(0.5)
        print(f"{kind}: {len(seen)} candidates")

        kept = 0
        for item in seen.values():
            if kept >= PER_CLASS:
                break
            path = folder / f"{kind}_{item['id'][:12]}.jpg"
            if not path.exists():
                request = urllib.request.Request(item["url"], headers={"User-Agent": AGENT})
                try:
                    with urllib.request.urlopen(request, timeout=60) as response:
                        data = response.read()
                except Exception as error:  # noqa: BLE001
                    print(f"  skip {item['id']}: {error}")
                    continue
                if not data.startswith(b"\xff\xd8"):
                    continue
                path.write_bytes(data)
                time.sleep(0.2)
            kept += 1
            rows.append({
                "file": f"{kind}/{path.name}",
                "title": item.get("title") or "",
                "page": item.get("foreign_landing_url") or "",
                "author": item.get("creator") or "",
                "license": f"{item.get('license', '')} {item.get('license_version') or ''}".strip(),
                "provider": item.get("provider") or "",
            })
        print(f"{kind}: kept {kept}")

    with (ROOT / "sources.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["file", "title", "page", "author", "license", "provider"])
        writer.writeheader()
        writer.writerows(rows)
    print(f"wrote {ROOT / 'sources.csv'} ({len(rows)} rows)")


if __name__ == "__main__":
    main()
