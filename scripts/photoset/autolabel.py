#!/usr/bin/env python3
"""Draft YOLO labels for a human to review, then build the train/val dataset.

Classes: 0 electric_meter, 1 breaker_panel, 2 gas_meter. The app maps 0 and 1 and
ignores 2 until EquipmentDetecting.kind(at:) learns it, so the 3-class model is a
drop-in replacement.

Inputs
- The open-images set from fetch_commons.py and fetch_openverse.py (<data>/manifest-*.csv,
  see open_images.py). Each photo's class is already known from its category or search
  query, so the labeler only has to find it: boxes of the photo's own class count at
  OWN_CONF, other equipment classes only at OTHER_CONF. Panels are labeled like meters.
  Negatives (AC condensers, junction boxes, mailboxes, hose bibs, pool equipment, water
  meters, telecom boxes) get empty label files. One where the labeler sees equipment above
  NEG_FLAG stays a negative (a water meter called a meter is the hard case the app needs)
  but is listed in review/negatives_flagged.txt and drawn on its own sheet for a human check.
- Hand-labeled photos (a YOLO .txt sidecar next to the image) in training/site,
  training/reference and training/negatives are copied as-is and repeated HAND_REPEAT
  times so they outweigh web photos. Unlabeled ones there are drafted by stem prefix
  (meter_, panel_, gas_; anything else is a negative).
Stems listed in <data>/exclude.txt or training/exclude.txt (one per line) are skipped.

Labelers (--labeler)
- owlv2 (default): google/owlv2-base-patch16-ensemble through transformers (Apache-2.0).
  On 18 held-out Commons photos it named every AC, the mailbox, a gas meter and the panels,
  where YOLOE-26l called the mailbox a meter (0.79) and a closed panel a watt-hour meter (0.87).
- yoloe: yoloe-26l-seg.pt through ultralytics (AGPL-3.0), the original pipeline.
Raw detections are cached in <data>/detections-<labeler>.json, so re-running with new
thresholds is instant; --relabel clears the cache.

Split: open images by uploader (one Flickr account or Commons uploader never spans train
and val, so val is not near-duplicates of train); photos matching --holdout (perceptual
hash) are forced into val; hand-labeled photos use VAL_STEMS.

Outputs
- <data>/labels/<stem>.txt drafted YOLO labels (empty file for a negative)
- <out>/{images,labels}/{train,val} and <out>/data.yaml (default training/dataset)
- <data>/review/<class>_NN.jpg contact sheets (100 per sheet, boxes drawn), plus
  unlabeled and flagged sheets and lists
- dataset/open-images-manifest.csv in the repo: attribution, split and box count per photo

Run with the training venv, e.g. ~/base-ar-data/.venv/bin/python scripts/photoset/autolabel.py
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import shutil
from collections import Counter, defaultdict
from pathlib import Path

import imagehash
from PIL import Image, ImageDraw, ImageOps

from open_images import DATA, FIELDS, NEAR_DUPLICATE, POSITIVE

REPO = Path(__file__).resolve().parents[2]
TRAINING = REPO / "training"
NAMES = ["electric_meter", "breaker_panel", "gas_meter"]
CLASS_ID = {name: i for i, name in enumerate(NAMES)}
HAND_LABELED = ["site", "reference", "negatives"]
PREFIX_CLASS = {"meter": 0, "panel": 1, "gas": 2}
# Held-out site photos, so validation measures the real target look.
VAL_STEMS = {"meter_IMG_5092", "meter_IMG_5094", "panel_IMG_5084", "panel_IMG_5096",
             "neg_IMG_5110", "neg_IMG_5113", "neg_IMG_5116"}
HAND_REPEAT = 3
VAL_FRACTION = 0.18
VAL_MAX = 0.26
SOURCE_ORDER = ["commons", "openverse"]  # commons wins a cross-source duplicate: richer metadata
COLORS = ["#2f9e44", "#e8590c", "#1c7ed6"]
FLAG_COLOR = "#e03131"

# Queries per class id; -1 are distractors so an AC or mailbox box does not win a meter's argmax.
OWL_QUERIES = {
    0: ["a photo of an electric meter", "a photo of a smart electricity meter",
        "a photo of a utility power meter on a house wall"],
    1: ["a photo of a residential electrical breaker panel", "a photo of a circuit breaker box",
        "a photo of an electrical load center"],
    2: ["a photo of a gas meter", "a photo of a natural gas meter with regulator"],
    -1: ["a photo of an air conditioner", "a photo of a mailbox", "a photo of a water meter",
         "a photo of an electrical disconnect switch", "a photo of a pool pump", "a photo of a faucet"],
}
YOLOE_PROMPTS = {
    0: ["electric meter", "electricity meter", "utility meter", "smart meter", "watt-hour meter"],
    1: ["breaker panel", "electrical panel", "breaker box", "circuit breaker panel", "load center",
        "fuse box", "distribution board"],
    2: ["gas meter", "natural gas meter", "gas regulator"],
    -1: ["air conditioner", "mailbox", "water meter", "disconnect switch", "pool pump", "faucet"],
}
# (own class, share of the best own box, other equipment classes, negative flag)
THRESHOLDS = {"owlv2": (0.16, 0.5, 0.30, 0.30), "yoloe": (0.30, 0.5, 0.50, 0.50)}
CONTAINER_SHARE = 0.8


# ---------------------------------------------------------------- labelers

class Owl:
    def __init__(self) -> None:
        import torch
        from transformers import Owlv2ForObjectDetection, Owlv2Processor

        self.torch = torch
        self.device = "mps" if torch.backends.mps.is_available() else "cpu"
        name = "google/owlv2-base-patch16-ensemble"
        self.processor = Owlv2Processor.from_pretrained(name)
        self.model = Owlv2ForObjectDetection.from_pretrained(name).to(self.device).eval()
        self.queries = [(cls, q) for cls, qs in OWL_QUERIES.items() for q in qs]

    def __call__(self, path: Path) -> list[list]:
        """[[argmax class, [score per class -1, 0, 1, 2], xyxy]] after per-class NMS."""
        from torchvision.ops import nms

        torch = self.torch
        image = ImageOps.exif_transpose(Image.open(path)).convert("RGB")
        inputs = self.processor(text=[[q for _, q in self.queries]], images=image, return_tensors="pt").to(self.device)
        with torch.no_grad():
            outputs = self.model(**inputs)
        probs = outputs.logits[0].sigmoid().float().cpu()  # boxes x queries
        classes = torch.tensor([cls for cls, _ in self.queries])
        per_class = torch.stack([probs[:, classes == c].max(dim=1).values for c in (-1, 0, 1, 2)], dim=1)
        side = max(image.size)  # OWLv2 pads to a square at the bottom and right
        cx, cy, w, h = (outputs.pred_boxes[0].float().cpu() * side).unbind(-1)
        boxes = torch.stack([cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2], dim=1)
        boxes[:, 0::2] = boxes[:, 0::2].clamp(0, image.width)
        boxes[:, 1::2] = boxes[:, 1::2].clamp(0, image.height)
        keep: set[int] = set()
        for column, floor in ((0, 0.15), (1, 0.06), (2, 0.06), (3, 0.06)):
            candidates = (per_class[:, column] >= floor).nonzero().flatten()
            if len(candidates):
                kept = nms(boxes[candidates], per_class[candidates, column], 0.5)[:20]
                keep.update(candidates[kept].tolist())
        found = []
        for i in sorted(keep):
            box = boxes[i].tolist()
            if box[2] - box[0] > 4 and box[3] - box[1] > 4:
                scores = [round(v, 4) for v in per_class[i].tolist()]
                found.append([(-1, 0, 1, 2)[max(range(4), key=lambda k: scores[k])], scores, [round(v, 1) for v in box]])
        return found


class Yoloe:
    def __init__(self) -> None:
        from ultralytics import YOLOE

        self.model = YOLOE("yoloe-26l-seg.pt")
        self.prompts = [(cls, p) for cls, ps in YOLOE_PROMPTS.items() for p in ps]
        self.model.set_classes([p for _, p in self.prompts])

    def __call__(self, path: Path) -> list[list]:
        """Same shape as Owl: YOLOE only reports the winning prompt, so other classes score 0."""
        result = self.model.predict(str(path), conf=0.1, iou=0.5, verbose=False, imgsz=1024)[0]
        found = []
        for c, score, box in zip(result.boxes.cls.tolist(), result.boxes.conf.tolist(), result.boxes.xyxy.tolist()):
            cls = self.prompts[int(c)][0]
            scores = [round(score, 4) if k == cls else 0.0 for k in (-1, 0, 1, 2)]
            found.append([cls, scores, [round(v, 1) for v in box]])
        return found


# ---------------------------------------------------------------- box logic

def area(box: list[float]) -> float:
    return max(0.0, box[2] - box[0]) * max(0.0, box[3] - box[1])


def inside(small: list[float], big: list[float]) -> float:
    """Share of the small box that lies inside the big one."""
    ix = max(0, min(small[2], big[2]) - max(small[0], big[0]))
    iy = max(0, min(small[3], big[3]) - max(small[1], big[1]))
    return ix * iy / area(small) if area(small) else 0


def iou(a: list[float], b: list[float]) -> float:
    ix = max(0, min(a[2], b[2]) - max(a[0], b[0]))
    iy = max(0, min(a[3], b[3]) - max(a[1], b[1]))
    inter = ix * iy
    union = area(a) + area(b) - inter
    return inter / union if union else 0


def overlaps(a: list[float], b: list[float]) -> bool:
    return iou(a, b) >= 0.2 or inside(a, b) >= 0.5 or inside(b, a) >= 0.5


def dedupe(boxes: list[tuple]) -> list[tuple]:
    """Best score first; a box that contains a kept one and scores nearly as well replaces it,
    so a meter's enclosure wins over its dome and a panel over its breaker rows."""
    kept: list[tuple] = []
    for box in sorted(boxes, key=lambda b: -b[1]):
        clash = [i for i, k in enumerate(kept) if box[0] == k[0] and overlaps(box[2], k[2])]
        if not clash:
            kept.append(box)
        elif len(clash) == 1 and inside(kept[clash[0]][2], box[2]) >= 0.8 and box[1] >= CONTAINER_SHARE * kept[clash[0]][1]:
            kept[clash[0]] = box
    return kept


