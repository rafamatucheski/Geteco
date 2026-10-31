"""Inspeciona uma sequência limitada de JPEGs do fliperama; são tempos de captura, nunca FPS.

Uso: python tools/analyze_arcade_temporal.py evidence/arcade-temporal-...
As saídas ficam ao lado da gravação fornecida. Nenhum motor ou save é tocado.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

# Em 960x540 estes recortes excluem HUD, personagens, telas dos gabinetes e a rota.
# Confira o posicionamento em temporal-contact-sheet.jpg a cada gravação nova.
REGIONS = {
    "back_wall_above_cabinets": (281, 89, 679, 109),
    "back_wall_between_cabinets": (452, 117, 501, 164),
    "left_wood_furniture": (278, 253, 300, 317),
    "floor_left_outside_route": (338, 228, 353, 318),
    "floor_bottom_left": (351, 384, 429, 411),
    "floor_bottom_right": (550, 384, 614, 411),
}
MOTION_DIAGNOSTIC = {"excluded_player_leg_edge": (345, 228, 371, 368)}


def load_rgb(folder: Path, index: int) -> Image.Image:
    return Image.open(folder / f"frame-{index:06d}.jpg").convert("RGB")


def summarize(values: np.ndarray) -> dict:
    return {
        "min": round(float(np.min(values)), 6),
        "median": round(float(np.median(values)), 6),
        "p95": round(float(np.percentile(values, 95)), 6),
        "p99": round(float(np.percentile(values, 99)), 6),
        "max": round(float(np.max(values)), 6),
    }


def annotate(image: Image.Image, label: str, boxes: bool = False) -> Image.Image:
    result = image.copy()
    draw = ImageDraw.Draw(result)
    if boxes:
        for number, box in enumerate(REGIONS.values(), 1):
            draw.rectangle(box, outline=(110, 248, 186), width=2)
            draw.text((box[0] + 2, box[1] + 2), str(number), fill=(255, 245, 170))
    draw.rectangle((0, 0, result.width, 21), fill=(11, 17, 28))
    draw.text((7, 5), label, fill=(234, 240, 249))
    return result.resize((480, 270), Image.Resampling.LANCZOS)


def run(folder: Path, stage: str) -> None:
    metadata = json.loads((folder / "frames.json").read_text(encoding="utf-8-sig"))
    frames = metadata["frames"]
    seconds = np.array([frame["seconds"] for frame in frames], dtype=np.float64)
    engine_frames = np.array([frame["drawn"] for frame in frames], dtype=np.int64)
    indices = np.array([frame["index"] for frame in frames], dtype=np.int64)
    intervals = np.diff(seconds)
    missing = [int(i) for i in indices if not (folder / f"frame-{i:06d}.jpg").is_file()]
    if missing:
        raise ValueError(f"Missing JPEG files: {missing[:12]}")
    count = len(frames)
    measured_regions = {**REGIONS, **MOTION_DIAGNOSTIC}
    names = list(measured_regions)
    luminance = np.empty((count, len(names)), dtype=np.float64)
    pair_mean = np.zeros((count, len(names)), dtype=np.float64)
    pair_p99 = np.zeros_like(pair_mean)
    pair_changed = np.zeros_like(pair_mean)
    previous: dict[str, np.ndarray] = {}
    pixel_low: dict[str, np.ndarray] = {}
    pixel_high: dict[str, np.ndarray] = {}
    for row, frame in enumerate(frames):
        image = load_rgb(folder, frame["index"])
        if image.size != (960, 540):
            raise ValueError(f"ROI layout requires 960x540, got {image.size}")
        for column, (name, box) in enumerate(measured_regions.items()):
            rgb = np.asarray(image.crop(box), dtype=np.float32)
            gray = rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
            luminance[row, column] = float(gray.mean())
            if row:
                delta = np.abs(gray - previous[name])
                pair_mean[row, column] = float(delta.mean())
                pair_p99[row, column] = float(np.percentile(delta, 99))
                pair_changed[row, column] = float(np.mean(delta > 12.0))
                pixel_low[name] = np.minimum(pixel_low[name], gray)
                pixel_high[name] = np.maximum(pixel_high[name], gray)
            else:
                pixel_low[name] = gray.copy()
                pixel_high[name] = gray.copy()
            previous[name] = gray

    # Os limiares indicam candidatos para inspeção; não diagnosticam cintilação.
    mean_jumps = np.abs(np.diff(luminance, axis=0, prepend=luminance[:1]))
    static_columns = len(REGIONS)
    candidate_mask = np.any((mean_jumps[:, :static_columns] > 2.0) | (pair_changed[:, :static_columns] > 0.02), axis=1)
    candidate_rows = np.flatnonzero(candidate_mask)
    severity = np.max((mean_jumps + pair_changed * 100)[:, :static_columns], axis=1)
    ordered_rows = np.argsort(severity[1:])[::-1][:8] + 1
    regions = {}
    for column, name in enumerate(names):
        worst = int(np.argmax(mean_jumps[:, column]))
        regions[name] = {
            "roi_xyxy": list(measured_regions[name]),
            "eligible_static_region": name in REGIONS,
            "mean_luminance_0_255": summarize(luminance[:, column]),
            "adjacent_abs_mean_luminance_jump": summarize(mean_jumps[1:, column]),
            "adjacent_mean_abs_pixel_difference": summarize(pair_mean[1:, column]),
            "adjacent_p99_abs_pixel_difference": summarize(pair_p99[1:, column]),
            "largest_fraction_pixels_changing_gt12": round(float(np.max(pair_changed[:, column])), 6),
            "whole_sequence_per_pixel_range": summarize(pixel_high[name] - pixel_low[name]),
            "worst_mean_jump_pair": [max(0, worst - 1), worst],
            "worst_mean_jump_seconds": round(float(seconds[worst]), 6),
            "static_phase_max_mean_jump": round(float(np.max(mean_jumps[seconds <= 15, column])), 6),
            "walking_phase_max_mean_jump": round(float(np.max(mean_jumps[seconds > 15, column])), 6),
        }

    targets = [0, 5, 10, 14.9, 15.8, 20, 25, 30.9]
    sample_rows = [int(np.argmin(np.abs(seconds - time))) for time in targets]
    sheet = Image.new("RGB", (1920, 540), (11, 17, 28))
    for cell, row in enumerate(sample_rows):
        frame = frames[row]
        tile = annotate(load_rgb(folder, frame["index"]), f"{seconds[row]:.3f}s | index {row} | drawn {frame['drawn']}", boxes=True)
        sheet.paste(tile, ((cell % 4) * 480, (cell // 4) * 270))
    sheet.save(folder / "temporal-contact-sheet.jpg", quality=95)

    pairs_sheet = Image.new("RGB", (1440, len(ordered_rows) * 270), (11, 17, 28))
    ranked_pairs = []
    for cell, row in enumerate(ordered_rows):
        row = int(row)
        before = load_rgb(folder, frames[row - 1]["index"])
        after = load_rgb(folder, frames[row]["index"])
        delta = np.abs(np.asarray(after, dtype=np.int16) - np.asarray(before, dtype=np.int16))
        difference = Image.fromarray(np.clip(delta * 6, 0, 255).astype(np.uint8))
        for col, (im, label) in enumerate([(before, f"Before {seconds[row - 1]:.3f}s / {row - 1}"), (after, f"After {seconds[row]:.3f}s / {row}"), (difference, "Absolute RGB difference x6; movement is expected")]):
            pairs_sheet.paste(annotate(im, label, boxes=col != 2), (col * 480, cell * 270))
        ranked_pairs.append({"indices": [row - 1, row], "seconds": [round(float(seconds[row - 1]), 6), round(float(seconds[row]), 6)], "max_roi_mean_jump": round(float(np.max(mean_jumps[row, :static_columns])), 6), "max_roi_changed_fraction_gt12": round(float(np.max(pair_changed[row, :static_columns])), 6), "above_candidate_threshold": bool(candidate_mask[row])})
    pairs_sheet.save(folder / "temporal-ranked-pairs.jpg", quality=94)

    report = {
        "recording": str(folder),
        "scope": "Night arcade interior, 15 s stationary + approximately 16 s walking; native Main capture.",
        "review_stage": stage,
        "engine": metadata.get("engine"),
        "renderer": metadata.get("renderer"),
        "native_resolution": metadata.get("native_resolution"),
        "capture_resolution": metadata.get("capture_resolution"),
        "night": metadata.get("night"),
        "continuity": {
            "metadata_frames": count,
            "jpeg_files": len(list(folder.glob("frame-*.jpg"))),
            "missing_files": missing,
            "index_start_end": [int(indices[0]), int(indices[-1])],
            "indices_sequential": bool(np.all(np.diff(indices) == 1)),
            "engine_drawn_start_end": [int(engine_frames[0]), int(engine_frames[-1])],
            "engine_drawn_deltas": {str(int(value)): int(np.sum(np.diff(engine_frames) == value)) for value in np.unique(np.diff(engine_frames))},
            "timestamps_strictly_increasing": bool(np.all(intervals > 0)),
            "seconds_start_end": [round(float(seconds[0]), 6), round(float(seconds[-1]), 6)],
            "capture_interval_ms_not_frame_time": summarize(intervals * 1000),
            "stationary_frame_count": int(np.sum(seconds <= 15)),
            "walking_frame_count": int(np.sum(seconds > 15)),
        },
        "regions": regions,
        "candidate_rule": "Inspect adjacent ROI mean-luma jump >2/255 or >2% of ROI pixels changing >12/255. Not an automatic flicker verdict.",
        "candidate_pair_count": int(len(candidate_rows)),
        "candidate_pair_indices": candidate_rows.tolist()[:30],
        "roi_review": "ROI layout was calibrated on preliminary arcade-temporal-190500-6357159: the initial floor crop x345..371 included Dante's swinging leg at 25.92..25.97 s (pairs 1199/1200 and 1200/1201), confirmed by original JPEGs. That wider crop is retained as excluded_player_leg_edge diagnostic, excluded from static-light decisions; the static floor crop uses x338..353, y228..318. Candidate thresholds are unchanged. Check marked crops again on each recording.",
        "ranked_pairs": ranked_pairs,
        "limits": ["JPEG/downsample can conceal subpixel and low-amplitude flicker.", "Only the six explicitly marked stationary crops receive static-light pixel statistics; character motion and emissive screens are excluded.", "Movement and shadows in the remaining room require visual review of contact sheet/pair images.", "No exterior, daylight, weather transition, entry/exit or streaming coverage in this sequence.", "Recording readback/JPEG overhead invalidates use of these intervals as runtime FPS or frame-time evidence."] + (["Preliminary recording predates the final two-light energy/attenuation adjustment; rerun this analyzer on the replacement recording."] if stage == "preliminary" else []),
    }
    (folder / "temporal-analysis.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"frames": count, "engine_deltas": report["continuity"]["engine_drawn_deltas"], "seconds": report["continuity"]["seconds_start_end"], "candidate_pairs": int(len(candidate_rows)), "worst_roi_mean_jump": round(float(np.max(mean_jumps[:, :static_columns])), 6), "report": str(folder / "temporal-analysis.json")}, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("recording", type=Path)
    parser.add_argument("--stage", choices=["preliminary", "final"], default="preliminary")
    arguments = parser.parse_args()
    run(arguments.recording.resolve(), arguments.stage)
