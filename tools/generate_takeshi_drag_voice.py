"""Six isolated, offline Takeshi takes; publishing is separate from synthesis.

Uses the already installed VoiceDesign/Whisper environments and cached weights.
Never calls the global Harbor generator or the external Edge speech service.
"""
from __future__ import annotations

import argparse
import ast
import difflib
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import time
import unicodedata
import wave

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "activities/desert_drag/TakeshiDragController.gd"
OUTPUT = ROOT / "evidence/takeshi-voice"
ASSETS = ROOT / "audio/mission_voices/takeshi_drag"
MANIFEST = ROOT / "audio/mission_voices/recordings.json"
MODEL_ROOT = Path("D:/geteco/tools/opening_voice_models")
WHISPER = MODEL_ROOT / "whisper/models--Systran--faster-whisper-small/snapshots/536b0662742c02347bc0e980a01041f333bce120"
SEED = 13739
os.environ.update(HF_HOME=str(MODEL_ROOT), HF_HUB_OFFLINE="1", TRANSFORMERS_OFFLINE="1", OMP_NUM_THREADS="1", PYTHONDONTWRITEBYTECODE="1")


def digest(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write_json(path: Path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def authored():
    source = SOURCE.read_bytes()
    text = source.decode("utf-8-sig")
    intro = json.loads(re.search(r'const INTRO := ("[^\n]*")', text)[1])
    victory = json.loads(re.search(r'const VICTORY := ("[^\n]*")', text)[1])
    pairs = re.findall(r'var words := ("[^"\n]*") if[^\n]+ else ("[^"\n]*")', text)
    if len(pairs) != 2:
        raise RuntimeError("Expected exactly two fixed Takeshi dialogue branches")
    lines = [intro, victory] + [json.loads(item) for pair in pairs for item in pair]
    names = ["intro", "victory", "rematch_win", "loss", "supra_gift", "katana_gift"]
    return digest(source), [dict(id=name, persona="takeshi", text=line, key=digest(("takeshi|" + line).encode())) for name, line in zip(names, lines)]


def profile():
    # Read the authored description without importing Torch or allocating GPU.
    tree = ast.parse((ROOT / "tools/generate_harbor_story_voices.py").read_text(encoding="utf-8"))
    assignments = {node.targets[0].id: node.value for node in tree.body if isinstance(node, ast.Assign) and isinstance(node.targets[0], ast.Name)}
    base = ast.literal_eval(assignments["BASE"])
    voices = assignments["VOICES"]
    for key, value in zip(voices.keys, voices.values):
        if ast.literal_eval(key) == "takeshi":
            return base + ast.literal_eval(value.right)
    raise RuntimeError("Authored Takeshi profile not found")


def prepare():
    source_hash, rows = authored()
    plan = dict(model="Qwen3-TTS VoiceDesign", language="pt-BR", offline=True, voice_cloning=False,
                source_sha256=source_hash, profile=profile(), seed=SEED, lines=rows)
    plan_path = OUTPUT / "plan.json"
    if plan_path.exists() and read_json(plan_path) != plan:
        raise RuntimeError("Existing plan differs; preserve it and choose a new output directory")
    write_json(plan_path, plan)
    print("TAKESHI_VOICE_PREPARED", len(rows), "profile_seed", SEED, flush=True)


def checked_plan():
    plan = read_json(OUTPUT / "plan.json")
    source_hash, rows = authored()
    if source_hash != plan["source_sha256"] or rows != plan["lines"] or profile() != plan["profile"]:
        raise RuntimeError("Takeshi dialogue/profile changed after preparation; refusing stale publication")
    return plan


def bounded_gpu_commit(local):
    """Keep desktop limits while allowing Windows' CUDA backing commitment.

    The reusable generator defaults to 6000 MiB of private commitment. With
    this cached model Windows exhausts it on the first CUDA kernel, despite
    3656 MiB of live GPU tensors. This isolated six-line job uses an 8192 MiB
    private cap only when at least 10 GiB of physical RAM are available.
    GPU 60%, resident 2048 MiB, one CPU thread and low priority stay unchanged.
    """
    import ctypes
    class MemoryStatus(ctypes.Structure):
        _fields_ = [("length", ctypes.c_uint32), ("load", ctypes.c_uint32)] + [(name, ctypes.c_uint64) for name in
                    ("total_phys", "avail_phys", "total_page", "avail_page", "total_virtual", "avail_virtual", "extended")]
    status = MemoryStatus()
    status.length = ctypes.sizeof(status)
    if not ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(status)) or status.avail_phys < 10 * 1024**3:
        raise MemoryError("The bounded GPU generation requires at least 10 GiB of available RAM")
    class BasicLimits(ctypes.Structure):
        _fields_ = [("process_time", ctypes.c_int64), ("job_time", ctypes.c_int64), ("flags", ctypes.c_uint32),
                    ("min_working", ctypes.c_size_t), ("max_working", ctypes.c_size_t), ("active", ctypes.c_uint32),
                    ("affinity", ctypes.c_size_t), ("priority", ctypes.c_uint32), ("scheduling", ctypes.c_uint32)]
    class IOCounts(ctypes.Structure):
        _fields_ = [("count" + str(index), ctypes.c_uint64) for index in range(6)]
    class ExtendedLimits(ctypes.Structure):
        _fields_ = [("basic", BasicLimits), ("io", IOCounts), ("process_memory", ctypes.c_size_t),
                    ("job_memory", ctypes.c_size_t), ("peak_process", ctypes.c_size_t), ("peak_job", ctypes.c_size_t)]
    limits = ExtendedLimits()
    limits.basic.flags = 0x100
    limits.process_memory = 8192 * 1024**2
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.SetInformationJobObject.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    if not kernel.SetInformationJobObject(local.DESKTOP_JOB, 9, ctypes.byref(limits), ctypes.sizeof(limits)):
        raise ctypes.WinError(ctypes.get_last_error())
    local.PRIVATE_LIMIT_MB = 8192
    print("TAKESHI_VOICE_DESKTOP_BUDGET", json.dumps({"available_ram_mib": status.avail_phys / 1024**2,
          "private_limit_mib": 8192, "resident_limit_mib": local.RESIDENT_LIMIT_MB, "threads": 1}), flush=True)


def generate(seed_offset=0):
    plan = checked_plan()
    codes = OUTPUT / "codes"
    codes.mkdir(exist_ok=True)
    # Import reuses the existing bounded loader; its main() is never called.
    import generate_harbor_story_voices as local
    import numpy as np
    import torch
    from qwen_tts.inference.qwen3_tts_tokenizer import Qwen3TTSTokenizer
    bounded_gpu_commit(local)

    previous_path = OUTPUT / "codes.json"
    report = read_json(previous_path) if previous_path.exists() else {"profile": plan["profile"], "seed": SEED, "lines": []}
    completed = {row["key"]: row for row in report["lines"]}
    missing = []
    for row in plan["lines"]:
        path = codes / (row["key"] + ".npy")
        if path.exists():
            if row["key"] not in completed or digest(path.read_bytes()) != completed[row["key"]]["codes_sha256"]:
                raise RuntimeError("Unverified existing take preserved: " + str(path))
        else:
            missing.append(row)
    if not missing:
        print("TAKESHI_VOICE_ALREADY_GENERATED", len(completed), flush=True)
        return
    cached = next((MODEL_ROOT / "hub/models--Qwen--Qwen3-TTS-12Hz-1.7B-VoiceDesign/snapshots").iterdir())
    torch.set_num_threads(1)
    torch.cuda.set_per_process_memory_fraction(.60)
    free_bytes, total_bytes = torch.cuda.mem_get_info()
    print("TAKESHI_VOICE_LOADING", json.dumps({"free_gpu_mib": free_bytes / 1024**2, "gpu_budget_mib": total_bytes * .60 / 1024**2, "missing": len(missing)}), flush=True)
    if free_bytes < total_bytes * .60:
        raise RuntimeError("GPU has insufficient free memory for the existing bounded voice profile")
    original_open = local.modeling_utils.safe_open
    original_warmup = local.modeling_utils.caching_allocator_warmup
    original_tokenizer_descriptor = Qwen3TTSTokenizer.__dict__["from_pretrained"]
    class DeferredTokenizer:
        device = "deferred_to_separate_cpu_process"
        def decode(self, _codes):
            raise RuntimeError("GPU phase must only produce codes; decode in the separate CPU phase")
    def defer_tokenizer(_cls, _path, *args, **kwargs):
        return DeferredTokenizer()
    local.modeling_utils.safe_open = local.StreamingSafeOpen
    local.modeling_utils.caching_allocator_warmup = lambda *args, **kwargs: None
    Qwen3TTSTokenizer.from_pretrained = classmethod(defer_tokenizer)
    try:
        model = local.Qwen3TTSModel.from_pretrained(str(cached), device_map="cuda:0", dtype=torch.bfloat16,
                                                   attn_implementation="sdpa", local_files_only=True, low_cpu_mem_usage=True)
    finally:
        local.modeling_utils.safe_open = original_open
        local.modeling_utils.caching_allocator_warmup = original_warmup
        Qwen3TTSTokenizer.from_pretrained = original_tokenizer_descriptor
    torch.cuda.empty_cache()
    print("TAKESHI_VOICE_LOADED", json.dumps({"gpu_allocated_mib": torch.cuda.memory_allocated() / 1024**2,
                                              "gpu_reserved_mib": torch.cuda.memory_reserved() / 1024**2,
                                              "private_mib": local.private_memory_mb(),
                                              "decoder_device": str(model.model.speech_tokenizer.device)}), flush=True)
    budget = local.DesktopBudget()
    for row in missing:
        torch.manual_seed(SEED + seed_offset)
        began = time.monotonic()
        # Same tokenization/options as Qwen3TTSModel.generate_voice_design;
        # hold no waveform decoder while the text/codec generator is resident.
        inputs = model._tokenize_texts([model._build_assistant_text(row["text"])])
        instructions = [model._tokenize_texts([model._build_instruct_text(plan["profile"])])[0]]
        options = model._merge_generate_kwargs(max_new_tokens=360, temperature=.7, top_p=.9,
                                               logits_processor=local.LogitsProcessorList([budget]))
        sequences, _ = model.model.generate(input_ids=inputs, instruct_ids=instructions,
                                            languages=["Portuguese"], non_streaming_mode=True, **options)
        code_values = sequences[0].detach().cpu().numpy()
        if not code_values.size or code_values.ndim != 2:
            raise RuntimeError("Empty or malformed generated codec sequence")
        path = codes / (row["key"] + ".npy")
        np.save(path, code_values, allow_pickle=False)
        take = dict(row, synthesis_text=row["text"], synthesis_seed=SEED + seed_offset,
                    codes_path=str(path.relative_to(ROOT)).replace("\\", "/"), code_frames=int(code_values.shape[0]),
                    generation_seconds=time.monotonic() - began, codes_sha256=digest(path.read_bytes()))
        completed[row["key"]] = take
        report["lines"] = [completed[item["key"]] for item in plan["lines"] if item["key"] in completed]
        report["complete"] = len(completed) == len(plan["lines"])
        write_json(previous_path, report)
        print("TAKESHI_VOICE_CODES", json.dumps({"id": row["id"], "frames": take["code_frames"], "generation_seconds": take["generation_seconds"], "private_mib": local.private_memory_mb()}), flush=True)


def decode(device="cpu"):
    plan = checked_plan()
    codes = read_json(OUTPUT / "codes.json")
    if not codes.get("complete") or len(codes["lines"]) != 6:
        raise RuntimeError("All six codec takes are required before starting the CPU decoder")
    import generate_harbor_story_voices as local
    import numpy as np
    import soundfile as sf
    import torch
    from qwen_tts.inference.qwen3_tts_tokenizer import Qwen3TTSTokenizer
    torch.set_num_threads(1)
    if device.startswith("cuda"):
        torch.cuda.set_per_process_memory_fraction(.60)
    cached = next((MODEL_ROOT / "hub/models--Qwen--Qwen3-TTS-12Hz-1.7B-VoiceDesign/snapshots").iterdir())
    original_open = local.modeling_utils.safe_open
    original_warmup = local.modeling_utils.caching_allocator_warmup
    local.modeling_utils.safe_open = local.StreamingSafeOpen
    local.modeling_utils.caching_allocator_warmup = lambda *args, **kwargs: None
    try:
        decoder = Qwen3TTSTokenizer.from_pretrained(str(cached / "speech_tokenizer"), device_map=device, dtype=torch.bfloat16,
                                                    attn_implementation="sdpa", local_files_only=True, low_cpu_mem_usage=True)
    finally:
        local.modeling_utils.safe_open = original_open
        local.modeling_utils.caching_allocator_warmup = original_warmup
    takes = OUTPUT / "takes"
    takes.mkdir(exist_ok=True)
    previous = read_json(OUTPUT / "generation.json") if (OUTPUT / "generation.json").exists() else {"lines": []}
    completed = {row["key"]: row for row in previous["lines"]}
    report = {"profile": plan["profile"], "seed": SEED, "decoder_device": device, "lines": []}
    began = time.monotonic()
    for row in codes["lines"]:
        if time.monotonic() - began > 600:
            raise TimeoutError("Six-take CPU decoding exceeded ten minutes")
        source = ROOT / row["codes_path"]
        if digest(source.read_bytes()) != row["codes_sha256"]:
            raise RuntimeError("Generated codes changed before waveform reconstruction")
        path = takes / (row["key"] + ".wav")
        if path.exists():
            existing = completed.get(row["key"], {})
            if digest(path.read_bytes()) != existing.get("wav_sha256") or row["codes_sha256"] != existing.get("codes_sha256"):
                raise RuntimeError("Unverified reconstructed take preserved: " + str(path))
            report["lines"].append(existing)
            continue
        code_values = torch.from_numpy(np.load(source, allow_pickle=False))
        waves, rate = decoder.decode([{"audio_codes": code_values}])
        signal = np.asarray(waves[0], dtype=np.float32)
        if not np.all(np.isfinite(signal)):
            raise RuntimeError("Non-finite waveform for " + row["id"])
        active = np.flatnonzero(np.abs(signal) > .004)
        if not len(active):
            raise RuntimeError("Silent take for " + row["id"])
        signal = signal[max(0, int(active[0] - rate * .08)):min(len(signal), int(active[-1] + rate * .16))]
        peak = float(np.max(np.abs(signal)))
        if peak > .9:
            signal *= .9 / peak
        sf.write(path, signal, rate, subtype="PCM_16")
        take = dict(row, path=str(path.relative_to(ROOT)).replace("\\", "/"), seconds=len(signal) / rate,
                    sample_rate=rate, peak=float(np.max(np.abs(signal))), rms=float(np.sqrt(np.mean(signal**2))),
                    wav_sha256=digest(path.read_bytes()))
        report["lines"].append(take)
        report["complete"] = len(report["lines"]) == 6
        write_json(OUTPUT / "generation.json", report)
        local.check_desktop_memory()
        print("TAKESHI_VOICE_TAKE", json.dumps({"id": row["id"], "seconds": take["seconds"], "private_mib": local.private_memory_mb()}), flush=True)
    report["complete"] = len(report["lines"]) == 6
    write_json(OUTPUT / "generation.json", report)


def words(text):
    plain = "".join(char for char in unicodedata.normalize("NFD", text.lower()) if unicodedata.category(char) != "Mn")
    return "".join(char if char.isalnum() else " " for char in plain).split()


def audit():
    checked_plan()
    generated = read_json(OUTPUT / "generation.json")
    if not generated.get("complete"):
        raise RuntimeError("Generation has not completed; no partial manifest will be published")
    from faster_whisper import WhisperModel
    model = WhisperModel(str(WHISPER), device="cpu", compute_type="int8", cpu_threads=1, num_workers=1, local_files_only=True)
    report = {"method": "Offline Whisper small int8, CPU thread 1; finite six-take audit", "lines": [],
              "limitations": "Transcript and waveform checks do not replace listening or certify acting/voice continuity."}
    previous = read_json(OUTPUT / "audit.json") if (OUTPUT / "audit.json").exists() else {"lines": []}
    completed = {row["key"]: row for row in previous["lines"]}
    began = time.monotonic()
    for row in generated["lines"]:
        if time.monotonic() - began > 600:
            raise TimeoutError("Voice transcript audit exceeded ten minutes")
        path = ROOT / row["path"]
        if digest(path.read_bytes()) != row["wav_sha256"]:
            raise RuntimeError("Generated take changed before audit: " + row["id"])
        if row["wav_sha256"] == completed.get(row["key"], {}).get("wav_sha256"):
            report["lines"].append(completed[row["key"]])
            continue
        segments, _ = model.transcribe(str(path), language="pt", beam_size=5, best_of=1, temperature=0,
                                       vad_filter=False, condition_on_previous_text=False,
                                       initial_prompt="Dante, Takeshi, Supra, katana, Ammu-Nation.")
        transcript = " ".join(segment.text.strip() for segment in segments)
        similarity = difflib.SequenceMatcher(None, words(row["text"]), words(transcript)).ratio()
        missing_core_words = [word for word in ["honra", "subestimei", "carro", "tesouro", "familia"]
                              if row["id"] == "victory" and word not in words(transcript)]
        with wave.open(str(path), "rb") as audio:
            valid_format = audio.getnchannels() == 1 and audio.getsampwidth() == 2 and audio.getframerate() == row["sample_rate"]
        entry = dict(row, transcript=transcript, similarity=similarity, format_valid=valid_format,
                     missing_core_words=missing_core_words,
                     review_required=not valid_format or bool(missing_core_words) or similarity < .90 or not .7 < row["seconds"] < 28 or row["rms"] < .006)
        report["lines"].append(entry)
        write_json(OUTPUT / "audit.json", report)
        print("TAKESHI_VOICE_AUDIT", json.dumps({"id": row["id"], "similarity": similarity, "review_required": entry["review_required"], "transcript": transcript}, ensure_ascii=False), flush=True)
    write_json(OUTPUT / "audit.json", report)


def publish(reviewed_ids, pending_pronunciation_review):
    plan = checked_plan()
    review = read_json(OUTPUT / "audit.json")
    if set(reviewed_ids) != {row["id"] for row in plan["lines"]}:
        raise RuntimeError("Explicit transcript/voice review is required for all six take IDs")
    pending = set(filter(None, pending_pronunciation_review))
    if pending not in [set(), {"victory"}]:
        raise RuntimeError("Only the documented victory pronunciation ambiguity can remain pending")
    if len(review["lines"]) != 6 or any(row["review_required"] and row["id"] not in pending for row in review["lines"]):
        raise RuntimeError("Undocumented flagged or incomplete take audit cannot publish")
    for row in review["lines"]:
        if not row["format_valid"] or not .7 < row["seconds"] < 28 or row["rms"] < .006:
            raise RuntimeError("Invalid audio cannot publish with a pronunciation review exception")
        if row["id"] in pending:
            opinion = read_json(OUTPUT / "victory-second-opinion.json")
            if opinion["wav_sha256"] != row["wav_sha256"]:
                raise RuntimeError("The pending take lacks its independent unprompted transcript")
    for row in review["lines"]:
        if digest((ROOT / row["path"]).read_bytes()) != row["wav_sha256"]:
            raise RuntimeError("Audited take changed: " + row["id"])
    ASSETS.mkdir(parents=True, exist_ok=True)
    for row in review["lines"]:
        destination = ASSETS / (row["key"] + ".wav")
        if destination.exists() and digest(destination.read_bytes()) != row["wav_sha256"]:
            raise RuntimeError("Different production asset preserved: " + str(destination))
        if not destination.exists():
            shutil.copyfile(ROOT / row["path"], destination)
    # Read current bytes only after asset verification. Retain every foreign key;
    # refuse the write if another session changes the source in this interval.
    original = MANIFEST.read_bytes()
    original_hash = digest(original)
    manifest = json.loads(original.decode("utf-8-sig"))
    additions = {row["key"]: "res://audio/mission_voices/takeshi_drag/" + row["key"] + ".wav" for row in review["lines"]}
    for key, path in additions.items():
        if key in manifest and manifest[key] != path:
            raise RuntimeError("A recording for this exact dialogue already exists; preserved " + key)
    merged = dict(manifest, **additions)
    encoded = (json.dumps(merged, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    if digest(MANIFEST.read_bytes()) != original_hash:
        raise RuntimeError("Concurrent recording manifest change detected; no shared write performed")
    # Exclusive OS handle closes the last compare/write race on Windows.
    import ctypes
    import msvcrt
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.CreateFileW.argtypes = [ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p]
    kernel.CreateFileW.restype = ctypes.c_void_p
    handle = kernel.CreateFileW(str(MANIFEST), 0xC0000000, 0, None, 3, 0x80, None)
    if handle == ctypes.c_void_p(-1).value:
        raise ctypes.WinError(ctypes.get_last_error())
    descriptor = msvcrt.open_osfhandle(handle, os.O_RDWR | os.O_BINARY)
    with os.fdopen(descriptor, "r+b") as output:
        if digest(output.read()) != original_hash:
            raise RuntimeError("Concurrent manifest change under lock; preserved newer version")
        backup = OUTPUT / ("recordings-before-" + original_hash + ".json")
        if not backup.exists():
            backup.write_bytes(original)
        output.seek(0)
        output.write(encoded)
        output.truncate()
        output.flush()
        os.fsync(output.fileno())
    write_json(ASSETS / "production.json", dict(plan, verified_lines=review["lines"], manifest_before_sha256=original_hash,
                                                 manifest_after_sha256=digest(encoded), complete=True,
                                                 pronunciation_review_pending=sorted(pending),
                                                 review_limitations="ASR and waveform checks only; no human listening or voice continuity approval."))
    print("TAKESHI_VOICE_PUBLISHED", len(additions), "retained_existing_keys", len(manifest), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["prepare", "generate", "decode", "audit", "publish"])
    parser.add_argument("--reviewed-ids", default="")
    parser.add_argument("--decode-device", choices=["cpu", "cuda:0"], default="cpu")
    parser.add_argument("--seed-offset", type=int, choices=[0, 17], default=0)
    parser.add_argument("--pending-pronunciation-review", default="")
    args = parser.parse_args()
    {"prepare": prepare, "generate": lambda: generate(args.seed_offset), "decode": lambda: decode(args.decode_device), "audit": audit, "publish": lambda: publish(args.reviewed_ids.split(","), args.pending_pronunciation_review.split(","))}[args.action]()
