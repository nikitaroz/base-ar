#!/usr/bin/env python3
"""Download openly licensed equipment photos from Wikimedia Commons.

Commons has few US residential photos: "Electricity meters in the United States"
and "Distribution boards in the United States" do not exist (checked 2026-09-26),
so this crawls the real categories below plus full-text file search for US brand
and product names. Every file's license comes from imageinfo extmetadata; files
without a free license short name are skipped.

Classes are fetched round-robin so a time limit leaves every class partly filled.
Writes <data>/images/<class>/commons_<pageid>.jpg and <data>/manifest-commons.csv
(see open_images.py). Re-running skips files already in the manifest.

Usage: python scripts/photoset/fetch_commons.py [--minutes 30]
"""

from __future__ import annotations

import argparse
import json
import re
import time
import urllib.parse
import urllib.request

from open_images import OFF_TOPIC, Manifest, fetch, log

API = "https://commons.wikimedia.org/w/api.php"
DOWNLOAD_GAP = 0.4
FREE = re.compile(r"^(cc0|cc[ -]by|cc-by|public domain|pd|attribution|copyrighted free use|gfdl|fal|"
                  r"no restrictions|usgov)", re.I)

# class -> (target, categories as (name, depth), searches). Category names verified via the API.
PLAN = {
    "electric_meter": (220, [
        ("Electricity meters in Canada", 1), ("Smart meters", 1), ("Electronic electricity meters", 1),
        ("Electricity meter mounts", 0), ("Automatic meter reading", 0), ("Landis & Gyr electricity meters", 0),
        ("Electricity meters (kWh)", 0), ("Electricity meters with liquid crystal displays", 0),
    ], ["Itron electricity meter", "Landis+Gyr meter", "Aclara meter", "Elster meter", "Sensus meter",
        "smart meter house", "electric meter house", "electric meter wall", "watthour meter", "meter socket",
        "electricity meter United States", "electric meter Texas", "electric meter California"]),
    "breaker_panel": (240, [
        ("Main distribution boards", 0), ("Fuse boxes with DIN rail", 0), ("Distribution boards in Germany", 1),
        ("Distribution boards in the Netherlands", 0), ("Distribution boards", 0),
    ], ["load center breaker", "breaker panel", "circuit breaker panel", "electrical panel breakers",
        "breaker box", "electrical service panel", "Square D panel", "Cutler-Hammer panel", "Stab-Lok",
        "Zinsco", "main breaker panel", "meter main combination", "service entrance panel",
        "residential electrical panel", "consumer unit"]),
    "gas_meter": (160, [("Gas meters", 2)],
                  ["gas meter house", "natural gas meter", "gas meter regulator", "gas service regulator"]),
    "air_conditioner_condenser": (22, [("Split type air conditioners - condenser in the United States", 0),
                                       ("Air source heat pumps", 0)],
                                  ["air conditioner condenser", "central air conditioning unit"]),
    "electrical_junction_box": (22, [], ["junction box electrical", "disconnect switch air conditioner",
                                         "electrical box wall"]),
    "mailbox": (22, [("Letter boxes in the United States", 1)], ["mailbox house"]),
    "hose_bib": (22, [], ["hose bib", "outdoor faucet", "spigot wall", "garden tap wall"]),
    "pool_equipment": (22, [], ["pool pump", "swimming pool filter", "pool equipment"]),
    "water_meter": (22, [("Water meters", 1)], ["water meter"]),
    "telecom_box": (22, [], ["telephone junction box", "network interface device telephone",
                             "telecommunications cabinet", "cable tv box wall"]),
}
NEGATIVE_KINDS = [k for k in PLAN if k not in ("electric_meter", "breaker_panel", "gas_meter")]
SKIP_CATEGORY = re.compile(r"disassembl|diagram|wiring|manufacturer|motor control|nh fused|cabling|accessor|"
                           r"introduction device|painted|street light|vehicle|factory|museum|logo|employees|"
                           r"utility cabinets|by city|by municipality|by district", re.I)
EXCLUDE = {
    "electric_meter": re.compile(r"\b(gas|water|parking)\b", re.I),
    "breaker_panel": re.compile(r"\b(solar|control panel|instrument)\b", re.I),
    "gas_meter": re.compile(r"\b(water|station|pump)\b", re.I),
    "water_meter": re.compile(r"\b(electric|electricity|gas|kwh)\b", re.I),
}
NEGATIVE_EXCLUDE = re.compile(r"\b(meters?|breakers?|electrical panel|fuse box|load center)\b", re.I)


def api(**params) -> dict:
    params |= {"format": "json", "formatversion": "2"}
    data = fetch(f"{API}?{urllib.parse.urlencode(params)}", timeout=30, attempts=4)
    return json.loads(data) if data else {}


