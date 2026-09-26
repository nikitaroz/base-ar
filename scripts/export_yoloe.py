#!/usr/bin/env python3
"""Bake YOLOE text prompts into a Core ML package for the BaseAR target.

Ultralytics is an export-time dependency only. The app loads the package with
Vision and Core ML and cannot change the prompts later.

The smallest current text-prompt checkpoint is yoloe-26n-seg.pt (YOLOE-26 nano).
set_classes folds "electric meter" and "breaker panel" into the weights, then
the mask branch is dropped so the package is a box detector.
"""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

PROMPTS = ["electric meter", "breaker panel"]
CHECKPOINT = "yoloe-26n-seg.pt"
PACKAGE_NAME = "EquipmentScan.mlpackage"


def _patch_coreml_scalar_cast() -> None:
    """coremltools 9 + NumPy 2 rejects one-element arrays in int()/bool() casts."""
    import numpy as np
    from coremltools.converters.mil import Builder as mb
    from coremltools.converters.mil.frontend.torch import ops as torch_ops

    original = torch_ops._cast

    def _cast(context, node, dtype, dtype_name):
        inputs = torch_ops._get_inputs(context, node, expected=1)
        value = inputs[0]
        if value.can_be_folded_to_const() and not isinstance(value.val, dtype):
            scalar = value.val
            if isinstance(scalar, np.ndarray):
                scalar = scalar.reshape(-1)[0].item()
            context.add(mb.const(val=dtype(scalar), name=node.name), node.name)
            return
        original(context, node, dtype, dtype_name)

    torch_ops._cast = _cast


def main() -> None:
    _patch_coreml_scalar_cast()
    from ultralytics import YOLOE

    root = Path(__file__).resolve().parents[1]
    destination = root / "BaseAR" / "Placement" / PACKAGE_NAME

    prompted = YOLOE(CHECKPOINT)
    prompted.set_classes(PROMPTS)

    profile = Path("equipment-prompts.npz")
    exported: Path | None = None
    try:
        prompted.save_prompt_embeddings(str(profile))
        detector = YOLOE("yoloe-26n.yaml")
        detector.load(CHECKPOINT)
        detector.load_prompt_embeddings(str(profile))
        exported = Path(detector.export(format="coreml", nms=True, imgsz=320))
    except Exception as error:  # noqa: BLE001 - fall back to the segmentation package
        print(f"detection-only export failed ({error}); exporting the prompted segmentation model", file=sys.stderr)
        exported = Path(prompted.export(format="coreml", nms=True, imgsz=320))

    if exported.suffix != ".mlpackage":
        raise SystemExit(f"expected an mlpackage, got {exported}")

    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(exported, destination)
    megabytes = sum(path.stat().st_size for path in destination.rglob("*") if path.is_file()) / 1_000_000
    print(f"wrote {destination} ({megabytes:.1f} MB)")


if __name__ == "__main__":
    main()