def select(detections: list, own: int, thresholds: tuple) -> tuple[str, list[tuple]]:
    """Returns (status, [(class, score, xyxy)]). own is a class id, or -1 for a negative photo.

    The photo's own class is known, so own boxes use that class's score even where another
    query scores higher (OWLv2 often calls a European gas meter an electric meter). Other
    equipment only counts where it is the winning class and clears OTHER_CONF.
    """
    own_conf, share, other_conf, neg_flag = thresholds
    score = lambda d, c: d[1][c + 1]  # noqa: E731 - scores are indexed -1, 0, 1, 2
    if own < 0:
        hits = dedupe([(d[0], score(d, d[0]), d[2]) for d in detections if d[0] >= 0 and score(d, d[0]) >= neg_flag])
        return ("flagged" if hits else "negative"), hits
    mine = [(own, score(d, own), d[2]) for d in detections if score(d, own) >= own_conf]
    if not mine:
        return "unlabeled", []
    best = max(m[1] for m in mine)
    mine = dedupe([m for m in mine if m[1] >= share * best])
    others = dedupe([(d[0], score(d, d[0]), d[2]) for d in detections
                     if d[0] >= 0 and d[0] != own and score(d, d[0]) >= other_conf
                     and not any(overlaps(d[2], m[2]) for m in mine)])
    return "labeled", mine + others


