"""Benchmark limitado de fala real. Nunca publica um manifesto de runtime."""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import time

from voice_direction import ROOT, read_json, write_json, digest, plan_takes, DirectionError
from voice_backend import (BASE_MODEL, LARGE_BASE_MODEL, DESIGN_MODEL, backend_settings, cached_snapshot,
                           condition_clone, load_model, package_versions, save_wave, synthesize_clone)
from build_directed_voices import install_budget

JESSICA = "2f74ccc16ed52b718b42204c49235f59574f5f599fab5aca4763f109dce41430"
ANCHOR = ROOT / "audio/mission_voices/directed/pt_BR" / (JESSICA + "_7d8ae2517fa89f66.wav")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backend", choices=("base", "base_large", "design"), default="base")
    parser.add_argument("--quantization", choices=("none", "nf4", "int8"), default="none")
    parser.add_argument("--instruction-mode", choices=("reference", "experimental_text"), default="experimental_text")
    parser.add_argument("--reference-mode", choices=("icl", "speaker_embedding", "per_language"), default="icl")
    parser.add_argument("--languages", nargs="+", choices=("pt_BR", "en"), default=["pt_BR", "en"])
    parser.add_argument("--timeout-seconds", type=int, default=360)
    parser.add_argument("--memory-mb", type=int, default=10000)
    parser.add_argument("--reserve-mb", type=int, default=3072)
    parser.add_argument("--vram-reserve-mb", type=int, default=768)
    parser.add_argument("--batch-size", type=int, choices=(1, 4, 8), default=1)
    args = parser.parse_args()
    if not 30 <= args.timeout_seconds <= 900 or args.reserve_mb < 2048 or args.vram_reserve_mb < 512:
        raise DirectionError("Benchmark needs finite deadline and desktop reserves")
    name = {"base": BASE_MODEL, "base_large": LARGE_BASE_MODEL, "design": DESIGN_MODEL}[args.backend]
    snapshot = cached_snapshot(name)
    settings = backend_settings(name, snapshot, args.quantization)
    from directed_voice_inventory import inventory
    cida_key = "a0f159168a801dab0e029c9259fde373c44d1123fcb8aa78ab0bd27a6abf3f40"
    keys = {JESSICA, cida_key} if args.batch_size > 1 else {JESSICA}
    rows = [r for r in inventory() if r["key"] in keys]
    takes = plan_takes(read_json(ROOT / "data/dialogue/voice-cast.json"),
                       read_json(ROOT / "data/dialogue/voice-line-direction.json"), rows, args.languages,
                       device="cuda", model_revision=snapshot.name)
    if args.batch_size == 8:
        takes = takes * 2
    anchor_sha = hashlib.sha256(ANCHOR.read_bytes()).hexdigest()
    bench_id = digest([settings, args.instruction_mode, args.reference_mode, anchor_sha, args.batch_size, [t["signature"] for t in takes]])[:16]
    output = ROOT / "audio/mission_voices/directed/benchmarks" / bench_id
    if (output / "benchmark.json").exists():
        print("VOICE_BENCHMARK_ALREADY_EXISTS " + str(output), flush=True)
        return
    install_budget(args.timeout_seconds, args.memory_mb, args.reserve_mb)
    model = load_model(snapshot, settings, vram_reserve_mb=args.vram_reserve_mb)
    import torch
    import psutil
    reference = condition_clone(model, ANCHOR, "Cinto, Dante. Respira. O volante agora é meu.",
                                x_vector_only=args.reference_mode == "speaker_embedding") if args.backend != "design" else None
    if args.batch_size > 1:
        if args.backend == "design" or len(takes) != args.batch_size:
            raise DirectionError("Batch comparison requires Base and both languages")
        cida = ROOT / "audio/mission_voices/directed/pt_BR" / (cida_key + "_fc2938c6c77dd73d.wav")
        cida_reference = condition_clone(model, cida, "Pode falar daí. Eu tô ouvindo.",
                                        x_vector_only=args.reference_mode == "speaker_embedding")
        prompts = [reference[0] if t["source_key"] == JESSICA else cida_reference[0] for t in takes]
        if args.reference_mode == "per_language":
            english_jessica = condition_clone(model, ANCHOR, "Cinto, Dante. Respira. O volante agora é meu.", x_vector_only=True)
            english_cida = condition_clone(model, cida, "Pode falar daí. Eu tô ouvindo.", x_vector_only=True)
            prompts = [(english_jessica[0] if t["source_key"] == JESSICA else english_cida[0])
                       if t["language"] == "en" else prompt for t, prompt in zip(takes, prompts)]
        started = time.monotonic()
        waves, rate = synthesize_clone(model, [t["spoken_text"] for t in takes], [t["model_language"] for t in takes],
                      prompts, [t["direction"] for t in takes], instruction_mode=args.instruction_mode,
                      seed=20261012, max_new_tokens=260)
        torch.cuda.synchronize()
        elapsed = round(time.monotonic()-started, 3)
        results = []
        for index, (take, wave) in enumerate(zip(takes, waves)):
            result = save_wave(wave, rate, output / (str(index) + "_" + take["character_id"] + "_" + take["language"] + ".wav"))
            result.update(language=take["language"], spoken_text=take["spoken_text"], character_id=take["character_id"])
            results.append(result)
        summary = {"version": 1, "settings": settings, "conditioning": args.instruction_mode,
                   "reference_mode": args.reference_mode,
                   "batch_size": args.batch_size, "batch_seconds": elapsed, "cuda_peak_mb": round(torch.cuda.max_memory_allocated()/1024**2, 1),
                   "package_versions": package_versions(), "takes": results, "complete": True}
        summary["effective_real_time_factor"] = elapsed / sum(t["duration_seconds"] for t in results)
        write_json(output / "benchmark.json", summary)
        print("VOICE_BATCH_BENCHMARK " + str(summary), flush=True)
        return
    results = []
    for take in takes:
        started = time.monotonic()
        torch.manual_seed(take["settings"]["seed"])
        if args.backend != "design":
            waves, rate = synthesize_clone(model, take["spoken_text"], take["model_language"], reference,
                           take["direction"], instruction_mode=args.instruction_mode,
                           seed=take["settings"]["seed"], max_new_tokens=260)
        else:
            waves, rate = model.generate_voice_design(text=take["spoken_text"], language=take["model_language"],
                           instruct=take["direction"], temperature=.7, top_p=.9, max_new_tokens=260)
        torch.cuda.synchronize()
        result = save_wave(waves[0], rate, output / (take["language"] + ".wav"))
        memory = psutil.Process().memory_info()
        result.update(language=take["language"], spoken_text=take["spoken_text"],
                      render_seconds=round(time.monotonic()-started, 3),
                      cuda_peak_mb=round(torch.cuda.max_memory_allocated()/1024**2, 1),
                      peak_private_mb=round(getattr(memory,"peak_pagefile",memory.rss)/1024**2, 1))
        result["real_time_factor"] = result["render_seconds"] / result["duration_seconds"]
        results.append(result)
        write_json(output / "benchmark.json", {"version": 1, "settings": settings,
                   "conditioning": args.instruction_mode, "reference_mode": args.reference_mode,
                   "anchor_path": str(ANCHOR), "anchor_sha256": anchor_sha,
                   "package_versions": package_versions(), "takes": results, "complete": len(results)==len(takes)})
        print("VOICE_BENCHMARK_TAKE " + str(result), flush=True)


if __name__ == "__main__":
    main()
