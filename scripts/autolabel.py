#!/usr/bin/env python3
"""Draft YOLO labels for training/raw with a large YOLOE model, for a human to review.

raw/meter/ (Commons) and openverse/{meter,panel}/ are auto-labeled. Commons panels are
European switchboards and hurt more than they help, so they are skipped. Hand-labeled photos (a .txt sidecar next to the image, in training/site/
and training/reference/) are copied as-is and repeated so they outweigh Commons.
training/negatives/ holds photos with no meter or panel and empty labels, so the model
learns to stay quiet on disconnects, batteries, and other gray boxes.
Stems listed in training/exclude.txt (one per line) are skipped after human review.

Writes training/dataset/{images,labels}/{train,val} and training/review/*.jpg
contact sheets with the drafted boxes drawn. Images with no box for their folder's
class go to training/review/unlabeled.txt instead of the dataset.

Run with training/.venv/bin/python.
"""

from __future__ import annotations

import random
import shutil
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1] / "training"
CHECKPOINT = "yoloe-26l-seg.pt"
CLASSES = ["electric meter", "breaker panel"]
# Several phrasings per class; each index maps back to a class id.
PROMPTS = {
    "electric meter": 0, "electricity meter": 0, "utility meter": 0, "smart meter": 0, "watt-hour meter": 0,
    "breaker panel": 1, "electrical panel": 1, "breaker box": 1, "circuit breaker panel": 1,
    "load center": 1, "fuse box": 1, "distribution board": 1,
}
FOLDER_CLASS = {"meter": 0, "panel": 1}
# (folder, kind) pairs drafted by the models. Commons panels are skipped: European switchboards.
AUTO_SOURCES = [("raw", "meter"), ("openverse", "meter")]
OWN_CONF = 0.3
# The last fine-tuned model knows US equipment on siding; YOLOE knows the wider world. Both draft boxes.
DOMAIN_CHECKPOINT = ROOT / "best_v3.pt"
DOMAIN_CONF = 0.4
VAL_FRACTION = 0.15
# openverse_hand/ holds Openverse panels labeled by hand; drafted panel boxes were too unreliable.
HAND_LABELED = ["site", "reference", "negatives", "openverse_hand"]
# Held-out site photos, so validation measures the real target look.
VAL_STEMS = {"meter_IMG_5092", "meter_IMG_5094", "panel_IMG_5084", "panel_IMG_5096",
             "neg_IMG_5110", "neg_IMG_5113", "neg_IMG_5116"}
HAND_REPEAT = 3
COLORS = ["#2f9e44", "#e8590c"]


def main() -> None:
    from ultralytics import YOLOE

    from ultralytics import YOLO

    model = YOLOE(CHECKPOINT)
    names = list(PROMPTS)
    model.set_classes(names)
    domain = YOLO(str(DOMAIN_CHECKPOINT)) if DOMAIN_CHECKPOINT.exists() else None

    dataset, review = ROOT / "dataset", ROOT / "review"
    for folder in (dataset, review):
        shutil.rmtree(folder, ignore_errors=True)
    for split in ("train", "val"):
        (dataset / "images" / split).mkdir(parents=True)
        (dataset / "labels" / split).mkdir(parents=True)
    review.mkdir()

    excluded = set((ROOT / "exclude.txt").read_text().split()) if (ROOT / "exclude.txt").exists() else set()
    images = [(p, FOLDER_CLASS[kind]) for source, kind in AUTO_SOURCES for p in sorted((ROOT / source / kind).glob("*.jpg"))
              if p.stem not in excluded]
    images += [(p, FOLDER_CLASS.get(p.stem.split("_")[0], -1)) for folder in HAND_LABELED for p in sorted((ROOT / folder).glob("*.jpg"))]
    random.seed(7)
    unlabeled, drawn = [], []

    for path, own in images:
        # A hand-written sidecar label wins over the model.
        sidecar = path.with_suffix(".txt")
        if sidecar.exists():
            split = "val" if path.stem in VAL_STEMS else "train"
            for copy in range(1 if split == "val" else HAND_REPEAT):
                stem = f"{path.parent.name}_{path.stem}_{copy}"
                shutil.copy(path, dataset / "images" / split / f"{stem}.jpg")
                shutil.copy(sidecar, dataset / "labels" / split / f"{stem}.txt")
            continue
        result = model.predict(str(path), conf=OWN_CONF, iou=0.5, verbose=False, imgsz=1024)[0]
        lines, boxes = [], []
        found = zip(result.boxes.xywhn.tolist(), result.boxes.xyxy.tolist(), result.boxes.cls.tolist(), result.boxes.conf.tolist())
        for xywhn, xyxy, prompt, score in found:
            cls = PROMPTS[names[int(prompt)]]
            if cls != own:
                continue
            lines.append(f"{cls} {' '.join(f'{v:.5f}' for v in xywhn)}")
            boxes.append((cls, score, xyxy))
        if domain is not None:
            extra = domain.predict(str(path), conf=DOMAIN_CONF, verbose=False, imgsz=640)[0]
            found = zip(extra.boxes.xywhn.tolist(), extra.boxes.xyxy.tolist(), extra.boxes.cls.tolist(), extra.boxes.conf.tolist())
            for xywhn, xyxy, cls, score in found:
                if int(cls) != own:
                    continue
                lines.append(f"{own} {' '.join(f'{v:.5f}' for v in xywhn)}")
                boxes.append((own, score, xyxy))
        # Drop duplicate boxes from different phrasings and from the two models.
        lines, boxes = dedupe(lines, boxes)

        if not any(cls == own for cls, _, _ in boxes):
            unlabeled.append(str(path.relative_to(ROOT)))
            continue
        split = "val" if random.random() < VAL_FRACTION else "train"
        stem = f"{path.parent.parent.name}_{path.stem}"
        shutil.copy(path, dataset / "images" / split / f"{stem}.jpg")
        (dataset / "labels" / split / f"{stem}.txt").write_text("\n".join(lines) + "\n")
        drawn.append((path, boxes, stem))

    (dataset / "data.yaml").write_text(
        f"path: {dataset}\ntrain: images/train\nval: images/val\nnames:\n  0: electric_meter\n  1: breaker_panel\n"
    )
    (review / "unlabeled.txt").write_text("\n".join(unlabeled) + "\n")
    contact_sheets(drawn, review)
    print(f"labeled {len(drawn)}, unlabeled {len(unlabeled)}; sheets in {review}")