def yolo_lines(boxes: list[tuple], width: int, height: int) -> str:
    lines = []
    for cls, _, (x0, y0, x1, y1) in boxes:
        lines.append(f"{cls} {(x0 + x1) / 2 / width:.5f} {(y0 + y1) / 2 / height:.5f} "
                     f"{(x1 - x0) / width:.5f} {(y1 - y0) / height:.5f}")
    return "\n".join(lines) + ("\n" if lines else "")


# ---------------------------------------------------------------- inputs

def open_image_rows(excluded: set[str]) -> tuple[list[dict], list[dict]]:
    """All manifest rows, minus excluded stems and missing files; cross-source near-duplicates split off."""
    found = sorted(p.stem.removeprefix("manifest-") for p in DATA.glob("manifest-*.csv"))
    rows = []
    for source in [s for s in SOURCE_ORDER if s in found] + [s for s in found if s not in SOURCE_ORDER]:
        rows += list(csv.DictReader((DATA / f"manifest-{source}.csv").open()))
    kept, duplicates, hashes = [], [], []
    for row in rows:
        stem = Path(row["file"]).stem
        if stem in excluded or not (DATA / row["file"]).exists():
            continue
        phash = imagehash.hex_to_hash(row["phash"])
        if any(phash - other <= NEAR_DUPLICATE for other in hashes):
            duplicates.append(row)
            continue
        hashes.append(phash)
        kept.append(row)
    return kept, duplicates


