"""Resumable anchored PT-BR/EN bank. Existing legacy/audio auditions are immutable.

Stages are explicit: plan, anchors, render, publish. A completed recording is not
an assertion of human artistic approval. The runtime manifest preserves that
distinction, along with each actor reference and actual synthesis configuration.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import time

from voice_direction import ROOT, DirectionError, digest, plan_takes, read_json, write_json
from voice_backend import (BASE_MODEL, LARGE_BASE_MODEL, DESIGN_MODEL, backend_settings, cached_snapshot,
                           condition_clone, load_model, package_versions, save_wave, synthesize_clone)
from build_directed_voices import install_budget

OUTPUT = ROOT / "audio/mission_voices/directed"
JESSICA = "2f74ccc16ed52b718b42204c49235f59574f5f599fab5aca4763f109dce41430"
ANCHOR_TEXT = "Eu ouvi o que você disse. Me dá um instante. Vou te explicar como a gente resolve isso."


def audio_valid(record):
    resource = record.get("path", "")
    if not resource.startswith("res://audio/mission_voices/directed/"):
        return False
    path = (ROOT / resource[6:]).resolve()
    try:
        path.relative_to(OUTPUT.resolve())
    except ValueError:
        return False
    return path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == record.get("audio_sha256")


def load_anchors():
    path = OUTPUT / "anchors.json"
    return read_json(path) if path.exists() else {"version": 1, "characters": {}}


def anchor_matches_spec(anchor, spec):
    return anchor.get("spec_signature", anchor.get("signature")) == spec["signature"] and audio_valid(anchor)


def anchor_plan(takes, design_settings):
    selected = {}
    for take in takes:
        if take["language"] != "pt_BR":
            continue
        identity = take["character_id"]
        if identity in selected:
            continue
        # Use only the stable character direction, not an arbitrary situation,
        # when designing the reusable fictional voice.
        voice = take["voice_profile"]
        text = voice.get("anchor_text_pt", "").strip()
        performance = voice.get("anchor_performance", "").strip()
        if not text or not performance:
            raise DirectionError("Missing authored reference script/performance: " + identity)
        direction = take["direction"].split("Scene performance overrides habitual emotion", 1)[0].strip()
        direction += " Reference scene performance: " + performance
        direction += " Read only the supplied words with native Brazilian pronunciation. Dry close microphone; no music or sound effects."
        spec = {"character_id": identity, "voice_gender": take["voice_gender"], "direction": direction,
                "text": text, "language": "pt_BR", "backend": design_settings,
                "seed": take["settings"]["seed"], "version": 1}
        spec["signature"] = digest(spec)
        selected[identity] = spec
    identities = sorted(identity for identity in selected if identity != "jessica")
    for at in range(0, len(identities), 4):
        group = identities[at:at+4]
        batch_id = digest([selected[identity]["signature"] for identity in group])
        for position, identity in enumerate(group):
            spec = selected[identity]
            spec.update(batch_id=batch_id, batch_seed=int(batch_id[:8], 16) % 2**31,
                        batch_position=position, batch_size=len(group))
            spec["signature"] = digest(spec)
    return selected


def clone_plan(takes, anchors, settings, instruction_mode, *, batch_size=1):
    if batch_size not in (1, 2, 4, 8):
        raise DirectionError("Supported deterministic batch sizes: 1, 2, 4, 8")
    result = []
    for take in takes:
        anchor = anchors.get(take["character_id"])
        if not anchor:
            raise DirectionError("Missing actor reference: " + take["character_id"])
        if anchor.get("voice_gender") != take["voice_gender"] or not audio_valid(anchor):
            raise DirectionError("Actor reference gender/provenance invalid: " + take["character_id"])
        # Hash every input actually fed to this backend; retain the original
        # authored plan signature separately rather than pretending Base=Design.
        spec = {"version": 1, "authored_signature": take["signature"], "backend": settings,
                "anchor_id": take["character_id"], "anchor_sha256": anchor["audio_sha256"],
                "anchor_text": anchor["text"], "instruction_mode": instruction_mode,
                "reference_mode": "speaker_embedding" if take["language"] == "en" else "icl",
                "non_streaming_mode": True, "temperature": .7, "top_p": .9,
                "max_new_tokens": take["settings"]["max_new_tokens"],
                "seed": take["settings"]["seed"]}
        result.append({**take, **spec, "signature": digest(spec),
                       "anchor_path": anchor["path"], "model": settings["model"],
                       "model_revision": settings["model_revision"], "status": "planned"})
    # Stable batches use similar utterance lengths, reducing padding. Membership
    # and sampling seed are signed because batching changes stochastic output.
    result.sort(key=lambda t: (len(t["spoken_text"]) // 40, t["character_id"], t["language"], t["source_key"]))
    for at in range(0, len(result), batch_size):
        batch = result[at:at+batch_size]
        batch_id = digest([batch_size, [t["signature"] for t in batch]])
        batch_seed = int(batch_id[:8], 16) % 2**31
        max_tokens = max(t["max_new_tokens"] for t in batch)
        for index, take in enumerate(batch):
            take.update(batch_id=batch_id, batch_seed=batch_seed, batch_position=index,
                        batch_size=len(batch), configured_batch_size=batch_size,
                        batch_max_new_tokens=max_tokens,
                        signature=digest([take["signature"], batch_id, batch_seed, index, max_tokens]))
    return result


def write_progress(stage, completed, total, current=None, started=None):
    value = {"version": 1, "stage": stage, "completed": completed, "total": total,
             "current": current, "updated_unix": round(time.time(), 3)}
    if started is not None:
        value["elapsed_seconds"] = round(time.monotonic()-started, 3)
    write_json(OUTPUT / "progress.json", value)
    print("VOICE_PROGRESS " + json.dumps(value, ensure_ascii=False), flush=True)


def complete_character_batches(takes, characters):
    groups = {t["batch_id"] for t in takes if t["character_id"] in characters}
    return [t for t in takes if t["batch_id"] in groups]


def repair_plan(current_takes, requests, backend):
    """Create only explicitly selected immutable alternatives; keep good takes."""
    batch_size = requests.get("batch_size", 1)
    if batch_size not in (1, 2, 4, 8):
        raise DirectionError("Retake batch size must be 1, 2, 4 or 8")
    current = {(t["source_key"], t["language"]): t for t in current_takes}
    result, seen = [], set()
    for request in requests.get("repairs", []):
        slot = request.get("source_key"), request.get("language")
        if slot in seen or slot not in current:
            raise DirectionError("Duplicate or unknown repair source/language")
        seen.add(slot)
        if not str(request.get("reason", "")).strip():
            raise DirectionError("A retake needs an explicit diagnostic reason")
        seed = request.get("seed")
        variant = request.get("variant")
        if not isinstance(seed, int) or isinstance(seed, bool) or not 0 <= seed < 2**31:
            raise DirectionError("A retake needs an explicit seed in 0..2^31-1")
        if not isinstance(variant, str) or not variant.strip():
            raise DirectionError("A retake needs an explicit variant identifier")
        original = current[slot]
        reference_mode = request.get("reference_mode", original["reference_mode"])
        if reference_mode not in ("icl", "speaker_embedding"):
            raise DirectionError("Retake reference_mode must be icl or speaker_embedding")
        suffix = str(request.get("direction_suffix", "")).strip()
        direction = original["direction"] + (" " + suffix if suffix else "")
        maximum_duration = request.get("max_duration_seconds")
        if maximum_duration is not None and (not isinstance(maximum_duration, (int, float)) or isinstance(maximum_duration, bool)
                                            or not math.isfinite(maximum_duration) or not 0 < maximum_duration <= 120):
            raise DirectionError("Retake timing window must be a finite positive duration")
        maximum_tokens = request.get("max_new_tokens", original["max_new_tokens"])
        if not isinstance(maximum_tokens, int) or isinstance(maximum_tokens, bool) or not 12 <= maximum_tokens <= 1200:
            raise DirectionError("Retake codec budget must be an integer in 12..1200; non-EOS completion is rejected")
        signed = {"pipeline": "anchored_repair_v1", "original_signature": original["signature"],
                  "seed": seed, "variant": variant, "backend": backend,
                  "direction": direction, "authored_direction": original["direction"], "direction_suffix": suffix,
                  "anchor_sha256": original["anchor_sha256"], "reference_mode": reference_mode,
                  "max_duration_seconds": maximum_duration, "max_new_tokens": maximum_tokens}
        signature = digest(signed)
        result.append({**original, "signature": signature, "repair_of": original["signature"],
                       "repair_recipe": signed, "repair_reason": request["reason"], "backend": backend,
                       "reference_mode": reference_mode,
                       "direction": direction, "max_duration_seconds": maximum_duration,
                       "max_new_tokens": maximum_tokens,
                       "model": backend["model"], "model_revision": backend["model_revision"],
                       "seed": seed, "settings": {**original["settings"], "seed": seed, "max_new_tokens": maximum_tokens},
                       "batch_id": signature, "batch_seed": seed,
                       "batch_size": 1, "batch_position": 0, "configured_batch_size": 1,
                       "batch_max_new_tokens": maximum_tokens})
    if not result:
        raise DirectionError("No explicit retakes requested")
    result.sort(key=lambda t: (len(t["spoken_text"])//40, t["character_id"], t["language"], t["source_key"]))
    budgets = {}
    for take in result:
        budgets.setdefault(take["max_new_tokens"], []).append(take)
    repair_groups = [items[at:at+batch_size] for _, items in sorted(budgets.items())
                     for at in range(0, len(items), batch_size)]
    for group in repair_groups:
        if len(group) < 2:
            continue
        shared_seed = requests.get("batch_seed")
        if not isinstance(shared_seed, int) or isinstance(shared_seed, bool) or not 0 <= shared_seed < 2**31:
            raise DirectionError("Batched retakes need an explicit shared batch_seed")
        if any(take["seed"] != shared_seed for take in group):
            raise DirectionError("Retake seeds must match their actual shared batch_seed")
        batch_id = digest(["anchored_repair_batch_v1", shared_seed, [take["repair_recipe"] for take in group]])
        max_tokens = max(take["max_new_tokens"] for take in group)
        for position, take in enumerate(group):
            recipe = {**take["repair_recipe"], "pipeline": "anchored_repair_v2", "batch_id": batch_id,
                      "batch_seed": shared_seed, "batch_position": position, "batch_size": len(group),
                      "batch_max_new_tokens": max_tokens}
            take.update(signature=digest(recipe), repair_recipe=recipe, batch_id=batch_id,
                        batch_seed=shared_seed, batch_position=position, batch_size=len(group),
                        configured_batch_size=batch_size, batch_max_new_tokens=max_tokens)
    return result


def validate_repair_targets(current_takes, requests, records, replacements):
    """A diagnostic belongs to specific bytes; it cannot reject a newer take."""
    by_slot = {(t["source_key"], t["language"]): t for t in current_takes}
    completed = {t["signature"]: t for t in records}
    alternatives = {(t["source_key"], t["language"]): t for t in replacements}
    for request in requests.get("repairs", []):
        slot = request["source_key"], request["language"]
        alternate = completed.get(alternatives[slot]["signature"])
        if alternate and audio_valid(alternate):
            continue  # Resuming this exact immutable alternative.
        original = completed.get(by_slot[slot]["signature"])
        expected_sha = request.get("supersedes_audio_sha256")
        if expected_sha and (not original or original.get("audio_sha256") != expected_sha or not audio_valid(original)):
            raise DirectionError("Retake diagnostic targets a different current audio SHA")
        if request.get("requires_missing") and original is not None:
            raise DirectionError("Missing-only production recipe would replace an existing recording")


def checkpoint_repair_selections(records):
    selection_path = OUTPUT / "repair-selections.json"
    previous = read_json(selection_path) if selection_path.exists() else {"version": 1, "repairs": []}
    merged = {take["repair_of"]: take for take in previous["repairs"]}
    for take in records:
        if not take.get("repair_of"):
            continue
        if (audio_valid(take) and take.get("timing_validation", {}).get("passed") is not False
                and take.get("generation_validation", {}).get("passed") is not False):
            merged[take["repair_of"]] = take
    write_json(selection_path, {"version": 1, "repairs": list(merged.values())})


def selected_repaired_plan(current_takes, selections):
    by_original = {t["repair_of"]: t for t in selections.get("repairs", [])}
    result = []
    for original in current_takes:
        repair = by_original.get(original["signature"])
        if repair:
            recipe = repair.get("repair_recipe", {})
            if digest(recipe) != repair.get("signature") or recipe.get("original_signature") != original["signature"]:
                raise DirectionError("Invalid signed repair selection")
            if any(repair.get(k) != recipe.get(k) for k in ("backend", "seed", "direction", "anchor_sha256", "reference_mode")):
                raise DirectionError("Repair parameters differ from its signed recipe")
            batch_fields = ("batch_id", "batch_seed", "batch_position", "batch_size", "batch_max_new_tokens")
            if any(k in recipe and repair.get(k) != recipe[k] for k in batch_fields):
                raise DirectionError("Repair batch differs from its signed recipe")
            expected_direction = original["direction"] + (" " + recipe["direction_suffix"] if recipe.get("direction_suffix") else "")
            if recipe.get("authored_direction") != original["direction"] or repair["direction"] != expected_direction:
                raise DirectionError("Repair omitted or replaced the authored performance direction")
            if repair.get("max_duration_seconds") != recipe.get("max_duration_seconds"):
                raise DirectionError("Repair timing window differs from its signed recipe")
            if repair.get("max_new_tokens") != recipe.get("max_new_tokens"):
                raise DirectionError("Repair codec budget differs from its signed recipe")
            if any(repair.get(k) != original.get(k) for k in ("source_key", "source", "persona", "spoken_text", "language",
                                                            "character_id", "voice_gender", "anchor_sha256")):
                raise DirectionError("Repair changed an authored word, actor or reference")
            # Use present publication blockers/cast metadata, not a historical
            # release state copied into the replacement recipe.
            repair = {**repair, "casting_blockers": original["casting_blockers"], "cast_revision": original.get("cast_revision")}
        result.append(repair or original)
    return result


def render_anchors(specs, args, design_snapshot, settings):
    document = load_anchors()
    anchors = document["characters"]
    valid = {identity for identity, spec in specs.items()
             if identity in anchors and anchor_matches_spec(anchors[identity], spec)}
    # Jessica's revised delivery is an actual prior fictional reference with an
    # exact transcript. Preserve and use it rather than redesigning her actor.
    jessica_spec = specs.get("jessica")
    if jessica_spec and "jessica" not in anchors:
        audition_path = OUTPUT / "production.json"
        auditions = read_json(audition_path).get("takes", []) if audition_path.exists() else []
        match = next((t for t in auditions if t["source_key"] == JESSICA and t["language"] == "pt_BR"
                      and t["signature"].startswith("7d8ae2517fa89f66") and audio_valid(t)), None)
        if match:
            anchors["jessica"] = {**jessica_spec, "text": match["spoken_text"], "path": match["path"],
                "audio_sha256": match["audio_sha256"], "duration_seconds": match["seconds"],
                "source": "reused_revised_fictional_audition", "source_signature": match["signature"],
                "source_backend": {"model": match["model"], "model_revision": match["model_revision"], "settings": match["settings"]},
                "artistic_review": "pending", "gender_validation": "authored_unverified"}
            write_json(OUTPUT / "anchors.json", document)
            valid.add("jessica")
    grouped = {}
    for spec in specs.values():
        grouped.setdefault(spec.get("batch_id", spec["signature"]), []).append(spec)
    pending = [sorted(group, key=lambda s: s.get("batch_position", 0)) for group in grouped.values()
               if any(spec["character_id"] not in valid for spec in group)]
    if not pending:
        write_progress("anchors_complete", len(specs), len(specs))
        return
    if args.limit:
        pending = pending[:args.limit]
    for group in pending:
        for spec in group:
            target = OUTPUT / "anchors" / (spec["character_id"] + "_" + spec["signature"][:16] + ".wav")
            if spec["character_id"] not in valid and target.exists():
                raise DirectionError("Existing actor reference has no matching valid provenance: " + str(target))
    install_budget(args.timeout_seconds, args.memory_mb, args.reserve_mb)
    model = load_model(design_snapshot, settings, vram_reserve_mb=args.vram_reserve_mb)
    import torch
    started = time.monotonic()
    for group in pending:
        at = time.monotonic()
        write_progress("anchors", len(valid), len(specs), [s["character_id"] for s in group], started)
        torch.manual_seed(group[0].get("batch_seed", group[0]["seed"]))
        waves, rate = model.generate_voice_design(text=[s["text"] for s in group], language=["Portuguese"]*len(group),
                                                  instruct=[s["direction"] for s in group], temperature=.7, top_p=.9, max_new_tokens=400)
        if len(waves) != len(group):
            raise DirectionError("Wrong number of generated actor references")
        for spec, wave in zip(group, waves):
            identity = spec["character_id"]
            if identity in valid:
                continue
            record = save_wave(wave, rate, OUTPUT / "anchors" / (identity + "_" + spec["signature"][:16] + ".wav"))
            anchors[identity] = {**spec, **record, "batch_render_seconds": round(time.monotonic()-at, 3),
                                 "source": "fictional_voice_design", "gender_validation": "authored_unverified",
                                 "package_versions": package_versions()}
            write_json(OUTPUT / "anchors.json", document)
            valid.add(identity)
        write_json(OUTPUT / "anchor-recordings.json", {"version": 1, "takes": [
            {**anchor, "spoken_text": anchor["text"]} for anchor in anchors.values()]})
    write_progress("anchors_batch_complete", len([k for k in specs if k in anchors]), len(specs), started=started)


def reference_retake_plan(specs, requests, settings):
    batch_size = requests.get("batch_size", 1)
    if batch_size not in (1, 2, 4):
        raise DirectionError("Actor reference retake batches must contain at most four items")
    planned, seen = [], set()
    for request in requests.get("anchors", []):
        identity = request.get("character_id")
        if identity not in specs or identity in seen:
            raise DirectionError("Unknown or duplicate actor reference retake")
        seen.add(identity)
        if not str(request.get("reason", "")).strip() or not str(request.get("variant", "")).strip():
            raise DirectionError("Actor reference retake needs reason and variant")
        seed = request.get("seed")
        if not isinstance(seed, int) or isinstance(seed, bool) or not 0 <= seed < 2**31:
            raise DirectionError("Actor reference retake needs explicit seed")
        spec = specs[identity]
        actual_direction = spec["direction"] + " " + str(request.get("direction_suffix", "")).strip()
        recipe = {"pipeline": "actor_reference_retake_v1", "spec_signature": spec["signature"],
                  "direction": actual_direction, "text": spec["text"], "seed": seed, "variant": request["variant"],
                  "backend": settings, "character_id": identity, "voice_gender": spec["voice_gender"]}
        planned.append((spec, request, recipe))
    planned.sort(key=lambda item: item[0]["character_id"])
    result = []
    for at in range(0, len(planned), batch_size):
        group = planned[at:at+batch_size]
        if len(group) > 1:
            seed = requests.get("batch_seed")
            if not isinstance(seed, int) or isinstance(seed, bool) or not 0 <= seed < 2**31:
                raise DirectionError("Batched actor alternatives need an explicit shared batch_seed")
            if any(recipe["seed"] != seed for _, _, recipe in group):
                raise DirectionError("Actor retake seeds must match the declared shared batch_seed")
            batch_id = digest(["actor_reference_batch_v1", seed, [recipe for _, _, recipe in group]])
            for position, (_, _, recipe) in enumerate(group):
                recipe.update(pipeline="actor_reference_retake_v2", batch_id=batch_id,
                              batch_seed=seed, batch_position=position, batch_size=len(group))
        for spec, request, recipe in group:
            signature = digest(recipe)
            result.append((spec, request, recipe, signature,
                           OUTPUT / "anchors" / (spec["character_id"] + "_" + signature[:16] + ".wav")))
    return result


def reanchor(specs, requests, args, snapshot, settings):
    document = load_anchors()
    planned = reference_retake_plan(specs, requests, settings)
    valid, groups = set(), {}
    for item in planned:
        spec, request, recipe, signature, target = item
        identity = spec["character_id"]
        groups.setdefault(recipe.get("batch_id", signature), []).append(item)
        if identity in document["characters"] and document["characters"][identity].get("signature") == signature and audio_valid(document["characters"][identity]):
            valid.add(signature)
            continue
        supersedes = request.get("supersedes_audio_sha256")
        if supersedes and document["characters"].get(identity, {}).get("audio_sha256") != supersedes:
            raise DirectionError("Actor reference retake targets a different current audio SHA")
        if target.exists():
            raise DirectionError("Existing actor alternative without valid provenance")
    pending = [group for group in groups.values() if any(item[3] not in valid for item in group)]
    if not pending:
        print("VOICE_REANCHOR_REUSED", flush=True)
        return
    install_budget(args.timeout_seconds, args.memory_mb, args.reserve_mb)
    model = load_model(snapshot, settings, vram_reserve_mb=args.vram_reserve_mb)
    import torch
    history_path = OUTPUT / "anchor-history.json"
    history = read_json(history_path) if history_path.exists() else {"version": 1, "references": []}
    started = time.monotonic()
    for index, group in enumerate(pending):
        write_progress("reanchor", index, len(pending), [item[0]["character_id"] for item in group], started)
        at = time.monotonic()
        torch.manual_seed(group[0][2]["seed"])
        waves, rate = model.generate_voice_design(text=[item[0]["text"] for item in group], language=["Portuguese"]*len(group),
                                                   instruct=[item[2]["direction"] for item in group],
                                                   temperature=.7, top_p=.9, max_new_tokens=400)
        if len(waves) != len(group):
            raise DirectionError("Wrong number of actor alternatives returned")
        for (spec, request, recipe, signature, target), wave in zip(group, waves):
            if signature in valid:
                continue
            record = save_wave(wave, rate, target)
            old = document["characters"].get(spec["character_id"])
            if old and not any(r.get("audio_sha256") == old["audio_sha256"] for r in history["references"]):
                history["references"].append(old)
                write_json(history_path, history)
            document["characters"][spec["character_id"]] = {**spec, **record, "signature": signature,
              "spec_signature": spec["signature"], "reference_retake_recipe": recipe,
              "direction": recipe["direction"], "seed": recipe["seed"], "batch_size": len(group),
              "batch_id": recipe.get("batch_id", signature), "batch_seed": recipe["seed"], "batch_position": recipe.get("batch_position", 0),
              "source": "fictional_voice_design_retake", "retake_reason": request["reason"],
              "previous_audio_sha256": old.get("audio_sha256") if old else None,
              "gender_validation": "authored_unverified", "render_seconds": round(time.monotonic()-at, 3),
              "package_versions": package_versions()}
            write_json(OUTPUT / "anchors.json", document)
            print("VOICE_REANCHORED " + spec["character_id"] + " " + record["audio_sha256"], flush=True)
    write_progress("reanchor_complete", len(pending), len(pending), started=started)


def render_bank(takes, args, snapshot, settings):
    path = OUTPUT / "cloned-production.json"
    document = read_json(path) if path.exists() else {"version": 1, "takes": []}
    previous = {t["signature"]: t for t in document["takes"]}
    valid = {t["signature"] for t in takes if t["signature"] in previous and audio_valid(previous[t["signature"]])}
    batches = {}
    for take in takes:
        batches.setdefault(take["batch_id"], []).append(take)
    pending = [sorted(batch, key=lambda take: take["batch_position"]) for batch in batches.values()
               if any(t["signature"] not in valid for t in batch)]
    # Keep deterministic membership while delivering cinematic/lead-character
    # coverage early enough for runtime and timing validation during production.
    pending.sort(key=lambda batch: (0 if any(t.get("section") == "opening_ferry" for t in batch) else
                                    1 if any(t["source_key"] == JESSICA for t in batch) else
                                    2 if any(t["character_id"] in ("cida", "dante", "civilian_reaction_female", "civilian_reaction_male") for t in batch) else 3))
    if args.limit:
        pending = pending[:args.limit]
    if not pending:
        write_progress("render_complete", len(takes), len(takes))
        return
    for batch in pending:
        for take in batch:
            target = OUTPUT / take["language"] / (take["source_key"] + "_" + take["signature"][:16] + ".wav")
            if take["signature"] not in valid and target.exists():
                raise DirectionError("Existing recording has no matching valid provenance: " + str(target))
    install_budget(args.timeout_seconds, args.memory_mb, args.reserve_mb)
    model = load_model(snapshot, settings, vram_reserve_mb=args.vram_reserve_mb)
    versions = package_versions()
    prompts = {}
    started = time.monotonic()
    for batch in pending:
        if getattr(args, "stop_file", None) and args.stop_file.exists():
            write_progress("render_paused_at_checkpoint", len(valid), len(takes), started=started)
            return
        for take in batch:
            identity = (take["anchor_id"], take["reference_mode"])
            if identity not in prompts:
                prompts[identity] = condition_clone(model, ROOT / take["anchor_path"][6:], take["anchor_text"],
                                                    x_vector_only=take["reference_mode"] == "speaker_embedding")
        at = time.monotonic()
        done = len(valid)
        write_progress("render", done, len(takes), batch[0]["batch_id"], started)
        waves, rate = synthesize_clone(model, [t["spoken_text"] for t in batch], [t["model_language"] for t in batch],
                       [prompts[(t["anchor_id"], t["reference_mode"])][0] for t in batch], [t["direction"] for t in batch],
                       instruction_mode=args.instruction_mode, seed=batch[0]["batch_seed"],
                       max_new_tokens=batch[0]["batch_max_new_tokens"])
        if len(waves) != len(batch):
            raise DirectionError("Synthesizer returned the wrong number of batch recordings")
        elapsed = round(time.monotonic()-at, 3)
        termination = getattr(model, "_directed_last_generation", None)
        if termination is not None and len(termination) != len(batch):
            raise DirectionError("Generation completion metadata does not match its batch")
        import torch
        resources = {"cuda_allocated_mb": round(torch.cuda.memory_allocated()/1024**2, 1),
                     "cuda_reserved_mb": round(torch.cuda.memory_reserved()/1024**2, 1),
                     "cuda_peak_allocated_mb": round(torch.cuda.max_memory_allocated()/1024**2, 1),
                     "batch_raw_audio_seconds": round(sum(len(wave)/rate for wave in waves), 3)}
        for position, (take, wave) in enumerate(zip(batch, waves)):
            if take["signature"] in valid:
                continue  # Resuming a partial batch preserves earlier immutable WAVs.
            # Reuse the resident speaker encoder as a measured consistency cue.
            # This score does not certify perceived gender or artistic delivery.
            similarity = None
            if len(wave) / rate >= 2:
                import numpy as np
                import torch.nn.functional as functional
                observed = model.model.extract_speaker_embedding(np.asarray(wave, dtype=np.float32), rate)
                reference = prompts[(take["anchor_id"], take["reference_mode"])][0].ref_spk_embedding
                similarity = {"method": "qwen_base_speaker_encoder_cosine",
                    "reference_audio_sha256": take["anchor_sha256"],
                    "cosine": round(float(functional.cosine_similarity(observed.float(), reference.float(), dim=0).item()), 4),
                    "human_listening": False}
            record = save_wave(wave, rate, OUTPUT / take["language"] / (take["source_key"] + "_" + take["signature"][:16] + ".wav"))
            if similarity is not None:
                record["speaker_similarity"] = similarity
            if take.get("max_duration_seconds") is not None:
                record["timing_validation"] = {"maximum_seconds": take["max_duration_seconds"],
                    "actual_seconds": record["duration_seconds"], "passed": record["duration_seconds"] <= take["max_duration_seconds"],
                    "method": "complete_waveform_duration_no_truncation_or_speed_change"}
            if termination is not None:
                record["generation_validation"] = termination[position]
            previous[take["signature"]] = {**take, **record, "status": "generated",
                  "batch_render_seconds": elapsed, "package_versions": versions,
                  "render_resources": resources,
                  "identity_conditioning": "persistent_reference_audio_and_speaker_embedding",
                  "transcription_validation": {"status": "pending"}, "gender_validation": "reference_authored_unverified"}
            document["takes"] = [previous[key] for key in sorted(previous)]
            write_json(path, document)
            valid.add(take["signature"])
        checkpoint_repair_selections([previous[take["signature"]] for take in batch if take["signature"] in previous])
    done = len(valid)
    write_progress("render_complete" if done == len(takes) else "render_batch_complete", done, len(takes), started=started)


def apply_content_audits(records, reports, decisions=None):
    """Join immutable audio/text tuples; never transfer a verdict to a retake."""
    audited = {}
    for report in reports:
        for row in report.get("takes", []):
            slot = row.get("waveform", {}).get("sha256"), row.get("language"), row.get("expected")
            audited[slot] = (row, report.get("asr_model"), report.get("report_sha256"))
    adjudicated = {}
    for decision in (decisions or {}).get("decisions", []):
        if decision.get("decision") not in ("lexically_equivalent", "reject") or not str(decision.get("reason", "")).strip():
            raise DirectionError("Content adjudication needs an explicit equivalence/reject reason")
        slot = decision.get("audio_sha256"), decision.get("language"), decision.get("expected")
        if slot in adjudicated or not all(slot):
            raise DirectionError("Content adjudication needs one exact audio/language/text tuple")
        adjudicated[slot] = decision
    result = []
    for record in records:
        record = {**record}
        slot = record.get("audio_sha256"), record.get("language"), record.get("spoken_text")
        matching = audited.get(slot)
        if matching:
            row, model, report_sha = matching
            if row.get("technical_errors"):
                record["technical_validation"] = {"passed": False, "errors": row["technical_errors"]}
            if "asr" in row:
                asr = row["asr"]
                verdict = {"status": "review_required" if asr.get("review") else "automated_clear",
                           "method": model, "report_sha256": report_sha, "audio_sha256": slot[0],
                           "transcript": asr.get("transcript"), "word_similarity": asr.get("word_similarity"),
                           "human_listening": False, "artistic_approval": False}
                decision = adjudicated.get(slot)
                if decision:
                    verdict.update(status="lexically_equivalent" if decision["decision"] == "lexically_equivalent" else "failed",
                                   adjudication=decision)
                record["transcription_validation"] = verdict
        result.append(record)
    return result


def runtime_manifest(takes, records, *, expected_total=None, require_audit=False):
    known = {t["signature"]: t for t in records}
    result = {"version": 1, "lines": {"pt_BR": {}, "en": {}}, "artistic_review": "pending",
              "coverage": {"expected": len(takes) if expected_total is None else expected_total,
                           "planned_scope": len(takes), "generated": 0, "blocked": [],
                           "content_review": [], "content_pending": [], "content_checked": 0}}
    fields = ("path", "spoken_text", "signature", "character_id", "persona", "source", "source_key",
              "voice_gender", "language", "duration_seconds", "audio_sha256", "technical_validation",
              "artistic_review", "transcription_validation", "anchor_id", "anchor_sha256", "model", "model_revision",
              "status", "authored_signature", "cast_revision", "gender_validation", "instruction_mode", "reference_mode",
              "speaker_similarity", "timing_validation", "generation_validation")
    for take in takes:
        record = known.get(take["signature"])
        if not record:
            continue
        if take.get("casting_blockers"):
            result["coverage"]["blocked"].append({"key": take["source_key"], "language": take["language"], "reasons": take["casting_blockers"]})
            continue
        if any(record.get(k) != take.get(k) for k in ("source_key", "persona", "source", "character_id", "spoken_text", "voice_gender",
                "language", "anchor_sha256", "model", "model_revision", "backend", "reference_mode", "instruction_mode", "direction")):
            raise DirectionError("Recording provenance differs from the current plan")
        if not audio_valid(record) or not record.get("technical_validation", {}).get("passed"):
            raise DirectionError("Missing or changed technically validated recording")
        if record.get("generation_validation", {}).get("passed") is False:
            result["coverage"]["blocked"].append({"key": take["source_key"], "language": take["language"], "reasons": ["Generation stopped without its natural EOS token"]})
            continue
        if record.get("timing_validation", {}).get("passed") is False:
            result["coverage"]["blocked"].append({"key": take["source_key"], "language": take["language"], "reasons": ["Complete waveform exceeds its signed timing window"]})
            continue
        content_state = record.get("transcription_validation", {}).get("status", "pending")
        if content_state in ("failed", "review_required"):
            result["coverage"]["content_review"].append({"key": take["source_key"], "language": take["language"], "status": content_state})
            continue
        if content_state in ("automated_clear", "lexically_equivalent"):
            result["coverage"]["content_checked"] += 1
        else:
            result["coverage"]["content_pending"].append({"key": take["source_key"], "language": take["language"]})
            if require_audit:
                continue
        result["lines"][take["language"]][take["source_key"]] = {k: record[k] for k in fields if k in record}
        result["coverage"]["generated"] += 1
    result["coverage"]["complete"] = result["coverage"]["generated"] == result["coverage"]["expected"]
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=("plan", "anchors", "reanchor", "render", "repair", "publish"))
    parser.add_argument("--limit", type=int, help="Optional maximum synthesis batches; no global take cap")
    parser.add_argument("--character", action="append", default=[])
    parser.add_argument("--instruction-mode", choices=("reference", "experimental_text"), default="experimental_text")
    parser.add_argument("--batch-size", type=int, choices=(1, 2, 4, 8), default=8)
    parser.add_argument("--repair-requests", type=Path)
    parser.add_argument("--resume-requests", type=Path, help="Frozen selective production recipes; preserve every other original batch")
    parser.add_argument("--stop-file", type=Path, help="Stop cooperatively between complete synthesis batches when this file exists")
    parser.add_argument("--repair-model", choices=("base", "base_large"), default="base")
    parser.add_argument("--audit", type=Path, action="append", default=[], help="Read-only ASR report snapshot; may be repeated")
    parser.add_argument("--content-decisions", type=Path, help="Explicit lexical-equivalence/reject decisions keyed by audio SHA, language and expected text")
    parser.add_argument("--require-audit", action="store_true", help="Exclude unaudited takes from the runtime manifest")
    parser.add_argument("--timeout-seconds", type=int, default=7200)
    parser.add_argument("--memory-mb", type=int, default=10000)
    parser.add_argument("--reserve-mb", type=int, default=3072)
    parser.add_argument("--vram-reserve-mb", type=int, default=768)
    args = parser.parse_args()
    if not 30 <= args.timeout_seconds <= 86400 or not 5000 <= args.memory_mb <= 16000 or args.reserve_mb < 2048 or args.vram_reserve_mb < 512:
        raise DirectionError("Invalid finite production resource budget")
    if args.limit is not None and args.limit < 1:
        raise DirectionError("Batch size must be positive")
    from directed_voice_inventory import inventory
    design_snapshot, base_snapshot = cached_snapshot(DESIGN_MODEL), cached_snapshot(BASE_MODEL)
    design = backend_settings(DESIGN_MODEL, design_snapshot, "nf4")
    base = backend_settings(BASE_MODEL, base_snapshot, "none")
    authored = plan_takes(read_json(ROOT / "data/dialogue/voice-cast.json"),
                          read_json(ROOT / "data/dialogue/voice-line-direction.json"), inventory(),
                          device="cuda", model_revision=design_snapshot.name)
    expected_total = len(authored)
    characters = set(args.character)
    if characters and not characters.issubset({t["character_id"] for t in authored}):
        raise DirectionError("No matching cast identities")
    specs = anchor_plan(authored, design)
    if args.stage == "plan":
        write_json(OUTPUT / "anchored-plan.json", {"version": 1, "authored_takes": authored, "anchors": specs,
                   "clone_backend": base, "instruction_mode": args.instruction_mode})
        print(json.dumps({"canonical_lines": len(authored)//2, "takes": len(authored), "actors": len(specs)}))
        return
    if args.stage == "anchors":
        scoped_specs = specs
        if characters:
            groups = {s.get("batch_id", s["signature"]) for k, s in specs.items() if k in characters}
            scoped_specs = {k: s for k, s in specs.items() if s.get("batch_id", s["signature"]) in groups}
        render_anchors(scoped_specs, args, design_snapshot, design)
        return
    if args.stage == "reanchor":
        if args.repair_requests is None:
            raise DirectionError("Reanchor requires --repair-requests listing selected character IDs")
        reanchor(specs, read_json(args.repair_requests), args, design_snapshot, design)
        return
    anchors = load_anchors()["characters"]
    for identity, spec in specs.items():
        if identity not in anchors or not anchor_matches_spec(anchors[identity], spec):
            raise DirectionError("Missing or stale actor reference: " + identity)
    takes = clone_plan(authored, anchors, base, args.instruction_mode, batch_size=args.batch_size)
    if args.stage == "render":
        if args.resume_requests:
            requests = read_json(args.resume_requests)
            replacements = repair_plan(takes, requests, base)
            records_path = OUTPUT / "cloned-production.json"
            records = read_json(records_path)["takes"] if records_path.exists() else []
            validate_repair_targets(takes, requests, records, replacements)
            selections_path = OUTPUT / "repair-selections.json"
            selected = read_json(selections_path)["repairs"] if selections_path.exists() else []
            merged = {t["repair_of"]: t for t in selected + replacements}
            takes = selected_repaired_plan(takes, {"repairs": list(merged.values())})
        if characters:
            takes = complete_character_batches(takes, characters)
        render_bank(takes, args, base_snapshot, base)
    elif args.stage == "repair":
        if args.repair_requests is None:
            raise DirectionError("Repair requires --repair-requests with source_key, language, seed, variant and reason")
        repair_snapshot = cached_snapshot(LARGE_BASE_MODEL) if args.repair_model == "base_large" else base_snapshot
        repair_backend = backend_settings(LARGE_BASE_MODEL, repair_snapshot, "nf4") if args.repair_model == "base_large" else base
        requests = read_json(args.repair_requests)
        replacements = repair_plan(takes, requests, repair_backend)
        records_path = OUTPUT / "cloned-production.json"
        records = read_json(records_path)["takes"] if records_path.exists() else []
        selections_path = OUTPUT / "repair-selections.json"
        effective = selected_repaired_plan(takes, read_json(selections_path)) if selections_path.exists() else takes
        validate_repair_targets(effective, requests, records, replacements)
        render_bank(replacements, args, repair_snapshot, repair_backend)
        selection_path = OUTPUT / "repair-selections.json"
        previous = read_json(selection_path) if selection_path.exists() else {"version": 1, "repairs": []}
        merged = {take["repair_of"]: take for take in previous["repairs"]}
        # Only choose alternatives that actually completed with matching bytes.
        completed = {take["signature"]: take for take in read_json(OUTPUT / "cloned-production.json")["takes"]}
        for replacement in replacements:
            if replacement["signature"] in completed and audio_valid(completed[replacement["signature"]]) and completed[replacement["signature"]].get("timing_validation", {}).get("passed") is not False and completed[replacement["signature"]].get("generation_validation", {}).get("passed") is not False:
                merged[replacement["repair_of"]] = replacement
            elif replacement["signature"] in completed:
                print("VOICE_REPAIR_NOT_SELECTED " + replacement["signature"] + " timing or natural EOS requirement not met", flush=True)
        write_json(selection_path, {"version": 1, "repairs": list(merged.values())})
    else:
        if characters:
            takes = [t for t in takes if t["character_id"] in characters]
        records = read_json(OUTPUT / "cloned-production.json")["takes"]
        selections_path = OUTPUT / "repair-selections.json"
        if selections_path.exists():
            takes = selected_repaired_plan(takes, read_json(selections_path))
        reports = [{**read_json(path), "report_sha256": hashlib.sha256(path.read_bytes()).hexdigest()} for path in args.audit]
        records = apply_content_audits(records, reports, read_json(args.content_decisions) if args.content_decisions else None)
        manifest = runtime_manifest(takes, records, expected_total=expected_total, require_audit=args.require_audit)
        mix_path = OUTPUT / "mix.json"
        mix = read_json(mix_path) if mix_path.exists() else {"takes": []}
        by_audio = {r["audio_sha256"]: r for r in mix["takes"]}
        manifest["mix_policy"] = mix.get("policy", {})
        pending_mix = []
        for language, entries in manifest["lines"].items():
            for key, entry in list(entries.items()):
                measured = by_audio.get(entry["audio_sha256"])
                if measured is None:
                    pending_mix.append({"key": key, "language": language})
                    del entries[key]
                    manifest["coverage"]["generated"] -= 1
                    continue
                entry.update({field: measured[field] for field in ("playback_gain_db", "input_lufs", "input_true_peak_db", "mix_method", "mix_policy")})
        manifest["coverage"]["pending_mix"] = pending_mix
        manifest["coverage"]["complete"] = manifest["coverage"]["generated"] == expected_total
        manifest["cast_sha256"] = hashlib.sha256((ROOT / "data/dialogue/voice-cast.json").read_bytes()).hexdigest()
        manifest["direction_sha256"] = hashlib.sha256((ROOT / "data/dialogue/voice-line-direction.json").read_bytes()).hexdigest()
        write_json(OUTPUT / "runtime.json", manifest)
        print(json.dumps(manifest["coverage"], ensure_ascii=False))


if __name__ == "__main__":
    main()
