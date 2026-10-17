"""Validate the offline engine-design pack, never audio realism or game performance.

Usage: python tools/audio/validate_engine_design_pack.py --pack audio/engine_design
       --report artifacts/engine-sound-design-20261016/validation.json

The manifest paths are relative to the pack directory. Every profile supplies
seven loaded and seven coast bands in increasing RPM order. Engine loops at or
below 1500 RPM last six seconds; higher bands last two seconds. All loops use
mono PCM16 at 22050 Hz and eight repeated guard frames. Turbo profiles supply a
spool loop; petrol turbos also supply a 0.68-second non-looping bypass release.
Every referenced WAV must match its manifest SHA256. Optional --baseline checks
the original four profiles' high bands and effects against their actual files.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys
import wave

import numpy as np


SAMPLE_RATE = 22050
USEFUL_FRAMES = 44100
LOW_RPM_FRAMES = 132300
LOW_RPM_LIMIT = 1500
GUARD_FRAMES = 8
BAND_COUNT = 7
RELEASE_FRAMES = 14994  # Exactly 0.68 seconds at 22050 Hz.
EXPECTED_PROFILES = {
    "jz2_i6_turbo": 6,
    "rb26_i6_turbo": 6,
    "v8_crossplane": 8,
    "v12_gt": 12,
    "ap_i4_turbo": 4,
    "ea888_i4_turbo": 4,
    "vq35_v6_na": 6,
    "tdi_i4_diesel": 4,
    "city_i4_na": 4,
    "v8_twin_turbo": 8,
    "truck_i6_diesel": 6,
    "bus_i6_diesel": 6,
    "work_i4_diesel": 4,
    "truck_v12_diesel": 12,
    "utility_v6_na": 6,
    "sport_i4_na": 4,
    "classic_i4_na": 4,
}
ORIGINAL_PROFILES = ("jz2_i6_turbo", "rb26_i6_turbo", "v8_crossplane", "v12_gt")
PETROL_TURBOS = {"jz2_i6_turbo", "rb26_i6_turbo", "ap_i4_turbo", "ea888_i4_turbo", "v8_twin_turbo"}
DIESEL_PROFILES = {"tdi_i4_diesel", "truck_i6_diesel", "bus_i6_diesel", "work_i4_diesel", "truck_v12_diesel"}
TURBO_PROFILES = PETROL_TURBOS | DIESEL_PROFILES


def is_number(value: object) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def inspect_wav(path: Path, label: str, errors: list[str], looped: bool = True,
                useful_frames: int | None = None) -> dict:
    if useful_frames is None:
        useful_frames = USEFUL_FRAMES if looped else RELEASE_FRAMES
    guard_frames = GUARD_FRAMES if looped else 0
    result: dict = {"path": label, "loop": looped, "valid": False}
    before = len(errors)
    try:
        with wave.open(str(path), "rb") as source:
            channels = source.getnchannels()
            width = source.getsampwidth()
            rate = source.getframerate()
            frames = source.getnframes()
            compression = source.getcomptype()
            raw = source.readframes(frames)
    except (OSError, EOFError, wave.Error) as exc:
        errors.append(f"{label}: cannot read WAV: {exc}")
        return result

    result.update({
        "channels": channels,
        "sample_width_bytes": width,
        "sample_rate": rate,
        "frames": frames,
        "compression": compression,
    })
    if channels != 1 or width != 2 or compression != "NONE":
        errors.append(f"{label}: expected mono uncompressed PCM16")
    if rate != SAMPLE_RATE:
        errors.append(f"{label}: expected {SAMPLE_RATE} Hz, got {rate}")
    if frames != useful_frames + guard_frames:
        errors.append(f"{label}: expected {useful_frames} useful + {guard_frames} guard frames, got {frames}")
    if len(raw) != frames * channels * width:
        errors.append(f"{label}: truncated PCM data")
    # Decode only after validating the representation and expected length.
    if len(errors) != before:
        return result

    pcm = np.frombuffer(raw, dtype="<i2")
    guard_matches = bool(np.array_equal(pcm[-guard_frames:], pcm[:guard_frames])) if looped else None
    endpoints_zero = bool(pcm[0] == 0 and pcm[-1] == 0)
    body = pcm[:useful_frames].astype(np.float64) / 32768.0
    natural_steps = np.abs(np.diff(body))
    dc = float(np.mean(body))
    rms = float(np.sqrt(np.mean(body * body)))
    peak = float(np.max(np.abs(body)))
    seam_step = float(abs(body[0] - body[-1]))
    natural_max = float(np.max(natural_steps))
    # A normal waveform may cross the loop boundary with nonzero slope. Permit
    # the same local movement seen inside the loop, plus a fixed 25% margin and
    # two PCM quantization units. This only rejects an anomalous amplitude jump;
    # it does not prove that the repeated sound is perceptually seamless.
    seam_limit = natural_max * 1.25 + 2.0 / 32768.0
    result.update({
        "guard_matches": guard_matches,
        "endpoints_zero": endpoints_zero,
        "dc": dc,
        "rms": rms,
        "peak": peak,
        "seam_step": seam_step,
        "natural_step_p99": float(np.percentile(natural_steps, 99.0)),
        "natural_step_max": natural_max,
        "seam_step_limit": seam_limit,
    })
    if looped and not guard_matches:
        errors.append(f"{label}: guard frames differ from the first eight PCM samples")
    if not looped and not endpoints_zero:
        errors.append(f"{label}: non-looping release must begin and end at zero PCM")
    if abs(dc) >= 0.001:
        errors.append(f"{label}: absolute DC {abs(dc):.6f} must be below 0.001")
    if peak >= 0.98:
        errors.append(f"{label}: peak {peak:.6f} must be below 0.98")
    if rms <= 0.01:
        errors.append(f"{label}: RMS {rms:.6f} must exceed 0.01")
    if looped and seam_step > seam_limit:
        errors.append(f"{label}: circular step {seam_step:.6f} exceeds natural-step limit {seam_limit:.6f}")
    result["valid"] = len(errors) == before
    return result


def compare_baseline(pack: Path, baseline: Path, manifest: dict, errors: list[str]) -> dict:
    """Compare actual WAV bytes, including the baseline manifest's integrity."""
    baseline = baseline.resolve()
    comparison: dict = {
        "pack": str(baseline), "preserve_above_rpm": LOW_RPM_LIMIT,
        "expected_engine_bands": 40, "expected_effects": 4,
        "engine_bands": 0, "effects": 0, "files": [], "valid": False,
    }
    before = len(errors)
    try:
        previous = json.loads((baseline / "manifest.json").read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        errors.append(f"baseline: cannot read manifest: {exc}")
        return comparison
    if not isinstance(previous, dict) or not isinstance(previous.get("profiles"), list):
        errors.append("baseline: expected an object with a profiles array")
        return comparison
    old_profiles = {p.get("id"): p for p in previous["profiles"] if isinstance(p, dict) and isinstance(p.get("id"), str)}
    new_profiles = {p.get("id"): p for p in manifest["profiles"] if isinstance(p, dict) and isinstance(p.get("id"), str)}

    def compare_file(profile_id: str, kind: str, old_relative: object,
                     new_relative: object, expected_hash: object) -> None:
        label = f"baseline.{profile_id}.{kind}"
        if not isinstance(old_relative, str) or not isinstance(new_relative, str):
            errors.append(f"{label}: missing WAV path")
            return
        if old_relative != new_relative:
            errors.append(f"{label}: preserved WAV path changed")
        old_path = (baseline / old_relative).resolve()
        new_path = (pack / new_relative).resolve()
        if not old_path.is_relative_to(baseline) or not new_path.is_relative_to(pack):
            errors.append(f"{label}: WAV path escapes its pack")
            return
        try:
            old_bytes, new_bytes = old_path.read_bytes(), new_path.read_bytes()
        except OSError as exc:
            errors.append(f"{label}: cannot read preserved WAV: {exc}")
            return
        old_hash = hashlib.sha256(old_bytes).hexdigest()
        new_hash = hashlib.sha256(new_bytes).hexdigest()
        baseline_intact = isinstance(expected_hash, str) and expected_hash == old_hash
        unchanged = old_bytes == new_bytes
        if not baseline_intact:
            errors.append(f"{label}: baseline WAV does not match its recorded SHA256")
        if not unchanged:
            errors.append(f"{label}: preserved WAV changed from baseline")
        comparison["files"].append({
            "profile": profile_id, "kind": kind, "path": new_relative,
            "baseline_sha256": old_hash, "current_sha256": new_hash,
            "baseline_intact": baseline_intact, "unchanged": unchanged,
        })
        comparison["engine_bands" if kind.startswith(("loaded[", "coast[")) else "effects"] += 1

    for profile_id in ORIGINAL_PROFILES:
        old, new = old_profiles.get(profile_id), new_profiles.get(profile_id)
        if not isinstance(old, dict) or not isinstance(new, dict):
            errors.append(f"baseline.{profile_id}: original profile missing in one pack")
            continue
        old_rpm, new_rpm = old.get("rpm_bands"), new.get("rpm_bands")
        old_hashes = old.get("sha256")
        if not isinstance(old_hashes, dict):
            errors.append(f"baseline.{profile_id}: missing recorded SHA256 map")
            old_hashes = {}
        if not isinstance(old_rpm, list) or len(old_rpm) != BAND_COUNT or not all(is_number(r) and np.isfinite(r) for r in old_rpm):
            errors.append(f"baseline.{profile_id}: invalid baseline RPM anchors")
            continue
        if not isinstance(new_rpm, list) or len(new_rpm) != BAND_COUNT:
            errors.append(f"baseline.{profile_id}: missing current RPM anchors")
            continue
        for band, rpm in enumerate(old_rpm):
            if rpm <= LOW_RPM_LIMIT:
                continue
            if new_rpm[band] != rpm:
                errors.append(f"baseline.{profile_id}[{band}]: high RPM anchor changed")
            for state in ("loaded", "coast"):
                old_paths, new_paths = old.get(state), new.get(state)
                if not isinstance(old_paths, list) or not isinstance(new_paths, list) or len(old_paths) != BAND_COUNT or len(new_paths) != BAND_COUNT:
                    errors.append(f"baseline.{profile_id}.{state}: incomplete band references")
                    continue
                old_relative = old_paths[band]
                expected_hash = old_hashes.get(old_relative) if isinstance(old_relative, str) else None
                compare_file(profile_id, f"{state}[{band}]", old_relative, new_paths[band], expected_hash)
        for effect in ("turbo_spool", "bypass_release") if profile_id in ("jz2_i6_turbo", "rb26_i6_turbo") else ():
            old_effects, new_effects = old.get("effects"), new.get("effects")
            old_effect = old_effects.get(effect) if isinstance(old_effects, dict) else None
            new_effect = new_effects.get(effect) if isinstance(new_effects, dict) else None
            if not isinstance(old_effect, dict) or not isinstance(new_effect, dict):
                errors.append(f"baseline.{profile_id}.{effect}: preserved effect missing")
                continue
            old_relative = old_effect.get("path")
            expected_hash = old_hashes.get(old_relative) if isinstance(old_relative, str) else None
            compare_file(profile_id, effect, old_relative, new_effect.get("path"), expected_hash)
    for key, expected in (("engine_bands", 40), ("effects", 4)):
        if comparison[key] != expected:
            errors.append(f"baseline: expected {expected} compared {key}, got {comparison[key]}")
    comparison["valid"] = len(errors) == before
    return comparison


def validate_pack(pack: Path, baseline: Path | None = None) -> dict:
    pack = pack.resolve()
    errors: list[str] = []
    report: dict = {
        "pack": str(pack),
        "scope": "Offline file and signal contract only. Does not certify listening quality, engine authenticity, runtime integration or FPS.",
        "contract": {
            "sample_rate": SAMPLE_RATE,
            "useful_frames": USEFUL_FRAMES,
            "low_rpm_frames": LOW_RPM_FRAMES,
            "low_rpm_max": LOW_RPM_LIMIT,
            "guard_frames": GUARD_FRAMES,
            "bands_per_state": BAND_COUNT,
            "release_frames": RELEASE_FRAMES,
            "release_guard_frames": 0,
            "sha256_required": True,
            "seam_rule": "abs(first-last) <= 1.25 * max(abs(diff(useful_pcm))) + 2/32768",
        },
        "valid": False,
        "errors": errors,
        "files": [],
    }
    try:
        manifest = json.loads((pack / "manifest.json").read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        errors.append(f"manifest.json: cannot read manifest: {exc}")
        return report
    if not isinstance(manifest, dict):
        errors.append("manifest.json: expected an object")
        return report
    for key, expected in (("sample_rate", SAMPLE_RATE), ("guard_frames", GUARD_FRAMES)):
        if type(manifest.get(key)) is not int or manifest[key] != expected:
            errors.append(f"manifest.json: {key} must be the integer {expected}")
    profiles = manifest.get("profiles")
    if not isinstance(profiles, list):
        errors.append("manifest.json: profiles must be an array")
        return report
    if len(profiles) != len(EXPECTED_PROFILES):
        errors.append(f"manifest.json: expected {len(EXPECTED_PROFILES)} profiles, got {len(profiles)}")

    ids: set[str] = set()
    referenced: set[Path] = set()
    for profile_index, profile in enumerate(profiles):
        label = f"profiles[{profile_index}]"
        if not isinstance(profile, dict):
            errors.append(f"{label}: expected an object")
            continue
        profile_id = profile.get("id")
        if not isinstance(profile_id, str) or not profile_id:
            errors.append(f"{label}: id must be a nonempty string")
            continue
        label = profile_id
        if profile_id in ids:
            errors.append(f"{label}: duplicate profile id")
        ids.add(profile_id)
        if profile_id not in EXPECTED_PROFILES:
            errors.append(f"{label}: unexpected profile id")
        elif type(profile.get("cylinders")) is not int or profile["cylinders"] != EXPECTED_PROFILES[profile_id]:
            errors.append(f"{label}: expected cylinders={EXPECTED_PROFILES[profile_id]}")
        if profile.get("architecture") != "piston_four_stroke":
            errors.append(f"{label}: architecture must be piston_four_stroke")
        expected_fuel = "diesel" if profile_id in DIESEL_PROFILES else "petrol"
        if profile.get("fuel") != expected_fuel:
            errors.append(f"{label}: fuel must be {expected_fuel}")
        rpm = profile.get("rpm_bands")
        if not isinstance(rpm, list) or len(rpm) != BAND_COUNT:
            errors.append(f"{label}: rpm_bands must contain seven values")
        elif not all(is_number(value) and np.isfinite(value) and value > 0 for value in rpm):
            errors.append(f"{label}: RPM values must be finite positive numbers")
        elif any(b <= a for a, b in zip(rpm, rpm[1:])):
            errors.append(f"{label}: RPM bands must strictly increase")
        band_frames = profile.get("band_frames")
        expected_frames = [LOW_RPM_FRAMES if is_number(r) and r <= LOW_RPM_LIMIT else USEFUL_FRAMES
                           for r in rpm] if isinstance(rpm, list) and len(rpm) == BAND_COUNT else [USEFUL_FRAMES] * BAND_COUNT
        if not isinstance(band_frames, list) or len(band_frames) != BAND_COUNT:
            errors.append(f"{label}: band_frames must contain seven frame counts")
        elif any(type(frames) is not int or frames != expected for frames, expected in zip(band_frames, expected_frames)):
            errors.append(f"{label}: band_frames must be 132300 at <=1500 RPM and 44100 above")

        entries: list[tuple[str, int | None, object, bool, int]] = []
        for state in ("loaded", "coast"):
            paths = profile.get(state)
            if not isinstance(paths, list) or len(paths) != BAND_COUNT:
                errors.append(f"{label}.{state}: expected exactly seven relative WAV paths")
                continue
            for band, relative in enumerate(paths):
                entries.append((state, band, relative, True, expected_frames[band]))

        turbo = profile_id in TURBO_PROFILES
        if profile.get("turbo") is not turbo:
            errors.append(f"{label}: turbo must be {str(turbo).lower()}")
        bypass = profile_id in PETROL_TURBOS
        if profile.get("bypass_valve") is not bypass:
            errors.append(f"{label}: bypass_valve must be {str(bypass).lower()}")
        expected_effects = {"turbo_spool": True} if turbo else {}
        if bypass:
            expected_effects["bypass_release"] = False
        effects = profile.get("effects")
        if not isinstance(effects, dict):
            errors.append(f"{label}: effects must be an object")
        else:
            if set(effects) != set(expected_effects):
                errors.append(f"{label}: effects must be {sorted(expected_effects)}; naturally aspirated profiles have no turbo effects and diesel has no bypass release")
            for effect, looped in expected_effects.items():
                metadata = effects.get(effect)
                if not isinstance(metadata, dict):
                    errors.append(f"{label}.{effect}: missing effect metadata")
                    continue
                expected_guard = GUARD_FRAMES if looped else 0
                if metadata.get("loop") is not looped:
                    errors.append(f"{label}.{effect}: loop must be {str(looped).lower()}")
                if type(metadata.get("guard_frames")) is not int or metadata["guard_frames"] != expected_guard:
                    errors.append(f"{label}.{effect}: guard_frames must be {expected_guard}")
                entries.append((effect, None, metadata.get("path"), looped,
                                USEFUL_FRAMES if looped else RELEASE_FRAMES))

        hashes = profile.get("sha256")
        if not isinstance(hashes, dict):
            errors.append(f"{label}: sha256 must map every referenced WAV to its hash")
            hashes = {}
        expected_paths = {relative for _, _, relative, _, _ in entries if isinstance(relative, str)}
        if set(hashes) != expected_paths:
            errors.append(f"{label}: SHA256 keys must match all referenced bands and effects exactly")
        for state, band, relative, looped, useful_frames in entries:
            file_label = f"{label}.{state}" + (f"[{band}]" if band is not None else "")
            if not isinstance(relative, str) or not relative or Path(relative).is_absolute():
                errors.append(f"{file_label}: expected a relative path")
                continue
            resolved = (pack / relative).resolve()
            if not resolved.is_relative_to(pack):
                errors.append(f"{file_label}: path escapes the pack directory")
                continue
            if resolved in referenced:
                errors.append(f"{file_label}: WAV path reused: {relative}")
            referenced.add(resolved)
            if not resolved.is_file():
                errors.append(f"{file_label}: missing file: {relative}")
                continue
            file_report = inspect_wav(resolved, relative, errors, looped=looped, useful_frames=useful_frames)
            file_report.update({"profile": profile_id, "state": state, "band": band})
            expected_hash = hashes.get(relative)
            try:
                actual_hash = hashlib.sha256(resolved.read_bytes()).hexdigest()
                hash_matches = isinstance(expected_hash, str) and expected_hash == actual_hash
                file_report.update({"sha256": actual_hash, "sha256_matches": hash_matches})
                if not hash_matches:
                    errors.append(f"{file_label}: SHA256 missing or does not match manifest")
                    file_report["valid"] = False
            except OSError as exc:
                errors.append(f"{file_label}: cannot hash WAV: {exc}")
                file_report["valid"] = False
            report["files"].append(file_report)

    for missing in sorted(set(EXPECTED_PROFILES) - ids):
        errors.append(f"manifest.json: missing profile {missing}")
    report["profile_count"] = len(ids)
    report["file_count"] = len(report["files"])
    report["engine_band_count"] = sum(item["band"] is not None for item in report["files"])
    report["effect_count"] = sum(item["band"] is None for item in report["files"])
    report["verified_hash_count"] = sum(item.get("sha256_matches") is True for item in report["files"])
    if baseline is not None:
        report["baseline_comparison"] = compare_baseline(pack, baseline, manifest, errors)
    report["valid"] = not errors
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack", required=True, type=Path, help="Directory containing manifest.json")
    parser.add_argument("--report", required=True, type=Path, help="Output JSON report")
    parser.add_argument("--baseline", type=Path, help="Original four-profile pack whose high bands and effects must remain unchanged")
    args = parser.parse_args()
    report = validate_pack(args.pack, args.baseline)
    try:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    except OSError as exc:
        print(f"Cannot write report: {exc}", file=sys.stderr)
        return 2
    status = "PASS" if report["valid"] else "FAIL"
    print(f"ENGINE_DESIGN_PACK {status}: {report.get('file_count', 0)} WAVs checked; {len(report['errors'])} errors")
    for error in report["errors"]:
        print(f"  {error}")
    print(f"Report: {args.report.resolve()}")
    return 0 if report["valid"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
