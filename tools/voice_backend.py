"""Local Qwen backends shared by finite benchmarks and resumable production.

No model imports, CUDA allocation or network traffic happen on import. Numerical
configuration is explicit and belongs in recording signatures.
"""
from __future__ import annotations

import hashlib
import importlib.metadata
import os
from pathlib import Path
import time

from voice_direction import DirectionError, ROOT, read_json

CACHE = Path("D:/geteco/tools/opening_voice_models/hub")
BASE_MODEL = "Qwen3-TTS-12Hz-0.6B-Base"
LARGE_BASE_MODEL = "Qwen3-TTS-12Hz-1.7B-Base"
DESIGN_MODEL = "Qwen3-TTS-12Hz-1.7B-VoiceDesign"
QUANT_SKIP = ["code_predictor", "speaker_encoder", "codec_head", "text_projection", "lm_head"]


def generation_termination(sequences, eos_token_id, maximum_steps):
    result = []
    for tokens in sequences:
        observed = eos_token_id in tokens
        steps = tokens.index(eos_token_id)+1 if observed else len(tokens)
        result.append({"method": "talker_generate_token_ids", "eos_observed": observed,
                       "generated_steps": steps, "maximum_steps": maximum_steps,
                       "hit_limit_without_eos": not observed and len(tokens) >= maximum_steps,
                       "passed": observed})
    return result


def cached_snapshot(name, revision=None):
    snapshots = CACHE / ("models--Qwen--" + name) / "snapshots"
    choices = [snapshots / revision] if revision else sorted(snapshots.glob("*"))
    choices = [p for p in choices if (p / "model.safetensors").is_file()]
    if len(choices) != 1:
        raise DirectionError("Select one complete cached model revision: " + name)
    return choices[0]


def backend_settings(model, snapshot, quantization="none", device="cuda"):
    if model not in (BASE_MODEL, LARGE_BASE_MODEL, DESIGN_MODEL) or quantization not in ("none", "nf4", "int8"):
        raise DirectionError("Unsupported model/quantization")
    if device != "cuda":
        raise DirectionError("Accelerated production requires explicit CUDA, no slow CPU fallback")
    return {"model": model, "model_revision": snapshot.name, "device": device,
            "dtype": "bfloat16", "quantization": quantization,
            "quantization_skip_modules": QUANT_SKIP if quantization != "none" else [],
            "attention": "sdpa", "threads": 2, "audio_decode_batch_size": 1}


def load_model(snapshot, settings, *, vram_reserve_mb=768):
    """Keep tiny autoregressive codec predictor/encoder out of quantization."""
    os.environ.update(HF_HUB_OFFLINE="1", TRANSFORMERS_OFFLINE="1", OMP_NUM_THREADS="2", MKL_NUM_THREADS="2")
    import torch
    from qwen_tts import Qwen3TTSModel
    from qwen_tts.core.models.modeling_qwen3_tts import Qwen3TTSTokenizer
    from transformers import BitsAndBytesConfig
    import transformers.modeling_utils as modeling_utils
    from build_directed_voices import safe_streaming_loader
    torch.set_num_threads(2)
    torch.set_num_interop_threads(1)
    if not torch.cuda.is_available():
        raise DirectionError("CUDA unavailable; no fallback")
    free, total = torch.cuda.mem_get_info()
    expected_mb = (2750 if settings["model"] == BASE_MODEL else 2900)
    if settings["quantization"] == "none" and settings["model"] != BASE_MODEL:
        expected_mb = 4850
    if free / 1024**2 < expected_mb + vram_reserve_mb:
        raise DirectionError(f"GPU needs {expected_mb + vram_reserve_mb:.0f} MiB free including reserve; has {free / 1024**2:.0f}")
    # Hard allocator ceiling is based on actual free memory and leaves desktop
    # headroom. It does not evict or terminate another application.
    torch.cuda.set_per_process_memory_fraction(min(.8, (free - vram_reserve_mb * 1024**2) / total))
    kwargs = dict(device_map="cuda:0", dtype=torch.bfloat16, attn_implementation="sdpa",
                  local_files_only=True, low_cpu_mem_usage=True)
    quant = settings["quantization"]
    if quant != "none":
        kwargs["quantization_config"] = BitsAndBytesConfig(
            load_in_4bit=quant == "nf4", load_in_8bit=quant == "int8",
            bnb_4bit_quant_type="nf4", bnb_4bit_use_double_quant=True,
            bnb_4bit_compute_dtype=torch.bfloat16, llm_int8_skip_modules=QUANT_SKIP)
    started = time.monotonic()
    print(f"VOICE_BACKEND_LOAD {settings}", flush=True)
    original_open, original_warmup = modeling_utils.safe_open, modeling_utils.caching_allocator_warmup
    original_tokenizer_loader = Qwen3TTSTokenizer.__dict__["from_pretrained"]
    def unquantized_tokenizer(cls, path, *args, **tokenizer_kwargs):
        tokenizer_kwargs.pop("quantization_config", None)
        return original_tokenizer_loader.__func__(cls, path, *args, **tokenizer_kwargs)
    Qwen3TTSTokenizer.from_pretrained = classmethod(unquantized_tokenizer)
    modeling_utils.safe_open = safe_streaming_loader(torch, modeling_utils)
    modeling_utils.caching_allocator_warmup = lambda *args, **kwargs: None
    try:
        model = Qwen3TTSModel.from_pretrained(str(snapshot), **kwargs)
    finally:
        modeling_utils.safe_open, modeling_utils.caching_allocator_warmup = original_open, original_warmup
        Qwen3TTSTokenizer.from_pretrained = original_tokenizer_loader
    torch.cuda.synchronize()
    # Autoregressive text/codec generation benefits from batches; the waveform
    # decoder has very large high-rate intermediate tensors. Decode one item at
    # a time to avoid multiplying those activations by the TTS batch size.
    original_decode = model.model.speech_tokenizer.decode
    def sequential_decode(codes, **decode_kwargs):
        if not isinstance(codes, list) or len(codes) < 2:
            return original_decode(codes, **decode_kwargs)
        print(f"VOICE_CODEC_DECODE items={len(codes)} batch_size=1", flush=True)
        waves, sample_rate = [], None
        for item in codes:
            decoded, rate = original_decode([item], **decode_kwargs)
            if sample_rate is not None and rate != sample_rate:
                raise DirectionError("Codec returned inconsistent sample rates")
            waves.extend(decoded)
            sample_rate = rate
        return waves, sample_rate
    model.model.speech_tokenizer.decode = sequential_decode
    original_generate = model.model.talker.generate
    def observed_generate(*generate_args, **generate_kwargs):
        generated = original_generate(*generate_args, **generate_kwargs)
        model._directed_last_generation = generation_termination(
            generated.sequences.detach().cpu().tolist(), model.model.config.talker_config.codec_eos_token_id,
            generate_kwargs.get("max_new_tokens", 0))
        return generated
    model.model.talker.generate = observed_generate
    print(f"VOICE_BACKEND_READY load_seconds={time.monotonic()-started:.3f} allocated_mb={torch.cuda.memory_allocated()/1024**2:.1f}", flush=True)
    return model


