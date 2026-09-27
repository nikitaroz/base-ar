"""Shared helpers for the openly licensed equipment photo set.

Images live outside the repo (default ~/base-ar-data/open-images, override with
BASE_AR_DATA). Each fetcher writes its own manifest-<source>.csv there, one row
per kept image, so two fetchers can run at once. scripts/photoset/autolabel.py merges them,
drops cross-source near-duplicates, splits by uploader and writes the committed
attribution list dataset/open-images-manifest.csv.

Needs Pillow and imagehash (scripts/requirements-training.txt).
"""

from __future__ import annotations

import csv
import hashlib
import io
import os
import re
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import imagehash
from PIL import Image, ImageOps

DATA = Path(os.environ.get("BASE_AR_DATA", Path.home() / "base-ar-data")) / "open-images"
IMAGES = DATA / "images"
AGENT = "BaseSiteSurvey-hackathon/0.2 (open-license detector training data; logan.may@superbuilders.school)"
MIN_SHORT_EDGE = 480
MAX_LONG_EDGE = 1280
NEAR_DUPLICATE = 6  # perceptual-hash Hamming distance

POSITIVE = ["electric_meter", "breaker_panel", "gas_meter"]
NEGATIVE = ["air_conditioner_condenser", "electrical_junction_box", "mailbox", "hose_bib",
            "pool_equipment", "water_meter", "telecom_box"]
FIELDS = ["file", "class", "subclass", "source", "source_id", "title", "page_url", "file_url",
          "license", "license_version", "license_url", "author", "author_url", "uploader", "group",
          "sha1", "phash", "width", "height", "query", "fetched_at"]

# Titles and tags that mean the photo is not residential site equipment.
OFF_TOPIC = re.compile(
    r"\b(aircraft|airplane|airliner|cockpit|boeing|airbus|cessna|7[0-9]7|dc-?\d+|helicopter|locomotive|train|"
    r"railway|tram|subway|bus|truck|car|vehicle|automotive|ship|boat|submarine|navy|uss|tank|rv|camper|"
    r"parking|taxi|light meter|exposure|multimeter|voltmeter|ammeter|oscilloscope|diagram|schematic|"
    r"drawing|logo|icon|illustration|cartoon|clipart|infographic|chart|poster|map|screenshot|stamp|"
    r"museum|antique|toy|lego|minecraft|game|render|3d model|factory|assembly line)\b",
    re.IGNORECASE,
)


def log(message: str) -> None:
    print(message, flush=True)


def fetch(url: str, timeout: int = 60, attempts: int = 3) -> bytes | None:
    request = urllib.request.Request(url, headers={"User-Agent": AGENT})
    for attempt in range(attempts):
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            if error.code in (403, 404, 410):
                return None
            time.sleep(3 * (attempt + 1))
        except Exception:  # noqa: BLE001 - retry transient network errors
            time.sleep(3 * (attempt + 1))
    return None


class Manifest:
    """Append-only CSV plus in-memory sha1 and perceptual-hash indexes for one source."""

    def __init__(self, source: str) -> None:
        DATA.mkdir(parents=True, exist_ok=True)
        self.path = DATA / f"manifest-{source}.csv"
        self.rows = list(csv.DictReader(self.path.open())) if self.path.exists() else []
        self.sha1 = {row["sha1"] for row in self.rows}
        self.ids = {row["source_id"] for row in self.rows}
        self.hashes = [imagehash.hex_to_hash(row["phash"]) for row in self.rows]
        self.rejected: dict[str, int] = {}

    def count(self, cls: str) -> int:
        return sum(1 for row in self.rows if row["class"] == cls or row["subclass"] == cls)

    def reject(self, why: str) -> None:
        self.rejected[why] = self.rejected.get(why, 0) + 1

    def add(self, data: bytes, row: dict) -> bool:
        """Validate, normalise to JPEG, dedupe and record one download. Returns True if kept."""
        sha1 = hashlib.sha1(data).hexdigest()
        if sha1 in self.sha1:
            self.reject("duplicate sha1")
            return False
        try:
            image = ImageOps.exif_transpose(Image.open(io.BytesIO(data))).convert("RGB")
        except Exception:  # noqa: BLE001 - corrupt or non-image payload
            self.reject("not an image")
            return False
        if min(image.size) < MIN_SHORT_EDGE:
            self.reject("short edge < 480")
            return False
        if max(image.size) / min(image.size) > 2.6:
            self.reject("extreme aspect")
            return False
        if _is_graphic(image):
            self.reject("flat graphic")
            return False
        phash = imagehash.phash(image)
        if any(phash - other <= NEAR_DUPLICATE for other in self.hashes):
            self.reject("near duplicate")
            return False
        image.thumbnail((MAX_LONG_EDGE, MAX_LONG_EDGE))
        folder = IMAGES / (row["class"] if row["class"] != "negative" else "negative")
        folder.mkdir(parents=True, exist_ok=True)
        stem = f"{row['source']}_{re.sub(r'[^A-Za-z0-9]+', '', row['source_id'])[:40]}"
        path = folder / f"{stem}.jpg"
        image.save(path, quality=90)
        row |= {
            "file": str(path.relative_to(DATA)),
            "sha1": sha1,
            "phash": str(phash),
            "width": image.width,
            "height": image.height,
            "fetched_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        }
        new_file = not self.path.exists()
        with self.path.open("a", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=FIELDS, extrasaction="ignore")
            if new_file:
                writer.writeheader()
            writer.writerow(row)
        self.rows.append(row)
        self.sha1.add(sha1)
        self.ids.add(row["source_id"])
        self.hashes.append(phash)
        return True


def _is_graphic(image: Image.Image) -> bool:
    """Logos, renders and diagrams have very few distinct colours; photos have thousands."""
    small = image.resize((96, 96))
    return len(set(small.getdata())) < 600
