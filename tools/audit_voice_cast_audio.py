"""Apoio acústico de elenco, só na CPU, para vozes fictícias do jogo; nunca identidade humana.

O classificador binário ECAPA é evidência para marcar prováveis desencontros com o elenco
autorado, não substitui ouvir nem afirma nada sobre o gênero de pessoas reais.
Modelo: JaesungHuh ECAPA ajustado, export ONNX MIT por Alice-Sabrina-Ivy.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import statistics
import time
from pathlib import Path

from voice_direction import ROOT, read_json, write_json, DirectionError

for _name in ("OMP_NUM_THREADS", "MKL_NUM_THREADS", "OPENBLAS_NUM_THREADS"):
    os.environ[_name] = "1"

MODEL_REVISION = "5debf995242f9851881d4e4848fe6eed2bb5ade7"
MODEL = Path("D:/geteco/tools/opening_voice_models/hub/models--Alice-Sabrina-Ivy--voice-gender-classifier-onnx-q8/snapshots") / MODEL_REVISION / "onnx/model_quantized.onnx"
MODEL_SHA256 = "33a7f84f17d5ceee61aae8b23488e06fc1e3295a44eaf7eb5744f3e01e380784"
# Registrado antes de inspecionar qualquer previsão de âncora. As notas são saídas do modelo,
# não probabilidades calibradas de verdade nem julgamento humano sobre uma identidade.
POLICY = {"version": 1, "confidence_threshold": .8, "window_seconds": 2,
          "distributed_windows": 3, "minimum_seconds": .75,
          "silent_window_rms_floor": .001, "aggregation": "median female softmax score",
          "disagreement": "review if any usable window confidently opposes authored cast"}
SOURCES = ["https://huggingface.co/JaesungHuh/voice-gender-classifier",
           "https://raw.githubusercontent.com/JaesungHuh/voice-gender-classifier/main/model.py",
           "https://huggingface.co/Alice-Sabrina-Ivy/voice-gender-classifier-onnx-q8/blob/" + MODEL_REVISION + "/README.md"]


def evaluate_scores(predictions, expected):
    """Classifica o apoio ao elenco fictício; nunca devolve decisão de aprovação."""
    if expected not in ("male", "female") or not predictions:
        raise DirectionError("Explicit casting and usable audio windows required")
    if any(not math.isfinite(p) or not 0 <= p <= 1 for p in predictions):
        raise DirectionError("Invalid classifier probability")
    female = float(statistics.median(predictions))
    predicted = "female" if female >= .5 else "male"
    confidence = female if predicted == "female" else 1-female
    support = female if expected == "female" else 1-female
    threshold = POLICY["confidence_threshold"]
    opposition = [1-p if expected == "female" else p for p in predictions]
    if 1-support >= threshold:
        interpretation = "review_likely_cast_mismatch"
    elif support < threshold:
        interpretation = "review_ambiguous_acoustic_profile"
    elif any(p >= threshold for p in opposition):
        interpretation = "review_window_disagreement"
    else:
        interpretation = "supports_authored_cast_not_approval"
    return {"predicted_voice_class": predicted, "female_probability": female,
            "male_probability": 1-female, "confidence": confidence,
            "expected_cast_probability": support, "window_female_probabilities": predictions,
            "review": interpretation != "supports_authored_cast_not_approval",
            "interpretation": interpretation, "human_approval": False}


def rows(document):
    if isinstance(document.get("characters"), dict):
        return list(document["characters"].values())
    if isinstance(document.get("takes"), list):
        return document["takes"]
    raise DirectionError("Expected anchors or recording provenance")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=ROOT / "audio/mission_voices/directed/anchors.json")
    parser.add_argument("--output", type=Path, default=ROOT / "evidence/voice-direction-20261012/cast-acoustic-audit.json")
    parser.add_argument("--limit", type=int, default=2000)
    parser.add_argument("--deadline-seconds", type=int, default=900)
    args = parser.parse_args()
    if args.limit <= 0 or not 30 <= args.deadline_seconds <= 3600:
        raise DirectionError("Use a positive limit and finite 30–3600 second deadline")
    if args.output.resolve().is_relative_to((ROOT / "audio").resolve()) or args.output.resolve() == args.manifest.resolve():
        raise DirectionError("Read-only audit cannot write into the audio bank or input manifest")
    import numpy as np
    import onnxruntime as ort
    import soundfile as sf
    from scipy.signal import resample_poly
    started = time.monotonic()
    manifest_bytes = args.manifest.read_bytes()
    document = json.loads(manifest_bytes)
    anchor_scope = isinstance(document.get("characters"), dict)
    # Reações curtas futuras da produção não servem como amostras de elenco de
    # dois segundos. Isto acrescenta um estado de evidência explícito, sem mudar a
    # política original de classificador/limiar das âncoras nem invalidar o cache dela.
    minimum_seconds = POLICY["minimum_seconds"] if anchor_scope else 2.0
    clip_policy = "anchor_v1" if anchor_scope else "production_minimum_2_seconds_v1"
    manifest_sha = hashlib.sha256(manifest_bytes).hexdigest()
    model_sha = hashlib.sha256(MODEL.read_bytes()).hexdigest()
    if model_sha != MODEL_SHA256:
        raise DirectionError("Classifier bytes differ from pinned HF LFS SHA-256")
    config = read_json(MODEL.parent.parent / "config.json")
    preprocessor = read_json(MODEL.parent.parent / "preprocessor_config.json")
    if config.get("id2label") != {"0":"male", "1":"female"}:
        raise DirectionError("Unexpected classifier label order")
    if preprocessor.get("sampling_rate") != 16000 or preprocessor.get("do_normalize") is not False:
        raise DirectionError("Unexpected preprocessing: raw 16k waveform without normalization required")
    cast_path = ROOT / "data/dialogue/voice-cast.json"
    cast_bytes = cast_path.read_bytes()
    expected_cast = {}
    for persona in json.loads(cast_bytes)["personas"].values():
        for profile in [persona] + persona.get("variants", []):
            expected_cast[profile["voice"]["identity"]] = profile["gender"]
    policy_hash = hashlib.sha256(json.dumps(POLICY, sort_keys=True).encode()).hexdigest()
    old = read_json(args.output) if args.output.exists() else {"takes": []}
    cached = {t["cache_key"]: t for t in old["takes"]}
    options = ort.SessionOptions()
    options.intra_op_num_threads = 1
    options.inter_op_num_threads = 1
    options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
    session = ort.InferenceSession(str(MODEL), sess_options=options, providers=["CPUExecutionProvider"])
    inputs = session.get_inputs()
    if len(inputs) != 1 or inputs[0].type != "tensor(float)" or len(inputs[0].shape) != 2:
        raise DirectionError("Unexpected acoustic classifier input schema")
    report = {"version": 1, "model": "Alice-Sabrina-Ivy/voice-gender-classifier-onnx-q8",
              "model_revision": MODEL_REVISION, "model_sha256": model_sha,
              "sources": SOURCES, "license": "MIT; model README stored alongside pinned ONNX",
              "policy": POLICY, "policy_sha256": policy_hash,
              "scope":"anchors" if anchor_scope else "recorded_takes",
              "clip_policy":clip_policy, "minimum_usable_seconds":minimum_seconds,
              "deadline_seconds":args.deadline_seconds,
              "manifest": str(args.manifest.resolve()), "manifest_sha256": manifest_sha,
              "cast_sha256": hashlib.sha256(cast_bytes).hexdigest(),
              "method": "CPU1; float32 mono 16k waveform, polyphase resampling; no amplitude/mean normalization; graph includes STFT, mel and log-mean normalization; softmax logits labels0male/1female",
              "limitations": "Binary classifier scores can be wrong and are not calibrated truth probabilities. Training on VoxCeleb2 and q8 quantization do not establish accuracy on these synthetic PT-BR voices. Support is not listening approval. No assessment of acting, health, age or real-person gender identity.",
              "human_approval": False, "audio_modified": False,
              "takes": []}
    processed = 0
    sources = rows(document)
    if not anchor_scope:
        sources.sort(key=lambda row: float(row.get("duration_seconds", row.get("seconds", 999))) < 2.0)
    for source in sources:
        cast_gender = expected_cast.get(source.get("character_id"))
        if cast_gender not in ("female", "male"):
            raise DirectionError("Missing explicit authored identity/gender")
        if source.get("voice_gender", cast_gender) != cast_gender:
            raise DirectionError("Anchor authoring gender disagrees with frozen cast: " + source["character_id"])
        resource = source["path"]
        if not resource.startswith("res://audio/mission_voices/directed/"):
            raise DirectionError("Unexpected voice bank path")
        path = (ROOT / resource[6:]).resolve()
        path.relative_to((ROOT / "audio/mission_voices/directed").resolve())
        sha = hashlib.sha256(path.read_bytes()).hexdigest()
        if sha != source["audio_sha256"]:
            raise DirectionError("Audio changed since production")
        cache_base = model_sha + "|" + policy_hash + "|" + sha + "|" + cast_gender + "|" + source["character_id"]
        if not anchor_scope:
            cache_base += "|" + clip_policy
        cache_key = hashlib.sha256(cache_base.encode()).hexdigest()
        metadata = {"path":resource, "language":source.get("language", "pt_BR"),
                    "source_key":source.get("source_key",source.get("key","")),
                    "source_section":source.get("section",source.get("source_section","")),
                    "source_text":source.get("spoken_text",source.get("text", ""))}
        if cache_key in cached:
            # As notas acústicas dependem de bytes/elenco, enquanto caminho e texto de
            # referência pertencem a este retrato exato do manifesto.
            report["takes"].append(dict(cached[cache_key], **metadata))
            continue
        if processed >= args.limit:
            continue
        if time.monotonic()-started >= args.deadline_seconds:
            report["deadline_reached"] = True
            continue
        audio, rate = sf.read(path, dtype="float32", always_2d=False)
        if audio.ndim == 2:
            audio = np.mean(audio, axis=1, dtype=np.float32)
        if audio.ndim != 1 or not np.isfinite(audio).all():
            raise DirectionError("Invalid waveform")
        if rate != 16000:
            from math import gcd
            common = gcd(rate, 16000)
            audio = resample_poly(audio, 16000//common, rate//common).astype(np.float32)
        result = {"cache_key": cache_key, "audio_sha256": sha, **metadata,
                  "character_id": source["character_id"], "language": source.get("language", "pt_BR"),
                  "expected_gender": cast_gender, "duration_seconds": len(audio)/16000,
                  "source_anchor_text": source.get("text", "")}
        if len(audio) < int(16000 * minimum_seconds):
            result.update(status="insufficient_duration_for_casting", review=True,
                          required_seconds=minimum_seconds, human_approval=False)
        else:
            window = min(int(16000 * POLICY["window_seconds"]), len(audio))
            offsets = sorted({0, (len(audio)-window)//2, len(audio)-window})
            predictions = []
            windows = []
            for offset in offsets:
                samples = np.ascontiguousarray(audio[offset:offset+window].reshape(1, -1), dtype=np.float32)
                rms = float(np.sqrt(np.mean(samples**2)))
                if rms < POLICY["silent_window_rms_floor"]:
                    windows.append({"start_seconds":offset/16000, "rms":rms, "status":"too_quiet"})
                    continue
                output = session.run(None, {inputs[0].name: samples})[0]
                if output.shape != (1, 2) or not np.isfinite(output).all():
                    raise DirectionError("Invalid classifier logits")
                logits = output[0]
                probabilities = np.exp(logits-np.max(logits))
                probabilities /= probabilities.sum()
                predictions.append(float(probabilities[1]))
                windows.append({"start_seconds":offset/16000, "rms":rms, "status":"measured", "female_probability":float(probabilities[1])})
            result["windows"] = windows
            if predictions:
                result.update(status="measured", **evaluate_scores(predictions, cast_gender))
            else:
                result.update(status="insufficient_signal", review=True, human_approval=False)
        processed += 1
        report["takes"].append(result)
        report["elapsed_seconds"] = round(time.monotonic()-started, 3)
        report["review_flags"] = sum(t.get("review", False) for t in report["takes"])
        write_json(args.output, report)
        print("VOICE_CAST_AUDIT " + source["character_id"] + " " + str(result.get("interpretation", result["status"])), flush=True)
    report["elapsed_seconds"] = round(time.monotonic()-started, 3)
    report["review_flags"] = sum(t.get("review", False) for t in report["takes"])
    report["casting_review_flags"] = sum(t.get("review",False) and t.get("status")=="measured" for t in report["takes"])
    report["insufficient_evidence"] = sum(t.get("status")!="measured" for t in report["takes"])
    source_ids = {row["character_id"] for row in sources}
    report["coverage"] = {"source_count":len(sources), "checked":len(report["takes"]),
                          "expected_character_count":len(expected_cast),
                          "missing_characters":sorted(set(expected_cast)-source_ids),
                          "complete_current_manifest":len(sources)==len(report["takes"]),
                          "not_a_claim_all_planned_takes_exist":not anchor_scope,
                          "complete":len(sources)==len(report["takes"]) and source_ids==set(expected_cast)}
    audio_owners = {}
    for result in report["takes"]:
        audio_owners.setdefault(result["audio_sha256"], set()).add(result["character_id"])
    report["shared_audio_across_identities"] = [{"audio_sha256":sha, "characters":sorted(owners)}
                                                for sha, owners in audio_owners.items() if len(owners) > 1]
    report["distinct_file_note"] = "Different WAV hashes only establish different files; they do not establish perceptually distinct voice identities."
    # Preserva as previsões de antes da regravação mesmo quando o manifesto atual troca uma
    # âncora. Um retrato por manifesto/modelo/política imutável, fora do banco.
    snapshot = args.output.parent / "cast-acoustic-snapshots" / (manifest_sha + "_" + model_sha[:12] + "_" + policy_hash[:12] + ".json")
    report["snapshot_path"] = str(snapshot.resolve())
    write_json(snapshot, report)
    write_json(args.output, report)
    print(f"VOICE_CAST_AUDIT_COMPLETE checked={len(report['takes'])} flags={report['review_flags']}")


if __name__ == "__main__":
    main()