def holdout_hashes(folder: str | None) -> list:
    if not folder:
        return []
    return [imagehash.phash(ImageOps.exif_transpose(Image.open(p)).convert("RGB"))
            for p in sorted(Path(folder).glob("*")) if p.suffix.lower() in (".jpg", ".jpeg", ".png")]


def split_by_group(items: list[dict], forced_val: set[str]) -> None:
    """Assign item['split'] so whole uploader groups land in val until each class has ~VAL_FRACTION."""
    groups: dict[str, list[dict]] = defaultdict(list)
    for item in items:
        groups[item["group"]].append(item)
    totals = Counter(item["bucket"] for item in items)
    val: Counter = Counter()

    def take(group_items: list[dict]) -> None:
        for item in group_items:
            item["split"] = "val"
            val[item["bucket"]] += 1

    for name in [g for g in groups if any(i["stem"] in forced_val for i in groups[g])]:
        take(groups.pop(name))
    for name in sorted(groups, key=lambda g: hashlib.sha1(g.encode()).hexdigest()):
        counts = Counter(item["bucket"] for item in groups[name])
        fits = all(val[k] + n <= VAL_MAX * totals[k] for k, n in counts.items())
        needed = any(val[k] < VAL_FRACTION * totals[k] for k in counts)
        if fits and needed:
            take(groups[name])
        else:
            for item in groups[name]:
                item["split"] = "train"


# ---------------------------------------------------------------- outputs

def link(src: Path, dst: Path) -> None:
    try:
        os.link(src, dst)
    except OSError:
        shutil.copy(src, dst)