def dedupe(lines: list[str], boxes: list[tuple]) -> tuple[list[str], list[tuple]]:
    """Largest box first, so a meter's enclosure wins over its glass dome and display."""
    order = sorted(range(len(boxes)), key=lambda i: -area(boxes[i][2]))
    kept: list[int] = []
    for i in order:
        # Any real overlap with a kept box of the same class is a second guess at the same meter.
        if all(boxes[i][0] != boxes[j][0] or (iou(boxes[i][2], boxes[j][2]) < 0.2 and inside(boxes[i][2], boxes[j][2]) < 0.5)
               for j in kept):
            kept.append(i)
    return [lines[i] for i in kept], [boxes[i] for i in kept]


def area(box: list[float]) -> float:
    return (box[2] - box[0]) * (box[3] - box[1])


def inside(small: list[float], big: list[float]) -> float:
    """Share of the small box that lies inside the big one."""
    ix = max(0, min(small[2], big[2]) - max(small[0], big[0]))
    iy = max(0, min(small[3], big[3]) - max(small[1], big[1]))
    return ix * iy / area(small) if area(small) else 0


def iou(a: list[float], b: list[float]) -> float:
    ix = max(0, min(a[2], b[2]) - max(a[0], b[0]))
    iy = max(0, min(a[3], b[3]) - max(a[1], b[1]))
    inter = ix * iy
    union = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter
    return inter / union if union else 0


def contact_sheets(drawn: list[tuple], review: Path, per_sheet: int = 20, tile: int = 320) -> None:
    for sheet_index in range(0, len(drawn), per_sheet):
        chunk = drawn[sheet_index:sheet_index + per_sheet]
        sheet = Image.new("RGB", (tile * 5, (tile + 18) * ((len(chunk) + 4) // 5)), "white")
        for n, (path, boxes, stem) in enumerate(chunk):
            image = Image.open(path).convert("RGB")
            draw = ImageDraw.Draw(image)
            width = max(3, image.width // 200)
            for cls, score, xyxy in boxes:
                draw.rectangle(xyxy, outline=COLORS[cls], width=width)
                draw.text((xyxy[0] + width, xyxy[1] + width), f"{'MP'[cls]} {score:.2f}", fill=COLORS[cls])
            image.thumbnail((tile, tile))
            x, y = (n % 5) * tile, (n // 5) * (tile + 18)
            sheet.paste(image, (x, y))
            ImageDraw.Draw(sheet).text((x + 2, y + tile + 2), stem, fill="black")
        sheet.save(review / f"sheet_{sheet_index // per_sheet:02d}.jpg", quality=85)


if __name__ == "__main__":
    main()
