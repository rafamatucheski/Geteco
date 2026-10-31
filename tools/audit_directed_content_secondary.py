"""Segunda leitura ASR focada, na CPU; nunca publica nem certifica audição.

Exige personagens/SHAs selecionados explicitamente ou marcas da revisão primária. O roteiro
esperado não é passado ao ASR como prompt. Pesos diferentes do Whisper ainda podem
compartilhar vieses de reconhecimento: concordância é evidência, não aprovação artística.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import time

from audit_directed_voices import words
from build_directed_voices import install_budget
from voice_direction import ROOT, DirectionError, write_json as write_report

MODEL_ID = "dropbox-dash/faster-whisper-large-v3-turbo"
MODEL_REVISION = "0a363e9161cbc7ed1431c9597a8ceaf0c4f78fcf"
MODEL_SHA256 = "e76620f83d5f5b69efd3d87e3dc180c1bd21df9fbebacfd4335e5e1efcc018da"
MODEL_PATH = Path("D:/geteco/tools/opening_voice_models/whisper/models--dropbox-dash--faster-whisper-large-v3-turbo/snapshots") / MODEL_REVISION
OPTIONS = {"device":"cpu", "compute_type":"int8", "cpu_threads":1, "num_workers":1,
           "beam_size":3, "best_of":1, "temperature":0, "vad_filter":False,
           "condition_on_previous_text":False, "initial_prompt":None}


def selected_rows(report, characters, shas, limit):
    result = []
    for row in report.get("takes", []):
        if not row.get("asr") or row.get("technical_errors"):
            continue
        sha = row.get("waveform", {}).get("sha256", "")
        if characters or shas:
            if row.get("character_id") not in characters and sha not in shas:
                continue
        elif not row["asr"].get("review"):
            continue
        if row.get("language") not in ("pt_BR", "en") or not row.get("expected"):
            raise DirectionError("Secondary ASR needs an explicit language and expected script")
        result.append(row)
    return result[:limit]


def cached_rows(report):
    """Guarda leituras presas ao SHA entre lotes pequenos sem ler de novo."""
    result = {}
    for group in ("archived_takes", "takes"):
        for row in report.get(group, []):
            bound = dict(row)
            for name in ("secondary_model", "model_revision", "model_sha256",
                         "options", "primary_report_sha256"):
                if name in report:
                    bound.setdefault(name, report[name])
            result[bound["cache_key"]] = bound
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--primary", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--character", action="append", default=[])
    parser.add_argument("--audio-sha", action="append", default=[])
    parser.add_argument("--limit", type=int, default=4)
    parser.add_argument("--cpu-threads", type=int, choices=(1,2), default=1)
    parser.add_argument("--deadline-seconds", type=int, default=900)
    parser.add_argument("--memory-mb", type=int, default=4096)
    parser.add_argument("--reserve-mb", type=int, default=2048)
    args = parser.parse_args()
    if not 1 <= args.limit <= 64 or not 60 <= args.deadline_seconds <= 3600:
        parser.error("Use a finite batch of 1–64 recordings and 60–3600 seconds")
    if not 2048 <= args.memory_mb <= 6144 or args.reserve_mb < 1024:
        parser.error("Use a 2–6 GiB process cap and at least 1 GiB system reserve")
    if args.output.resolve().is_relative_to((ROOT / "audio").resolve()) or args.output.resolve() == args.primary.resolve():
        raise DirectionError("Read-only review cannot overwrite the bank or primary report")
    options = dict(OPTIONS,cpu_threads=args.cpu_threads)
    for name in ("OMP_NUM_THREADS", "MKL_NUM_THREADS", "OPENBLAS_NUM_THREADS"):
        os.environ[name] = str(args.cpu_threads)
    os.environ.update(CUDA_VISIBLE_DEVICES="-1", HF_HUB_OFFLINE="1", TRANSFORMERS_OFFLINE="1")
    install_budget(args.deadline_seconds, args.memory_mb, args.reserve_mb)
    started = time.monotonic()
    primary_bytes = args.primary.read_bytes()
    primary = json.loads(primary_bytes)
    chosen = selected_rows(primary, set(args.character), set(args.audio_sha), args.limit)
    if not chosen:
        raise DirectionError("No finite selected, technically valid primary-ASR recordings")
    with (MODEL_PATH / "model.bin").open("rb") as source:
        model_sha = hashlib.file_digest(source, "sha256").hexdigest()
    if model_sha != MODEL_SHA256:
        raise DirectionError("ASR model differs from the pinned LFS SHA256")
    download = json.loads((MODEL_PATH / "download-provenance.json").read_text(encoding="utf8"))
    for name in ("config.json", "tokenizer.json", "preprocessor_config.json", "vocabulary.json"):
        if hashlib.sha256((MODEL_PATH / name).read_bytes()).hexdigest() != download["files"][name]["sha256"]:
            raise DirectionError("ASR model metadata changed: " + name)
    previous = json.loads(args.output.read_text(encoding="utf8")) if args.output.exists() else {}
    cached = cached_rows(previous)
    report = {"version":1, "primary_report":str(args.primary.resolve()),
              "primary_report_sha256":hashlib.sha256(primary_bytes).hexdigest(),
              "primary_model":primary.get("asr_model"),
              "secondary_model":MODEL_ID, "model_revision":MODEL_REVISION,
              "model_sha256":model_sha, "options":options,
              "budget":{"limit":args.limit, "deadline_seconds":args.deadline_seconds,
                        "memory_mb":args.memory_mb, "reserve_mb":args.reserve_mb},
              "sources":["https://github.com/SYSTRAN/faster-whisper/tree/v1.2.1",
                         "https://huggingface.co/"+MODEL_ID+"/tree/"+MODEL_REVISION,
                         "https://huggingface.co/openai/whisper-large-v3-turbo"],
              "method":f"Pinned four-decoder-layer CTranslate2 model; CPU{args.cpu_threads}/int8; no expected-text prompt; full selected utterances only",
              "limitations":"Second weights, same Whisper family: shared errors remain possible. Textual agreement is not listening approval, pronunciation certification or acting review. Short Ai/Ow may be poorly recognized.",
              "human_listening":False, "audio_modified":False,
              "archived_takes":list(cached.values()), "takes":[]}
    pending = []
    for row in chosen:
        resource = row["path"]
        if not resource.startswith("res://audio/mission_voices/directed/"):
            raise DirectionError("Unexpected recording resource")
        path = (ROOT / resource[6:]).resolve()
        path.relative_to((ROOT / "audio/mission_voices/directed").resolve())
        sha = hashlib.sha256(path.read_bytes()).hexdigest()
        if sha != row["waveform"]["sha256"]:
            raise DirectionError("Recording changed since primary ASR: " + row["character_id"])
        key = hashlib.sha256(json.dumps([sha, row["language"],row["expected"],MODEL_SHA256,
                                        options,row["asr"]["transcript"]],sort_keys=True).encode()).hexdigest()
        if key in cached:
            report["takes"].append(cached[key])
        else:
            pending.append((row,path,sha,key))
    report["selected"] = len(chosen)
    write_report(args.output,report)
    import psutil
    process = psutil.Process()

    def save():
        memory = process.memory_info()
        report["elapsed_seconds"] = round(time.monotonic()-started,3)
        report["memory"] = {"rss_mb":round(memory.rss/1024**2,1),
                            "peak_working_set_mb":round(getattr(memory,"peak_wset",memory.rss)/1024**2,1),
                            "private_mb":round(getattr(memory,"private",memory.rss)/1024**2,1),
                            "peak_commit_mb":round(getattr(memory,"peak_pagefile",memory.rss)/1024**2,1)}
        report["checked"] = len(report["takes"])
        report["complete_selected_batch"] = len(report["takes"]) == len(chosen)
        write_report(args.output,report)

    if pending:
        from faster_whisper import WhisperModel
        import difflib
        loading = time.monotonic()
        model = WhisperModel(str(MODEL_PATH),device="cpu",compute_type="int8",
                             cpu_threads=args.cpu_threads,num_workers=1,local_files_only=True)
        report["model_load_seconds"] = round(time.monotonic()-loading,3)
        report["versions"] = {name:importlib.metadata.version(name) for name in ("faster-whisper","ctranslate2")}
        save()
        for row,path,sha,key in pending:
            began = time.monotonic()
            segments,_ = model.transcribe(str(path),language="pt" if row["language"]=="pt_BR" else "en",
                beam_size=3,best_of=1,temperature=0,vad_filter=False,
                condition_on_previous_text=False,initial_prompt=None)
            segment_data = [{"start":s.start,"end":s.end,"text":s.text.strip(),
                             "avg_logprob":s.avg_logprob,"no_speech_prob":s.no_speech_prob} for s in segments]
            transcript = " ".join(s["text"] for s in segment_data)
            expected_words,heard_words = words(row["expected"]),words(transcript)
            comparison = "exact_normalized_text_match" if expected_words==heard_words else "textual_adjudication_required"
            report["takes"].append({"cache_key":key,"audio_sha256":sha,
                "secondary_model":MODEL_ID,"model_revision":MODEL_REVISION,
                "model_sha256":MODEL_SHA256,"options":options,
                "primary_report_sha256":report["primary_report_sha256"],
                "character_id":row["character_id"],"source_key":row.get("source_key",""),
                "path":row["path"],"language":row["language"],"expected":row["expected"],
                "primary_asr":row["asr"],"secondary_asr":{"transcript":transcript,
                    "word_similarity":round(difflib.SequenceMatcher(None,expected_words,heard_words).ratio(),4),
                    "seconds":round(time.monotonic()-began,3),"segments":segment_data},
                "comparison":comparison,"human_listening":False,"artistic_approval":False})
            save()
            print("SECONDARY_ASR " + row["character_id"] + " " + comparison,flush=True)
    save()
    selection_sha = hashlib.sha256(json.dumps(
        sorted(row["cache_key"] for row in report["takes"])).encode()).hexdigest()
    snapshot = args.output.parent / "secondary-asr-snapshots" / (
        report["primary_report_sha256"] + "_" + selection_sha + ".json")
    if not snapshot.exists():
        write_report(snapshot, report)
    print(json.dumps({key:report[key] for key in ("checked","selected","complete_selected_batch","elapsed_seconds","memory")}))


if __name__ == "__main__":
    main()