def category_files(title: str, depth: int, seen: set[str]) -> list[str]:
    if title in seen or SKIP_CATEGORY.search(title):
        return []
    seen.add(title)
    files, subcats, cont = [], [], {}
    while True:
        data = api(action="query", list="categorymembers", cmtitle=f"Category:{title}",
                   cmtype="file|subcat", cmlimit="500", **cont)
        for member in data.get("query", {}).get("categorymembers", []):
            name = member["title"]
            (subcats if name.startswith("Category:") else files).append(name.removeprefix("Category:"))
        cont = data.get("continue", {})
        if not cont:
            break
    if depth > 0:
        # North American hardware first.
        subcats.sort(key=lambda name: not re.search(r"United States|Canada|America", name))
        for sub in subcats:
            files += category_files(sub, depth - 1, seen)
    return files


def search_files(query: str) -> list[str]:
    data = api(action="query", list="search", srsearch=f"{query} filetype:bitmap", srnamespace="6", srlimit="100")
    return [hit["title"] for hit in data.get("query", {}).get("search", [])]


def image_info(titles: list[str]):
    for start in range(0, len(titles), 50):
        data = api(action="query", titles="|".join(titles[start:start + 50]), prop="imageinfo",
                   iiprop="url|size|mime|extmetadata|user", iiurlwidth="1280")
        for page in data.get("query", {}).get("pages", []):
            if page.get("imageinfo"):
                yield {"title": page["title"], "pageid": page.get("pageid", 0), **page["imageinfo"][0]}


def clean(value: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", value or "")).strip()


def keep(kind: str, title: str) -> bool:
    if OFF_TOPIC.search(title) or (kind in EXCLUDE and EXCLUDE[kind].search(title)):
        return False
    return not (kind in NEGATIVE_KINDS and kind != "water_meter" and NEGATIVE_EXCLUDE.search(title))


def stream(kind: str, categories: list[tuple[str, int]], searches: list[str], seen_titles: set[str]):
    """Yield (query, imageinfo) for one class, category members first, then search hits."""
    seen_categories: set[str] = set()
    sources = [(f"Category:{name}", lambda n=name, d=depth: category_files(n, d, seen_categories))
               for name, depth in categories]
    sources += [(f"search:{q}", lambda q=q: search_files(q)) for q in searches]
    for label, load in sources:
        titles = [t for t in dict.fromkeys(load()) if t not in seen_titles and keep(kind, t)]
        seen_titles.update(titles)
        for info in image_info(titles):
            yield label, info


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--minutes", type=float, default=30)
    args = parser.parse_args()
    deadline = time.time() + args.minutes * 60

    manifest = Manifest("commons")
    done_titles = {row["title"] for row in manifest.rows}
    seen_titles: set[str] = set(done_titles)
    streams = {kind: stream(kind, cats, searches, seen_titles) for kind, (_, cats, searches) in PLAN.items()}
    active, logged = list(PLAN), 0
    while active and time.time() < deadline:
        for kind in list(active):
            if manifest.count(kind) >= PLAN[kind][0]:
                active.remove(kind)
                continue
            item = next(streams[kind], None)
            if item is None:
                active.remove(kind)
                continue
            query, info = item
            if info.get("mime") not in ("image/jpeg", "image/png", "image/webp"):
                manifest.reject("not a bitmap photo")
                continue
            if min(info["width"], info["height"]) < 480:
                manifest.reject("short edge < 480")
                continue
            meta = info.get("extmetadata", {})
            license_name = clean(meta.get("LicenseShortName", {}).get("value", ""))
            if not FREE.search(license_name):
                manifest.reject(f"license {license_name or 'missing'}")
                continue
            # Commons serves standard thumb widths; portrait images use 960 so the long edge stays ~1280.
            url = info.get("thumburl") or info["url"]
            if info["height"] > info["width"] and info["width"] > 960:
                url = url.replace("/1280px-", "/960px-")
            data = fetch(url)
            time.sleep(DOWNLOAD_GAP)
            if data is None:
                manifest.reject("download failed")
                continue
            negative = kind in NEGATIVE_KINDS
            uploader = info.get("user", "")
            manifest.add(data, {
                "class": "negative" if negative else kind,
                "subclass": kind if negative else "",
                "source": "commons",
                "source_id": str(info["pageid"]),
                "title": info["title"],
                "page_url": info.get("descriptionurl", ""),
                "file_url": info["url"],
                "license": license_name,
                "license_version": "",
                "license_url": clean(meta.get("LicenseUrl", {}).get("value", "")),
                "author": clean(meta.get("Artist", {}).get("value", ""))[:200],
                "author_url": "",
                "uploader": uploader,
                "group": f"commons:{uploader or info['title']}",
                "query": query,
            })
            if len(manifest.rows) >= logged + 25:
                logged = len(manifest.rows)
                log(f"commons kept {logged}: " + ", ".join(f"{k}={manifest.count(k)}" for k in PLAN))

    log("commons per class: " + ", ".join(f"{k}={manifest.count(k)}" for k in PLAN))
    log(f"commons kept {len(manifest.rows)}; rejected {manifest.rejected}")


if __name__ == "__main__":
    main()
