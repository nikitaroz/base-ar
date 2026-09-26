#!/usr/bin/env python3
"""Download freely licensed meter and panel photos from Wikimedia Commons.

Images land in training/raw/{meter,panel}/ at 1280 px on the long edge, with
training/raw/sources.csv recording URL, author and license for each file.
Standard library only. Re-running skips files that already exist.
"""

from __future__ import annotations

import csv
import json
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://commons.wikimedia.org/w/api.php"
AGENT = "BaseAR-hackathon/0.1 (training data fetch; contact nikitaroz@gmail.com)"
ROOT = Path(__file__).resolve().parents[1] / "training" / "raw"
PER_CLASS = 200
MAX_DEPTH = 3

# US categories come first so the cap favours North American hardware.
SEEDS = {
    "meter": [
        "Electricity meters in the United States",
        "Smart meters",
        "Electricity meter mounts",
        "Electronic electricity meters",
        "Electricity meters (kWh)",
        "Electricity meters by country",
    ],
    "panel": [
        "Distribution boards in the United States",
        "Distribution boards",
        "Fuse boxes",
        "Distribution boards by country",
    ],
}
SEARCHES = {
    "meter": ["electric meter house", "electricity meter wall", "smart meter house"],
    "panel": ["breaker panel", "electrical panel breakers", "circuit breaker box", "load center"],
}
SKIP = re.compile(
    r"vehicle|street light|disassembl|din rail|diagram|factory|locomotive|employees|"
    r"wiring|manufacturer|motor control|nh fused|cabling|accessor|introduction device|"
    r"logo|icon|svg|drawing|schematic|museum|antique|historic",
    re.IGNORECASE,
)


def api(**params) -> dict:
    params |= {"format": "json", "formatversion": "2"}
    request = urllib.request.Request(f"{API}?{urllib.parse.urlencode(params)}", headers={"User-Agent": AGENT})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.load(response)
        except Exception:  # noqa: BLE001 - retry transient network errors
            time.sleep(2 * (attempt + 1))
    return {}


def category_files(title: str, depth: int, seen: set[str]) -> list[str]:
    if title in seen or SKIP.search(title):
        return []
    seen.add(title)
    files: list[str] = []
    subcats: list[str] = []
    cont: dict = {}
    while True:
        data = api(action="query", list="categorymembers", cmtitle=f"Category:{title}",
                   cmtype="file|subcat", cmlimit="500", **cont)
        for member in data.get("query", {}).get("categorymembers", []):
            name = member["title"]
            if name.startswith("Category:"):
                subcats.append(name.removeprefix("Category:"))
            else:
                files.append(name)
        cont = data.get("continue", {})
        if not cont:
            break
    if depth < MAX_DEPTH:
        subcats.sort(key=lambda name: "United States" not in name)
        for sub in subcats:
            files += category_files(sub, depth + 1, seen)
    return files


def search_files(query: str) -> list[str]:
    data = api(action="query", list="search", srsearch=f"{query} filetype:bitmap", srnamespace="6", srlimit="100")
    return [hit["title"] for hit in data.get("query", {}).get("search", [])]


def image_info(titles: list[str]) -> list[dict]:
    infos = []
    for start in range(0, len(titles), 50):
        data = api(action="query", titles="|".join(titles[start:start + 50]), prop="imageinfo",
                   iiprop="url|size|mime|extmetadata", iiurlwidth="1280")
        for page in data.get("query", {}).get("pages", []):
            if page.get("imageinfo"):
                infos.append({"title": page["title"], **page["imageinfo"][0]})
    return infos


def clean(value: str) -> str:
    return re.sub(r"<[^>]+>", "", value or "").strip()


def main() -> None:
    rows = []
    for kind in ("meter", "panel"):
        folder = ROOT / kind
        folder.mkdir(parents=True, exist_ok=True)
        titles: list[str] = []
        seen: set[str] = set()
        for seed in SEEDS[kind]:
            titles += category_files(seed, 0, seen)
        for query in SEARCHES[kind]:
            titles += search_files(query)
        titles = [t for t in dict.fromkeys(titles) if not SKIP.search(t)]
        print(f"{kind}: {len(titles)} candidates")

        kept = 0
        for info in image_info(titles):
            if kept >= PER_CLASS:
                break
            if info.get("mime") not in ("image/jpeg", "image/png") or min(info["width"], info["height"]) < 480:
                continue
            meta = info.get("extmetadata", {})
            license_name = clean(meta.get("LicenseShortName", {}).get("value", ""))
            if not license_name:
                continue
            # Commons only serves standard thumb widths; tall images use 960 so the long edge stays reasonable.
            url = info.get("thumburl") or info["url"]
            if info["height"] > info["width"] and info["width"] > 960:
                url = url.replace("/1280px-", "/960px-")
            name = f"{kind}_{kept:04d}.jpg"
            path = folder / name
            if not path.exists():
                request = urllib.request.Request(url, headers={"User-Agent": AGENT})
                try:
                    with urllib.request.urlopen(request, timeout=60) as response:
                        path.write_bytes(response.read())
                except Exception as error:  # noqa: BLE001
                    print(f"  skip {info['title']}: {error}")
                    continue
                time.sleep(0.2)
            kept += 1
            rows.append({
                "file": f"{kind}/{name}",
                "title": info["title"],
                "page": info.get("descriptionurl", ""),
                "author": clean(meta.get("Artist", {}).get("value", "")),
                "license": license_name,
            })
        print(f"{kind}: kept {kept}")

    with (ROOT / "sources.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["file", "title", "page", "author", "license"])
        writer.writeheader()
        writer.writerows(rows)
    print(f"wrote {ROOT / 'sources.csv'} ({len(rows)} rows)")


if __name__ == "__main__":
    main()
