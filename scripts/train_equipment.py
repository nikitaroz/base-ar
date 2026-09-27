#!/usr/bin/env python3
"""Fine-tune a small YOLO detector on training/dataset and replace EquipmentScan.mlpackage.

Run scripts/autolabel.py (training/review/) or scripts/photoset/autolabel.py (contact sheets)
first and review its drafts before training.
Run with the training venv. Pass --no-export to train without touching the app.

Class 0 is electric_meter and class 1 is breaker_panel, which is what
EquipmentDetecting's kind(for:) and kind(at:) already expect. Class 2 (gas_meter)
is ignored by the app until kind(at:) maps it.

Example: python scripts/train_equipment.py --data ~/base-ar-data/open-images/dataset/data.yaml --no-export
"""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "training" / "dataset" / "data.yaml"
RUNS = ROOT / "training" / "runs"
BASE = "yolo26s.pt"  # about 3x yolo26n's compute, still far inside the app's 250 ms budget
IMGSZ = 640
DESTINATION = ROOT / "BaseAR" / "Placement" / "EquipmentScan.mlpackage"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", default=str(DATA))
    parser.add_argument("--model", default=BASE)
    parser.add_argument("--epochs", type=int, default=100)
    parser.add_argument("--no-export", action="store_true")
    args = parser.parse_args()
    from ultralytics import YOLO

    model = YOLO(args.model)
    model.train(
        data=args.data,
        imgsz=IMGSZ,
        epochs=args.epochs,
        patience=20,
        batch=16,
        device="mps",
        project=str(RUNS),
        name="equipment",
        exist_ok=True,
        # Phones tilt and outdoor light varies; flips are fine for both classes.
        degrees=10,
        # Strong zoom-out so panels 10+ ft away still look familiar next to the negatives.
        scale=0.9,
        fliplr=0.5,
        hsv_v=0.5,
        plots=True,
    )
    best = RUNS / "equipment" / "weights" / "best.pt"
    trained = YOLO(str(best))
    metrics = trained.val(data=args.data, imgsz=IMGSZ, device="mps")
    print(f"mAP50 {metrics.box.map50:.3f}  mAP50-95 {metrics.box.map:.3f}")
    for row, index in enumerate(metrics.box.ap_class_index):
        print(f"  {trained.names[int(index)]}: AP50 {metrics.box.ap50[row]:.3f}")

    if args.no_export:
        return
    sys.path.insert(0, str(Path(__file__).parent))
    from export_yoloe import _patch_coreml_scalar_cast

    _patch_coreml_scalar_cast()
    exported = Path(trained.export(format="coreml", nms=True, imgsz=IMGSZ, half=True))
    if DESTINATION.exists():
        shutil.rmtree(DESTINATION)
    shutil.copytree(exported, DESTINATION)
    megabytes = sum(p.stat().st_size for p in DESTINATION.rglob("*") if p.is_file()) / 1_000_000
    print(f"wrote {DESTINATION} ({megabytes:.1f} MB)")


if __name__ == "__main__":
    main()
