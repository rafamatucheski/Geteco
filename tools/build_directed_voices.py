"""Planeja, testa e publica diálogo expressivo offline sem mexer nos WAVs antigos.

O padrão é um ensaio sem custo e com poucas dependências. Renderizar é explícito, incremental,
só local e com recursos limitados. Testes do VoiceDesign exigem audição antes da
publicação, porque direção por texto não garante gênero nem identidade.

Exemplos (use o ambiente Python opening_voice_design existente para renderizar):
  python tools/build_directed_voices.py --plan-out tmp/voice-plan.json
  python tools/build_directed_voices.py --render --speaker cida --limit 1 --device cpu
  python tools/build_directed_voices.py --publish-review tmp/voice-reviews.json
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path
import sys
import threading
import time

from voice_direction import (ROOT, MODEL, DirectionError, approved_manifest, plan_takes,
                             read_json, write_json, merge_reviews)

MODEL_CACHE = Path("D:/geteco/tools/opening_voice_models/hub") / ("models--Qwen--" + MODEL) / "snapshots"
DEFAULT_OUTPUT = ROOT / "audio/mission_voices/directed"


def model_snapshot(explicit=None):
    if explicit:
        path = Path(explicit).resolve()
    else:
        snapshots = sorted(path for path in MODEL_CACHE.glob("*") if path.is_dir())
        if len(snapshots) != 1:
            raise DirectionError("Select exactly one cached model using --model-path; no automatic download")
        path = snapshots[0]
    config = read_json(path / "config.json")
    if config.get("tts_model_type") != "voice_design":
        raise DirectionError("Selected model is not VoiceDesign")
    if not (path / "model.safetensors").is_file():
        raise DirectionError("Local model weights are missing")
    return path


def available_memory_mb():
    if os.name == "nt":
        import ctypes
        class Memory(ctypes.Structure):
            _fields_ = [("length", ctypes.c_ulong), ("load", ctypes.c_ulong)] + [
                (name, ctypes.c_ulonglong) for name in ("total", "free", "page_total", "page_free", "virtual_total", "virtual_free", "extended")]
        memory = Memory()
        memory.length = ctypes.sizeof(memory)
        if not ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(memory)):
            raise RuntimeError("Unable to inspect system memory budget")
        return memory.free / 1024**2
    import psutil
    return psutil.virtual_memory().available / 1024**2


def private_memory_mb():
    import psutil
    memory = psutil.Process().memory_info()
    return max(memory.rss, getattr(memory, "private", memory.rss)) / 1024**2


def install_budget(deadline_seconds, memory_mb, reserve_mb):
    """Vigia só este renderizador; nunca manda sinal ao processo de outro aplicativo."""
    import psutil
    process = psutil.Process()
    if os.name == "nt":
        process.nice(psutil.BELOW_NORMAL_PRIORITY_CLASS)
        # Impõe o limite de commit antes dos imports do modelo, além de vigiar a residência.
        import ctypes
        class BasicLimits(ctypes.Structure):
            _fields_ = [("process_time", ctypes.c_int64), ("job_time", ctypes.c_int64),
                        ("flags", ctypes.c_uint32), ("min_ws", ctypes.c_size_t), ("max_ws", ctypes.c_size_t),
                        ("active", ctypes.c_uint32), ("affinity", ctypes.c_size_t),
                        ("priority", ctypes.c_uint32), ("scheduling", ctypes.c_uint32)]
        class IOCounts(ctypes.Structure):
            _fields_ = [("field" + str(index), ctypes.c_uint64) for index in range(6)]
        class ExtendedLimits(ctypes.Structure):
            _fields_ = [("basic", BasicLimits), ("io", IOCounts), ("process_memory", ctypes.c_size_t),
                        ("job_memory", ctypes.c_size_t), ("peak_process", ctypes.c_size_t), ("peak_job", ctypes.c_size_t)]
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.CreateJobObjectW.argtypes = [ctypes.c_void_p, ctypes.c_wchar_p]
        kernel.CreateJobObjectW.restype = ctypes.c_void_p
        kernel.GetCurrentProcess.restype = ctypes.c_void_p
        kernel.SetInformationJobObject.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
        kernel.AssignProcessToJobObject.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        job = kernel.CreateJobObjectW(None, None)
        limits = ExtendedLimits()
        limits.basic.flags = 0x100  # JOB_OBJECT_LIMIT_PROCESS_MEMORY
        limits.process_memory = memory_mb * 1024**2
        if not job or not kernel.SetInformationJobObject(job, 9, ctypes.byref(limits), ctypes.sizeof(limits)):
            raise ctypes.WinError(ctypes.get_last_error())
        if not kernel.AssignProcessToJobObject(job, kernel.GetCurrentProcess()):
            raise ctypes.WinError(ctypes.get_last_error())
        global BUDGET_JOB
        BUDGET_JOB = job
    started = time.monotonic()
    def watch():
        while True:
            reason = ""
            if time.monotonic() - started > deadline_seconds:
                reason = "finite wall-time budget exceeded"
            elif private_memory_mb() > memory_mb:
                reason = "renderer memory budget exceeded"
            elif available_memory_mb() < reserve_mb:
                reason = "system free-memory reserve reached"
            if reason:
                print("VOICE_RENDER_STOP " + reason, flush=True)
                os._exit(3)
            time.sleep(1)
    threading.Thread(target=watch, daemon=True).start()


def safe_streaming_loader(torch, modeling_utils):
    """Evita reservar um segundo mapeamento safetensors do tamanho do modelo no Windows."""
    class TensorSlice:
        def __init__(self, archive, key): self.archive, self.key = archive, key
        def get_shape(self): return self.archive.header[self.key]["shape"]
        def get_dtype(self): return self.archive.header[self.key]["dtype"]
        def __getitem__(self, index): return self.archive.get_tensor(self.key)[index]
    class StreamingSafeOpen:
        def __init__(self, filename, framework, device="cpu"):
            if framework != "pt": raise ValueError("PyTorch checkpoint required")
            self.filename = filename
            self.device = "cuda:" + str(device) if isinstance(device, int) else device
            with open(filename, "rb") as file:
                size = int.from_bytes(file.read(8), "little")
                if not 0 < size < 16 * 1024**2: raise ValueError("Invalid checkpoint header")
                self.header = json.loads(file.read(size))
            self.offset, self.file_size = 8 + size, os.path.getsize(filename)
        def __enter__(self): return self
        def __exit__(self, *args): return False
        def metadata(self): return self.header.get("__metadata__")
        def keys(self): return [key for key in self.header if key != "__metadata__"]
        def get_slice(self, key): return TensorSlice(self, key)
        def get_tensor(self, key):
            description = self.header[key]
            dtype = modeling_utils.str_to_torch_dtype[description["dtype"]]
            begin, end = description["data_offsets"]
            count = 1
            for dimension in description["shape"]: count *= dimension
            item_size = torch.empty((), dtype=dtype).element_size()
            if begin < 0 or end < begin or self.offset + end > self.file_size or end - begin != count * item_size:
                raise ValueError("Invalid tensor bounds: " + key)
            tensor = torch.empty(count, dtype=dtype, device=self.device)
            if count:
                block = bytearray(min(end - begin, 8 * 1024**2))
                view = memoryview(block)
                with open(self.filename, "rb") as file:
                    file.seek(self.offset + begin)
                    for at in range(0, end - begin, len(block)):
                        chunk = view[:min(len(block), end - begin - at)]
                        if file.readinto(chunk) != len(chunk): raise EOFError(key)
                        first = at // item_size
                        tensor[first:first + len(chunk) // item_size].copy_(torch.frombuffer(chunk, dtype=dtype))
            return tensor.reshape(description["shape"])
    return StreamingSafeOpen


def usable_previous(previous, take):
    old = previous.get(take["signature"])
    if not old or old.get("status") not in ("review_required", "approved"):
        return None
    path = ROOT / old.get("path", "res://missing")[6:]
    if path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == old.get("audio_sha256"):
        return old
    return None


def take_path(output, take):
    return output / take["language"] / (take["source_key"] + "_" + take["signature"][:16] + ".wav")


def render(takes, snapshot, output, args):
    production_path = output / "production.json"
    previous_doc = read_json(production_path) if production_path.exists() else {"version": 1, "takes": []}
    previous = {take["signature"]: take for take in previous_doc["takes"]}
    pending = [take for take in takes if not usable_previous(previous, take)]
    if not pending:
        print(f"VOICE_RENDER_REUSED takes={len(takes)}", flush=True)
        return
    for take in pending:
        if take_path(output, take).exists():
            raise DirectionError("Existing audio without matching valid provenance; use another --take-index")
    # Este ambiente PyTorch instalado com CUDA consome ~2,45 GB de commit privado
    # antes dos pesos, mesmo com o modelo na CPU. Orça esse custo conhecido
    # das dependências mais uma pequena reserva de decodificação em vez de falhar no nativo.
    weight_mb = sum(path.stat().st_size for path in snapshot.rglob("*.safetensors")) / 1024**2
    weight_mb *= 2 if args.dtype == "float32" else 1  # o checkpoint em cache é BF16
    minimum_mb = weight_mb + 2800
    if args.memory_mb < minimum_mb:
        raise DirectionError(f"Cached model and installed dependencies need at least {minimum_mb:.0f}MB process budget")
    # O commit de DLL/privado é maior que a RAM residente neste build do Windows.
    # Estima pesos físicos + 1 GiB de runtime e impõe a memória livre real
    # durante carga/decodificação, em vez de somar commit à RAM física.
    if available_memory_mb() < weight_mb + 1024 + args.reserve_mb:
        raise DirectionError("Not enough free physical RAM for model/runtime plus desktop reserve")
    os.environ.update(HF_HUB_OFFLINE="1", TRANSFORMERS_OFFLINE="1", OMP_NUM_THREADS="2", MKL_NUM_THREADS="2")
    # As dependências só carregam depois de um pedido explícito de renderização.
    install_budget(args.timeout_seconds, args.memory_mb, args.reserve_mb)
    import numpy as np
    import soundfile as sf
    import torch
    from qwen_tts import Qwen3TTSModel
    import transformers.modeling_utils as modeling_utils
    torch.set_num_threads(2)
    torch.set_num_interop_threads(1)
    if args.device == "cuda":
        if not torch.cuda.is_available(): raise DirectionError("CUDA requested but unavailable; no CPU fallback")
        free, total = torch.cuda.mem_get_info()
        if free < (weight_mb + 600) * 1024**2: raise DirectionError("Insufficient free VRAM; leave other applications untouched")
        torch.cuda.set_per_process_memory_fraction(.65)
    output.mkdir(parents=True, exist_ok=True)
    print(f"VOICE_MODEL_LOADING device={args.device} dtype={args.dtype} takes={len(pending)} threads=2", flush=True)
    original_open = modeling_utils.safe_open
    original_warmup = modeling_utils.caching_allocator_warmup
    modeling_utils.safe_open = safe_streaming_loader(torch, modeling_utils)
    modeling_utils.caching_allocator_warmup = lambda *a, **kw: None
    try:
        model = Qwen3TTSModel.from_pretrained(str(snapshot), device_map="cpu" if args.device == "cpu" else "cuda:0",
                    dtype=getattr(torch, args.dtype), attn_implementation="sdpa", local_files_only=True, low_cpu_mem_usage=True)
    finally:
        modeling_utils.safe_open = original_open
        modeling_utils.caching_allocator_warmup = original_warmup
    supported = set(model.get_supported_languages() or [])
    if any(take["model_language"].lower() not in supported for take in pending):
        raise DirectionError("Cached model does not explicitly support the selected languages")
    versions = {name: importlib.metadata.version(name) for name in ("torch", "transformers", "qwen-tts", "soundfile")}
    for index, take in enumerate(pending):
        started = time.monotonic()
        settings = take["settings"]
        torch.manual_seed(settings["seed"])
        waves, rate = model.generate_voice_design(text=take["spoken_text"], language=take["model_language"],
                    instruct=take["direction"], **{name: settings[name] for name in ("temperature", "top_p", "do_sample", "max_new_tokens")})
        signal = np.asarray(waves[0], dtype=np.float32)
        if rate != 24000 or signal.ndim != 1 or not np.isfinite(signal).all():
            raise DirectionError("Unexpected/invalid generated audio format")
        active = np.flatnonzero(np.abs(signal) > .003)
        if not len(active): raise DirectionError("Synthesizer returned a silent take")
        signal = signal[max(0, int(active[0] - rate * .08)):min(len(signal), int(active[-1] + rate * .18))]
        peak = float(np.max(np.abs(signal)))
        if peak > .9: signal *= .9 / peak
        path = take_path(output, take)
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists():
            raise DirectionError("Existing audio without matching valid provenance; use another --take-index")
        # Grava uma vez. Um WAV parcial/de falha nunca vira tomada revisável.
        import tempfile
        with tempfile.NamedTemporaryFile(suffix=".wav", dir=path.parent, delete=False) as file:
            pending_path = Path(file.name)
        sf.write(pending_path, signal, rate, subtype="PCM_16")
        with pending_path.open("rb") as source, path.open("xb") as target:
            import shutil
            shutil.copyfileobj(source, target)
        pending_path.unlink()
        completed = {**take, "path": "res://" + path.relative_to(ROOT).as_posix(),
                     "status": "review_required", "audio_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                     "seconds": len(signal) / rate, "render_seconds": round(time.monotonic() - started, 3),
                     "sample_rate": rate, "channels": 1, "format": "PCM_16", "package_versions": versions,
                     "identity_guarantee": False, "review_checks_required": ["transcript", "language", "gender", "identity", "delivery", "technical_quality"]}
        import psutil
        memory = psutil.Process().memory_info()
        completed["peak_private_mb"] = round(getattr(memory, "peak_pagefile", memory.rss) / 1024**2, 1)
        completed["peak_resident_mb"] = round(getattr(memory, "peak_wset", memory.rss) / 1024**2, 1)
        previous[take["signature"]] = completed
        write_json(production_path, {"version": 1, "model": MODEL, "model_revision": snapshot.name,
                   "voice_cloning": False, "complete": False, "status": "auditions_require_listening",
                   "takes": [previous[key] for key in sorted(previous)]})
        print(f"VOICE_TAKE {index + 1}/{len(pending)} {take['character_id']} {take['language']} {completed['seconds']:.2f}s render={completed['render_seconds']}s", flush=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cast", type=Path, default=ROOT / "data/dialogue/voice-cast.json")
    parser.add_argument("--direction", type=Path, default=ROOT / "data/dialogue/voice-line-direction.json")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--model-path", type=Path)
    parser.add_argument("--languages", nargs="+", choices=("pt_BR", "en"), default=["pt_BR", "en"])
    parser.add_argument("--speaker", action="append", default=[])
    parser.add_argument("--line-key", action="append", default=[])
    parser.add_argument("--limit", type=int, help="Maximum canonical lines, before expanding languages")
    parser.add_argument("--take-index", type=int, default=0)
    parser.add_argument("--device", choices=("cpu", "cuda"), default="cpu")
    parser.add_argument("--dtype", choices=("bfloat16", "float32"), default="bfloat16",
                        help="CPU AVX2 needs float32 for practical speed; requires a larger explicit memory budget")
    parser.add_argument("--render", action="store_true")
    parser.add_argument("--plan-out", type=Path)
    parser.add_argument("--publish-review", type=Path)
    parser.add_argument("--timeout-seconds", type=int, default=900)
    parser.add_argument("--memory-mb", type=int, default=8000)
    parser.add_argument("--reserve-mb", type=int, default=3000)
    args = parser.parse_args(argv)
    output = args.output.resolve()
    if output != DEFAULT_OUTPUT.resolve():
        raise DirectionError("Output must be the separate audio/mission_voices/directed bank")
    if args.publish_review:
        if args.render: raise DirectionError("Render and review publication are separate operations")
        from directed_voice_inventory import inventory
        snapshot = model_snapshot(args.model_path)
        production = read_json(output / "production.json")
        combinations = {(take["settings"]["device"], take.get("take_index", 0), take["settings"]["dtype"]) for take in production["takes"]}
        combinations.add((args.device, args.take_index, args.dtype))
        current = []
        for device, take_index, dtype in sorted(combinations):
            current.extend(plan_takes(read_json(args.cast), read_json(args.direction), inventory(), ("pt_BR", "en"),
                                      model_revision=snapshot.name, device=device, take_index=take_index, dtype=dtype))
        prior_path = output / "reviews.json"
        if (output / "approved.json").exists() and not prior_path.exists():
            raise DirectionError("Historical review decisions are missing; restore reviews.json before publishing")
        prior = read_json(prior_path) if prior_path.exists() else {"reviews": []}
        reviews = merge_reviews(prior, read_json(args.publish_review), production, current)
        manifest = approved_manifest(production, reviews, current_plan=current)
        write_json(prior_path, reviews)
        write_json(output / "approved.json", manifest)
        print(json.dumps({"published": {k: len(v) for k, v in manifest["lines"].items()}}))
        return
    from directed_voice_inventory import inventory
    rows = inventory()
    if args.speaker: rows = [row for row in rows if row["persona"] in {name.lower() for name in args.speaker}]
    if args.line_key: rows = [row for row in rows if row["key"] in args.line_key]
    if args.limit is not None:
        if args.limit <= 0: raise DirectionError("--limit must be positive")
        rows = rows[:args.limit]
    if not rows: raise DirectionError("No canonical dialogue matched; nothing was rendered")
    snapshot = model_snapshot(args.model_path)
    takes = plan_takes(read_json(args.cast), read_json(args.direction), rows, args.languages,
                       model_revision=snapshot.name, device=args.device, take_index=args.take_index, dtype=args.dtype)
    if args.plan_out: write_json(args.plan_out, {"version": 1, "takes": takes})
    print(json.dumps({"mode": "render" if args.render else "dry_run", "lines": len(rows), "takes": len(takes),
          "characters": len({take["character_id"] for take in takes}), "characters_to_speak": sum(len(take["spoken_text"]) for take in takes),
          "provider": "local_qwen3_voice_design", "model_revision": snapshot.name,
          "audio_published": False, "identity_requires_listening": True}, ensure_ascii=False), flush=True)
    if args.render:
        if len(takes) > 12: raise DirectionError("Audition batch exceeds 12 takes; select a finite --speaker/--line-key/--limit batch")
        if not 30 <= args.timeout_seconds <= 1800 or not 1000 <= args.memory_mb <= 12288 or args.reserve_mb < 2048:
            raise DirectionError("Invalid desktop budget: 30..1800s, 1000..12288MB, reserve at least 2048MB")
        render(takes, snapshot, output, args)


if __name__ == "__main__":
    try:
        main()
    except (DirectionError, FileNotFoundError) as error:
        print("VOICE_PREFLIGHT_FAILED " + str(error), file=sys.stderr)
        sys.exit(2)
