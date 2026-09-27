#!/usr/bin/env python3
"""Fine-tune a small YOLO detector on training/dataset and replace EquipmentScan.mlpackage.

Run scripts/autolabel.py first and review training/review/ before training.
Run with training/.venv/bin/python. Pass --no-export to train without touching the app.

Class 0 is electric_meter and class 1 is breaker_panel, which is what
YOLOEEquipmentDetector.kind(for:) and kind(at:) already expect.
"""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "training" / "dataset" / "data.yaml"
RUNS = ROOT / "training" / "runs"
BASE = "yolo26s.pt"
IMGSZ = 640
DESTINATION = ROOT / "BaseAR" / "Placement" / "EquipmentScan.mlpackage"


def main() -> None:
    from ultralytics import YOLO

    model = YOLO(BASE)
    model.train(
        data=str(DATA),
        imgsz=IMGSZ,
        epochs=80,
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
    metrics = trained.val(data=str(DATA), imgsz=IMGSZ, device="mps")
    print(f"mAP50 {metrics.box.map50:.3f}  mAP50-95 {metrics.box.map:.3f}")

    if "--no-export" in sys.argv:
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