def contact_sheets(items: list[dict], review: Path, name: str, per_sheet: int = 100, tile: int = 192) -> int:
    cols = 10
    for index in range(0, len(items), per_sheet):
        chunk = items[index:index + per_sheet]
        rows = (len(chunk) + cols - 1) // cols
        sheet = Image.new("RGB", (tile * cols, (tile + 14) * rows), "white")
        for n, item in enumerate(chunk):
            image = ImageOps.exif_transpose(Image.open(item["path"])).convert("RGB")
            draw = ImageDraw.Draw(image)
            width = max(3, image.width // 120)
            for cls, score, box in item["boxes"]:
                color = FLAG_COLOR if item.get("flagged") else COLORS[cls]
                draw.rectangle(box, outline=color, width=width)
                draw.rectangle([box[0], box[1], box[0] + 9 * width, box[1] + 4 * width], fill=color)
                draw.text((box[0] + width, box[1] + width), f"{'MPG'[cls]}{score:.2f}", fill="white")
            image.thumbnail((tile, tile))
            x, y = (n % cols) * tile, (n // cols) * (tile + 14)
            sheet.paste(image, (x + (tile - image.width) // 2, y + (tile - image.height) // 2))
            ImageDraw.Draw(sheet).text((x + 2, y + tile + 1), f"{item['split'][:1]} {item['stem'][:26]}", fill="black")
        sheet.save(review / f"{name}_{index // per_sheet:02d}.jpg", quality=82)
    return (len(items) + per_sheet - 1) // per_sheet


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--labeler", choices=["owlv2", "yoloe"], default="owlv2")
    parser.add_argument("--out", default=str(TRAINING / "dataset"))
    parser.add_argument("--holdout", help="folder of test photos to force into val (matched by perceptual hash)")
    parser.add_argument("--relabel", action="store_true", help="ignore cached detections")
    args = parser.parse_args()
    thresholds = THRESHOLDS[args.labeler]

    excluded: set[str] = set()
    for path in (DATA / "exclude.txt", TRAINING / "exclude.txt"):
        if path.exists():
            excluded |= set(path.read_text().split())

    # Everything to label: open images first, then drafts for unlabeled hand photos.
    rows, duplicates = open_image_rows(excluded)
    items = []
    for row in rows:
        own = CLASS_ID.get(row["class"], -1)
        items.append({"path": DATA / row["file"], "stem": Path(row["file"]).stem, "own": own, "row": row,
                      "group": row["group"] or row["source_id"], "bucket": row["class"]})
    hand = []
    for folder in HAND_LABELED:
        for path in sorted((TRAINING / folder).glob("*.jpg")):
            if path.stem in excluded:
                continue
            entry = {"path": path, "stem": f"{folder}_{path.stem}", "own": PREFIX_CLASS.get(path.stem.split("_")[0], -1),
                     "split": "val" if path.stem in VAL_STEMS else "train", "row": None, "raw_stem": path.stem}
            (hand if path.with_suffix(".txt").exists() else items).append(entry)
            if not path.with_suffix(".txt").exists():
                entry |= {"group": f"hand:{folder}", "bucket": NAMES[entry["own"]] if entry["own"] >= 0 else "negative"}

    cache_path = DATA / f"detections-{args.labeler}.json"
    cache = {} if args.relabel or not cache_path.exists() else json.loads(cache_path.read_text())
    todo = [item for item in items if str(item["path"]) not in cache]
    if todo:
        labeler = Owl() if args.labeler == "owlv2" else Yoloe()
        for n, item in enumerate(todo, 1):
            cache[str(item["path"])] = labeler(item["path"])
            if n % 100 == 0 or n == len(todo):
                print(f"{args.labeler}: {n}/{len(todo)}", flush=True)
                cache_path.write_text(json.dumps(cache))

    labels_dir = DATA / "labels"
    shutil.rmtree(labels_dir, ignore_errors=True)
    labels_dir.mkdir(parents=True)
    for item in items:
        item["status"], item["boxes"] = select(cache[str(item["path"])], item["own"], thresholds)
        # Negatives stay negatives: a water meter or junction box the labeler calls equipment is exactly
        # the hard negative the app needs. Flagged ones are listed first for a human to check.
        item["flagged"] = item["status"] == "flagged"
        if item["flagged"]:
            item["status"] = "negative"
        if item["status"] in ("labeled", "negative"):
            with Image.open(item["path"]) as image:
                size = ImageOps.exif_transpose(image).size
            item["label"] = "" if item["status"] == "negative" else yolo_lines(item["boxes"], *size)
            (labels_dir / f"{item['stem']}.txt").write_text(item["label"])

    usable = [item for item in items if item["status"] in ("labeled", "negative")]
    boxes = Counter(NAMES[b[0]] for i in usable if i["status"] == "labeled" for b in i["boxes"])
    forced = set()
    holdout = holdout_hashes(args.holdout)
    if holdout:
        for item in usable:
            if item["row"] and any(imagehash.hex_to_hash(item["row"]["phash"]) - h <= NEAR_DUPLICATE for h in holdout):
                forced.add(item["stem"])
    split_by_group([i for i in usable if i["row"]], forced)
    for item in items:
        item.setdefault("split", "")

    # Dataset folders.
    out = Path(args.out)
    shutil.rmtree(out, ignore_errors=True)
    for split in ("train", "val"):
        (out / "images" / split).mkdir(parents=True)
        (out / "labels" / split).mkdir(parents=True)
    for item in usable:
        link(item["path"], out / "images" / item["split"] / f"{item['stem']}.jpg")
        (out / "labels" / item["split"] / f"{item['stem']}.txt").write_text(item["label"])
    for item in hand:
        sidecar = item["path"].with_suffix(".txt")
        for copy in range(1 if item["split"] == "val" else HAND_REPEAT):
            stem = f"{item['stem']}_{copy}"
            shutil.copy(item["path"], out / "images" / item["split"] / f"{stem}.jpg")
            shutil.copy(sidecar, out / "labels" / item["split"] / f"{stem}.txt")
    (out / "data.yaml").write_text(f"path: {out}\ntrain: images/train\nval: images/val\nnames:\n"
                                   + "".join(f"  {i}: {n}\n" for i, n in enumerate(NAMES)))

    # Review sheets and lists.
    review = DATA / "review"
    shutil.rmtree(review, ignore_errors=True)
    review.mkdir(parents=True)
    sheets = 0
    for name in POSITIVE:
        labeled = [i for i in items if i["bucket"] == name and i["status"] == "labeled"]
        labeled.sort(key=lambda i: max(b[1] for b in i["boxes"] if b[0] == i["own"]))  # doubtful first
        sheets += contact_sheets(labeled, review, name)
        missed = [i for i in items if i["bucket"] == name and i["status"] == "unlabeled"]
        sheets += contact_sheets(missed, review, f"{name}_unlabeled")
    negatives = [i for i in items if i["status"] == "negative" and not i["flagged"]]
    sheets += contact_sheets(negatives, review, "negative")
    flagged = sorted([i for i in items if i["flagged"]], key=lambda i: -max(b[1] for b in i["boxes"]))
    sheets += contact_sheets(flagged, review, "negative_flagged")
    (review / "unlabeled.txt").write_text("".join(f"{i['stem']}\t{i['bucket']}\n" for i in items if i["status"] == "unlabeled"))
    (review / "negatives_flagged.txt").write_text("".join(
        f"{i['stem']}\t{i['row']['subclass'] if i['row'] else ''}\t{max(b[1] for b in i['boxes']):.2f}\n" for i in flagged))

    # Committed attribution manifest.
    manifest_path = REPO / "dataset" / "open-images-manifest.csv"
    manifest_path.parent.mkdir(exist_ok=True)
    columns = ["file", "class", "subclass", "split", "status", "boxes"] + [f for f in FIELDS if f not in
                                                                           ("file", "class", "subclass", "phash", "fetched_at")]
    with manifest_path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        for item in sorted((i for i in items if i["row"]), key=lambda i: i["row"]["file"]):
            status = "negative_flagged" if item.get("flagged") else item["status"]
            count = 0 if item["status"] == "negative" else len(item["boxes"])
            writer.writerow(item["row"] | {"split": item["split"], "status": status, "boxes": count})
        for row in duplicates:
            writer.writerow(row | {"split": "", "status": "cross_source_duplicate", "boxes": 0})

    # Summary.
    table = Counter((i["bucket"], i["status"], i["split"]) for i in items)
    for bucket in POSITIVE + ["negative"]:
        parts = {s: sum(n for (b, st, _), n in table.items() if b == bucket and st == s)
                 for s in ("labeled", "negative", "unlabeled")}
        parts["flagged"] = sum(1 for i in items if i["bucket"] == bucket and i.get("flagged"))
        splits = {s: sum(n for (b, st, sp), n in table.items() if b == bucket and sp == s) for s in ("train", "val")}
        print(f"{bucket:15s} {parts}  {splits}")
    print(f"boxes {dict(boxes)}; hand-labeled {len(hand)}; cross-source duplicates {len(duplicates)}; "
          f"forced to val {len(forced)}; {sheets} sheets in {review}; dataset {out}")


if __name__ == "__main__":
    main()