def condition_clone(model, anchor_path, anchor_text, *, x_vector_only=False):
    import soundfile as sf
    audio, rate = sf.read(anchor_path, dtype="float32", always_2d=False)
    if audio.ndim != 1 or not anchor_text.strip():
        raise DirectionError("Anchor must be mono with its exact transcript")
    return model.create_voice_clone_prompt(ref_audio=(audio, rate), ref_text=anchor_text,
                                           x_vector_only_mode=x_vector_only)


def synthesize_clone(model, text, language, prompt, direction, *, instruction_mode, seed,
                     max_new_tokens=700, temperature=.7):
    """Base supports acoustic reference; text instruction is explicitly experimental.

    Its low-level API accepts instruct_ids with a clone prompt, but the published
    Base capability table does not promise instruction control. Do not label an
    experimental sample as proven expressive merely because it generated audio.
    """
    import torch
    if instruction_mode not in ("reference", "experimental_text"):
        raise DirectionError("Choose an explicit clone conditioning mode")
    kwargs = {}
    if instruction_mode == "experimental_text":
        directions = direction if isinstance(direction, list) else [direction]
        kwargs["instruct_ids"] = model._tokenize_texts([model._build_instruct_text(item) for item in directions])
    torch.manual_seed(seed)
    return model.generate_voice_clone(text=text, language=language, voice_clone_prompt=prompt,
                                      non_streaming_mode=True, temperature=temperature,
                                      top_p=.9, max_new_tokens=max_new_tokens, **kwargs)


def save_wave(signal, rate, path):
    """Immutable PCM publication; return objective format checks, never listening."""
    import numpy as np
    import soundfile as sf
    import tempfile
    import shutil
    signal = np.asarray(signal, dtype=np.float32)
    if rate != 24000 or signal.ndim != 1 or not np.isfinite(signal).all():
        raise DirectionError("Invalid model waveform")
    active = np.flatnonzero(np.abs(signal) > .003)
    if not len(active):
        raise DirectionError("Silent model waveform")
    signal = signal[max(0, int(active[0]-rate*.08)):min(len(signal), int(active[-1]+rate*.18))]
    peak = float(np.max(np.abs(signal)))
    if peak > .9:
        signal *= .9 / peak
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        raise DirectionError("Refusing to overwrite an existing recording: " + str(path))
    with tempfile.NamedTemporaryFile(suffix=".wav", dir=path.parent, delete=False) as file:
        pending = Path(file.name)
    try:
        sf.write(pending, signal, rate, subtype="PCM_16")
        with pending.open("rb") as source, path.open("xb") as destination:
            shutil.copyfileobj(source, destination)
    finally:
        pending.unlink(missing_ok=True)
    return {"path": "res://" + path.relative_to(ROOT).as_posix(),
            "audio_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "duration_seconds": len(signal) / rate, "sample_rate": rate,
            "channels": 1, "format": "PCM_16", "peak": float(np.max(np.abs(signal))),
            "technical_validation": {"passed": True, "checks": ["finite_audio", "non_silent", "mono_pcm16_24khz", "peak_below_full_scale"]},
            "artistic_review": "pending"}


def package_versions():
    return {name: importlib.metadata.version(name) for name in
            ("torch", "transformers", "qwen-tts", "bitsandbytes", "soundfile")}
