#!/usr/bin/env python3
"""Download openly licensed equipment photos through the Openverse API (mostly Flickr).

Only CC0, public-domain mark, CC BY and CC BY-SA images are requested; NC and ND
licenses are never fetched. Wikimedia results are skipped because
fetch_commons.py covers Commons with better metadata.

Anonymous Openverse limits are 20 requests/min and 200/day, so API calls are
spaced 3.2 s apart and downloads happen in between. Classes are fetched round-robin
so a time limit leaves every class partly filled rather than some empty.

Writes <data>/images/<class>/openverse_<id>.jpg and <data>/manifest-openverse.csv.
Re-running skips ids already in the manifest.

Usage: python scripts/photoset/fetch_openverse.py [--minutes 30]
"""

from __future__ import annotations

import argparse
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request

from open_images import AGENT, OFF_TOPIC, Manifest, fetch, log

API = "https://api.openverse.org/v1/images/"
LICENSES = "cc0,pdm,by,by-sa"
API_GAP = 3.2
DOWNLOAD_GAP = 0.6
PAGES = 5

# class -> (target, [queries]); negatives use the subclass as the key.
PLAN = {
    "electric_meter": (220, ["electric meter", "electricity meter house", "smart meter", "electric meters",
                             "power meter house", "watthour meter", "kwh meter", "itron meter",
                             "meter socket", "utility meter"]),
    "breaker_panel": (240, ["breaker panel", "circuit breaker panel", "electrical panel", "breaker box",
                            "load center", "circuit breakers", "fuse box", "electrical service panel",
                            "main breaker", "service entrance electrical"]),
    "gas_meter": (160, ["gas meter", "gas meters", "natural gas meter", "gas regulator meter"]),
    "air_conditioner_condenser": (22, ["air conditioner condenser", "ac unit outside", "heat pump outdoor"]),
    "electrical_junction_box": (22, ["junction box", "disconnect switch", "electrical box outdoor"]),
    "mailbox": (22, ["mailbox", "mailbox house"]),
    "hose_bib": (22, ["hose bib", "outdoor faucet", "spigot"]),
    "pool_equipment": (22, ["pool pump", "pool filter", "pool equipment"]),
    "water_meter": (22, ["water meter"]),
    "telecom_box": (22, ["telephone box wall", "cable box outside", "telecom box"]),
}
NEGATIVE_KINDS = [k for k in PLAN if k not in ("electric_meter", "breaker_panel", "gas_meter")]
# Per-class words that mean the photo is about something else.
EXCLUDE = {
    "electric_meter": re.compile(r"\b(gas|water|parking|solar panel)\b", re.I),
    "breaker_panel": re.compile(r"\b(solar|control panel|instrument|dashboard|door panel|panel discussion|"
                                r"art panel|stained|comic)\b", re.I),
    "gas_meter": re.compile(r"\b(water|gas station|gas pump|petrol|gas mask|parking)\b", re.I),
    "water_meter": re.compile(r"\b(electric|electricity|gas|kwh|parking)\b", re.I),
}
NEGATIVE_EXCLUDE = re.compile(r"\b(meters?|breakers?|electrical panel|fuse box|load center)\b", re.I)


class Openverse:
    def __init__(self) -> None:
        self.last = 0.0
        self.remaining = 200
        self.calls = 0

    def search(self, query: str, page: int) -> list[dict]:
        if self.remaining <= 5:
            return []
        wait = API_GAP - (time.time() - self.last)
        if wait > 0:
            time.sleep(wait)
        params = {"q": query, "license": LICENSES, "excluded_source": "wikimedia", "page_size": 20, "page": page}
        request = urllib.request.Request(f"{API}?{urllib.parse.urlencode(params)}", headers={"User-Agent": AGENT})
        for attempt in range(3):
            self.last = time.time()
            self.calls += 1
            try:
                with urllib.request.urlopen(request, timeout=30) as response:
                    self.remaining = int(response.headers.get("x-ratelimit-available-anon_sustained", self.remaining))
                    return json.load(response).get("results", [])
            except urllib.error.HTTPError as error:
                if error.code == 429:
                    log(f"  openverse 429, sleeping 60 s ({query!r} p{page})")
                    time.sleep(60)
                    continue
                if error.code in (400, 401):  # past the anonymous page limit
                    return []
                time.sleep(5)
            except Exception:  # noqa: BLE001
                time.sleep(5)
        return []


def candidates(api: Openverse, kind: str, queries: list[str]):
    """Yield (query, result) pairs, fetching pages lazily."""
    for page in range(1, PAGES + 1):
        for query in queries:
            results = api.search(query, page)
            for result in results:
                yield query, result


def keep(kind: str, result: dict) -> bool:
    text = " ".join([result.get("title") or ""] + [t.get("name", "") for t in result.get("tags") or []
                                                    if t.get("accuracy") is None])
    if OFF_TOPIC.search(text):
        return False
    if kind in EXCLUDE and EXCLUDE[kind].search(text):
        return False
    if kind in NEGATIVE_KINDS and kind != "water_meter" and NEGATIVE_EXCLUDE.search(text):
        return False
    if result.get("category") in ("illustration", "digitized_artwork"):
        return False
    return result.get("license") in LICENSES.split(",")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--minutes", type=float, default=30)
    args = parser.parse_args()
    deadline = time.time() + args.minutes * 60

    manifest = Manifest("openverse")
    api = Openverse()
    streams = {kind: candidates(api, kind, queries) for kind, (_, queries) in PLAN.items()}
    active = list(PLAN)
    logged = 0
    while active and time.time() < deadline:
        for kind in list(active):
            target = PLAN[kind][0]
            if manifest.count(kind) >= target:
                active.remove(kind)
                continue
            item = next(streams[kind], None)
            if item is None:
                active.remove(kind)
                continue
            query, result = item
            if result["id"] in manifest.ids:
                continue
            if not keep(kind, result):
                manifest.reject("off-topic title/tags or license")
                continue
            data = fetch(result["url"])
            time.sleep(DOWNLOAD_GAP)
            if data is None:
                manifest.reject("download failed")
                continue
            negative = kind in NEGATIVE_KINDS
            creator_url = result.get("creator_url") or ""
            uploader = creator_url.rstrip("/").rsplit("/", 1)[-1] if creator_url else (result.get("creator") or "")
            manifest.add(data, {
                "class": "negative" if negative else kind,
                "subclass": kind if negative else "",
                "source": "openverse",
                "source_id": result["id"],
                "title": result.get("title") or "",
                "page_url": result.get("foreign_landing_url") or "",
                "file_url": result["url"],
                "license": result.get("license", ""),
                "license_version": result.get("license_version") or "",
                "license_url": result.get("license_url") or "",
                "author": result.get("creator") or "",
                "author_url": creator_url,
                "uploader": uploader,
                "group": f"{result.get('source', 'openverse')}:{uploader or result['id']}",
                "query": query,
            })
        if len(manifest.rows) >= logged + 25:
            logged = len(manifest.rows)
            log(f"openverse kept {len(manifest.rows)}  api calls {api.calls}  remaining/day {api.remaining}")

    log("openverse per class: " + ", ".join(f"{k}={manifest.count(k)}" for k in PLAN))
    log(f"openverse kept {len(manifest.rows)}; api calls {api.calls}; rejected {manifest.rejected}")


if __name__ == "__main__":
    main()
