"""Resumable read-only WAV/content audit; never certifies acting or speaker gender."""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import difflib
import hashlib
import json
import os
from pathlib import Path
import time
import unicodedata

from audit_voice_performance import waveform
from voice_direction import write_json

ROOT = Path(__file__).resolve().parents[1]
WHISPER = Path("D:/geteco/tools/opening_voice_models/whisper/models--Systran--faster-whisper-small/snapshots/536b0662742c02347bc0e980a01041f333bce120")
ASR_VERSION = "whisper-small-int8-cpu1-beam3-v1"


def words(text):
    plain = "".join(c for c in unicodedata.normalize("NFD", text.lower())
                    if unicodedata.category(c) != "Mn")
    return "".join(c if c.isalnum() else " " for c in plain).split()


def entries(manifest):
    if isinstance(manifest.get("takes"), list):
        return manifest["takes"]
    if isinstance(manifest.get("characters"), dict):
        return list(manifest["characters"].values())
    rows = manifest.get("lines", {})
    if isinstance(rows, list):
        return rows
    result = []
    for language, bank in rows.items():
        for key, row in bank.items():
            result.append(dict(row, language=language, source_key=key))
    return result


def write_report(path, report):
    # Readers can briefly hold Windows handles without delete sharing. Use the
    # same finite atomic-write retry as the producer; never discard a checkpoint.
    write_json(path, report)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--asr-max", type=int, default=0)
    parser.add_argument("--selection", choices=("representatives", "all"), default="representatives")
    parser.add_argument("--priority-section", action="append", default=[],
                        help="Audit these authored sections first without skipping other recordings")
    parser.add_argument("--deadline-seconds", type=int, default=900)
    parser.add_argument("--workers", type=int, choices=(1, 2, 3), default=1,
                        help="Shared read-only ASR model; each worker uses one CPU thread, never CUDA")
    args = parser.parse_args()
    if args.asr_max < 0 or not 30 <= args.deadline_seconds <= 3600:
        parser.error("Use a nonnegative ASR batch and a finite 30–3600 second deadline")
    started = time.monotonic()
    manifest_bytes = args.manifest.read_bytes()
    manifest = json.loads(manifest_bytes.decode("utf-8-sig"))
    previous = json.loads(args.output.read_text(encoding="utf-8")) if args.output.exists() else {}
    cached = {row["audit_key"]: row for row in previous.get("takes", [])}
    report = {"version": 1, "manifest": str(args.manifest.resolve()),
              "manifest_sha256": hashlib.sha256(manifest_bytes).hexdigest(),
              "method": "All listed WAVs checked; offline CPU Whisper on a finite selected batch",
              "limitations": ["ASR checks lexical content, not emotion, perceived gender, accent or identity.",
                              "ASR differences are review cues; homophones and names can produce false flags.",
                              "The input is a manifest snapshot; a producer may subsequently add recordings."],
              "takes": [], "asr_model": ASR_VERSION, "asr_cpu_workers": args.workers}
    pending = []
    source_entries = entries(manifest)
    if not source_entries:
        raise ValueError("No completed recordings in the input manifest; zero checks cannot pass")
    for source in source_entries:
        resource = source.get("path", "")
        if not resource.startswith("res://audio/mission_voices/directed/") or ".." in Path(resource).parts:
            raise ValueError("Unexpected recording resource: " + resource)
        path = ROOT / resource.removeprefix("res://")
        text = source.get("spoken_text", source.get("text", ""))
        language = source.get("language", "")
        if not text or language not in ("pt_BR", "en"):
            raise ValueError("Recording requires explicit text and language: " + resource)
        info = waveform(path)
        sha = info.get("sha256", "")
        cache_key = hashlib.sha256((sha + "|" + language + "|" + text + "|" + ASR_VERSION).encode()).hexdigest()
        row = {"audit_key": cache_key, "source_key": source.get("source_key", source.get("key", "")),
               "character_id": source.get("character_id", "benchmark"), "language": language,
               "source_section": source.get("section", source.get("source_section", "")),
               "expected": text, "path": resource, "waveform": info}
        errors = []
        if info.get("error"):
            errors.append(info["error"])
        else:
            if info["sample_rate"] != 24000: errors.append("Unexpected sample rate")
            if info["peak"] < .01 or info["active_seconds"] == 0: errors.append("Silent or nearly silent")
            if info["hard_clipped_samples"]: errors.append("Hard clipped samples")
            if source.get("audio_sha256") and sha != source["audio_sha256"]: errors.append("Audio hash mismatch")
            declared = source.get("duration_seconds", source.get("seconds", 0))
            if declared and abs(info["seconds"] - declared) > .002: errors.append("Duration mismatch")
        row["technical_errors"] = errors
        if cache_key in cached and "asr" in cached[cache_key]: row["asr"] = cached[cache_key]["asr"]
        elif not errors: pending.append(row)
        report["takes"].append(row)

    def save():
        report["waveforms_checked"] = len(report["takes"])
        report["technical_failures"] = sum(bool(r["technical_errors"]) for r in report["takes"])
        report["asr_checked"] = sum("asr" in r for r in report["takes"])
        report["asr_review_flags"] = sum(r.get("asr", {}).get("review", False) for r in report["takes"])
        report["elapsed_seconds"] = round(time.monotonic() - started, 3)
        write_report(args.output, report)

    save()
    if args.selection == "representatives":
        covered = {(r["character_id"], r["language"]) for r in report["takes"] if "asr" in r}
        chosen = {}
        for row in pending:
            group = (row["character_id"], row["language"])
            if group in covered: continue
            if group not in chosen or abs(row["waveform"]["seconds"] - 6) < abs(chosen[group]["waveform"]["seconds"] - 6):
                chosen[group] = row
        pending = list(chosen.values())
    if args.priority_section:
        pending.sort(key=lambda row: row["source_section"] not in args.priority_section)
    pending = pending[:args.asr_max]
    if pending:
        os.environ["OMP_NUM_THREADS"] = "1"
        os.environ["OPENBLAS_NUM_THREADS"] = "1"
        os.environ["HF_HUB_OFFLINE"] = "1"
        os.environ["TRANSFORMERS_OFFLINE"] = "1"
        from faster_whisper import WhisperModel
        model = WhisperModel(str(WHISPER), device="cpu", compute_type="int8", cpu_threads=1,
                             num_workers=args.workers, local_files_only=True)

        def transcribe(row):
            if time.monotonic() - started >= args.deadline_seconds:
                return row, None
            began = time.monotonic()
            segments, _ = model.transcribe(str(ROOT / row["path"].removeprefix("res://")),
                language="pt" if row["language"] == "pt_BR" else "en", beam_size=3, best_of=1,
                temperature=0, vad_filter=False, condition_on_previous_text=False,
                initial_prompt="Dante, Maciota, Vicente, Jessica, Harbor, Ferrugem, Takeshi, Helena, Neco.")
            transcript = " ".join(segment.text.strip() for segment in segments)
            similarity = difflib.SequenceMatcher(None, words(row["expected"]), words(transcript)).ratio()
            return row, {"transcript": transcript, "word_similarity": round(similarity, 4),
                         "review": similarity < .85 or not transcript,
                         "seconds": round(time.monotonic() - began, 3)}

        # CTranslate2's worker pool shares model weights. Only the main thread
        # mutates/writes the report; every completed waveform remains resumable.
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            futures = [pool.submit(transcribe, row) for row in pending]
            for index, future in enumerate(as_completed(futures)):
                row, result = future.result()
                if result is None:
                    report["deadline_reached"] = True
                    continue
                row["asr"] = result
                save()
                print(f'DIRECTED_ASR {index + 1}/{len(pending)} {row["character_id"]} {row["language"]} {result["word_similarity"]:.3f}', flush=True)
    save()
    print(json.dumps({k: report[k] for k in ("waveforms_checked", "technical_failures", "asr_checked", "asr_review_flags", "elapsed_seconds")}))
    return 1 if report["technical_failures"] else (2 if report.get("deadline_reached") else 0)


if __name__ == "__main__":
    raise SystemExit(main())
