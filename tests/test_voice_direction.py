"""Testes de regressão offline de elenco e portões de liberação; sem síntese nem carga de modelo."""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from voice_direction import (MODEL, REVIEW_CHECKS, DirectionError, approved_manifest,
                             canonical_key, plan_takes, resolve_character, merge_reviews, write_json)
import build_directed_voices as builder


class DirectedVoiceContracts(unittest.TestCase):
    def test_metadata_retries_temporary_windows_reader_lock(self):
        import os
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "production.json"
            original_replace = os.replace
            attempts = []
            def transient(source, destination):
                attempts.append(1)
                if len(attempts) == 1:
                    raise PermissionError("Concurrent read-only audit")
                original_replace(source, destination)
            with patch("os.replace", side_effect=transient), patch("time.sleep") as wait:
                write_json(target, {"takes": ["completed"]})
            self.assertEqual(json.loads(target.read_text()), {"takes": ["completed"]})
            self.assertEqual(len(attempts), 2)
            wait.assert_called_once_with(.05)

    def test_persistent_metadata_lock_preserves_recoverable_checkpoint(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "production.json"
            target.write_text('{"takes": []}')
            with patch("os.replace", side_effect=PermissionError("Persistent lock")) as replace, patch("time.sleep"):
                with self.assertRaises(PermissionError):
                    write_json(target, {"takes": ["completed"]})
            self.assertEqual(replace.call_count, 40)
            self.assertEqual(json.loads(target.read_text()), {"takes": []})
            pending = list(Path(directory).glob("*.pending"))
            self.assertEqual(len(pending), 1)
            self.assertEqual(json.loads(pending[0].read_text()), {"takes": ["completed"]})

    def setUp(self):
        self.row = {"persona": "cida", "text": "Vai devagar, moço.", "section": "sewer"}
        self.row["key"] = canonical_key(self.row["persona"], self.row["text"])
        self.cast = {"schema_version": 1, "personas": {"cida": {
            "id": "cida", "default_character": "cida", "gender": "female",
            "direction": {"pt_BR": "A guarded woman protecting her shelter; brief and dry.",
                          "en": "A guarded woman protecting her shelter; brief and dry."},
            "voice": {"provider": "qwen3_voice_design", "model": MODEL, "identity": "cida"}}}}
        self.direction = {"version": 1, "lines": [{"key": self.row["key"], "speaker": "cida",
            "source": self.row["text"], "spoken_pt": "Vai devagar, moço.", "spoken_en": "Easy, mister.",
            "intent": "Defend a boundary", "performance_prompt": "Quiet warning. Stress easy; stay wary."}]}

    def plan(self):
        return plan_takes(self.cast, self.direction, [self.row], model_revision="cached-sha")

    def test_distinct_languages_share_canonical_source_and_actor(self):
        pt, en = self.plan()
        self.assertEqual([pt["spoken_text"], en["spoken_text"]], ["Vai devagar, moço.", "Easy, mister."])
        self.assertEqual(pt["source_key"], en["source_key"])
        self.assertEqual(pt["character_id"], en["character_id"])
        self.assertNotEqual(pt["signature"], en["signature"])
        self.assertIn("woman", pt["direction"])
        self.assertIn("Brazilian Portuguese", pt["direction"])

    def test_unknown_persona_never_becomes_default_man(self):
        self.cast["personas"] = {}
        with self.assertRaisesRegex(DirectionError, "No explicit cast"):
            self.plan()

    def test_unknown_gender_blocks_render(self):
        self.cast["personas"]["cida"]["gender"] = "unknown"
        with self.assertRaisesRegex(DirectionError, "gender"):
            self.plan()

    def test_missing_translation_never_speaks_portuguese_in_english(self):
        del self.direction["lines"][0]["spoken_en"]
        with self.assertRaisesRegex(DirectionError, "Missing authored text"):
            self.plan()

    def test_changed_source_cannot_reuse_an_old_direction_key(self):
        self.direction["lines"][0]["source"] = "Outra fala."
        with self.assertRaisesRegex(DirectionError, "mismatch"):
            self.plan()

    def test_direction_affects_take_signature_and_reruns_are_stable(self):
        before = self.plan()
        self.assertEqual(before, self.plan())
        self.direction["lines"][0]["performance_prompt"] = "An urgent warning, louder, then catch breath."
        self.assertNotEqual(before[0]["signature"], self.plan()[0]["signature"])

    def test_missing_or_duplicate_line_direction_is_an_error(self):
        self.direction["lines"].append(copy.deepcopy(self.direction["lines"][0]))
        with self.assertRaisesRegex(DirectionError, "Duplicate direction"):
            self.plan()
        self.direction["lines"] = []
        with self.assertRaisesRegex(DirectionError, "Missing authored line"):
            self.plan()

    def test_homonyms_use_specific_context_and_line_key_precedence(self):
        profile = self.cast["personas"]["cida"]
        other = {"id": "cida_other", "sections": ["sewer"],
                 "voice": {**profile["voice"], "identity": "cida_other"}}
        profile["variants"] = [other]
        self.assertEqual(self.plan()[0]["character_id"], "cida_other")
        specific = {"id": "cida_specific", "line_keys": [self.row["key"]],
                    "voice": {**profile["voice"], "identity": "cida_specific"}}
        profile["variants"].append(specific)
        self.assertEqual(self.plan()[0]["character_id"], "cida_specific")

    def test_ambiguous_homonym_is_rejected(self):
        self.cast["personas"]["cida"]["variants"] = [{"id": "a", "sections": ["sewer"]},
                                                       {"id": "b", "sections": ["sewer"]}]
        with self.assertRaisesRegex(DirectionError, "Ambiguous"):
            self.plan()

    def test_mismatched_assigned_identity_is_rejected(self):
        self.cast["personas"]["cida"]["voice"]["identity"] = "dona_cida"
        with self.assertRaisesRegex(DirectionError, "identity differs"):
            self.plan()

    def review_fixture(self, root):
        take = self.plan()[0]
        path = root / "audio/mission_voices/directed/pt_BR/a.wav"
        path.parent.mkdir(parents=True)
        path.write_bytes(b"test reviewed bytes")
        take.update(path="res://audio/mission_voices/directed/pt_BR/a.wav", status="review_required",
                    audio_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
        review = {"reviews": [{"signature": take["signature"], "decision": "approved", "reviewer": "Casting review",
                               "checks": {name: True for name in REVIEW_CHECKS}}]}
        return {"takes": [take]}, review, path

    def test_no_audio_is_published_without_listening_review(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            production, review, _ = self.review_fixture(root)
            self.assertEqual(approved_manifest(production, {"reviews": []}, current_plan=self.plan(), root=root)["lines"]["pt_BR"], {})
            review["reviews"][0]["checks"]["gender"] = False
            with self.assertRaisesRegex(DirectionError, "checks must pass"):
                approved_manifest(production, review, current_plan=self.plan(), root=root)

    def test_publish_verified_bytes_with_exact_authored_subtitle(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            production, review, path = self.review_fixture(root)
            manifest = approved_manifest(production, review, current_plan=self.plan(), root=root)
            take = manifest["lines"]["pt_BR"][self.row["key"]]
            self.assertEqual(take["spoken_text"], "Vai devagar, moço.")
            self.assertEqual(take["persona"], "cida")
            path.write_bytes(b"different take")
            with self.assertRaisesRegex(DirectionError, "missing or changed"):
                approved_manifest(production, review, current_plan=self.plan(), root=root)

    def test_review_cannot_publish_legacy_or_external_path(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            production, review, _ = self.review_fixture(root)
            production["takes"][0]["path"] = "res://audio/mission_voices/old.wav"
            with self.assertRaisesRegex(DirectionError, "outside"):
                approved_manifest(production, review, current_plan=self.plan(), root=root)

    def test_changed_cast_or_direction_invalidates_prior_approval(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            production, review, _ = self.review_fixture(root)
            self.direction["lines"][0]["spoken_en"] = "Slow down, mister."
            self.cast["personas"]["cida"]["direction"]["pt_BR"] = "A different actor with a louder performance."
            with self.assertRaisesRegex(DirectionError, "stale"):
                approved_manifest(production, review, current_plan=self.plan(), root=root)

    def test_unresolved_character_binding_blocks_publication(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.cast["personas"]["cida"]["casting_blockers"] = ["Visual actor gender is not bound"]
            production, review, _ = self.review_fixture(root)
            with self.assertRaisesRegex(DirectionError, "binding is unresolved"):
                approved_manifest(production, review, current_plan=self.plan(), root=root)

    def test_incremental_render_reuses_verified_take_without_loading_model(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            production, _, _ = self.review_fixture(root)
            output = root / "audio/mission_voices/directed"
            (output / "production.json").write_text(json.dumps(production), encoding="utf-8")
            with patch.object(builder, "ROOT", root), patch.object(builder, "available_memory_mb", side_effect=AssertionError("No model budget needed")):
                builder.render(self.plan()[:1], root / "model", output, None)

    def test_untracked_existing_wav_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            output = root / "audio/mission_voices/directed"
            take = self.plan()[0]
            path = builder.take_path(output, take)
            path.parent.mkdir(parents=True)
            path.write_bytes(b"another session owns this take")
            with self.assertRaisesRegex(DirectionError, "Existing audio"):
                builder.render([take], root / "model", output, None)
            self.assertEqual(path.read_bytes(), b"another session owns this take")

    def test_review_batches_preserve_previous_approvals_and_explicit_rejection_removes(self):
        pt, en = self.plan()
        production = {"takes": [pt, en]}
        first = {"reviews": [{"signature": pt["signature"], "decision": "approved"}]}
        second = {"reviews": [{"signature": en["signature"], "decision": "approved"}]}
        merged = merge_reviews(first, second, production, self.plan())
        self.assertEqual(sum(row["decision"] == "approved" for row in merged["reviews"]), 2)
        rejected = {"reviews": [{"signature": pt["signature"], "decision": "rejected"}]}
        merged = merge_reviews(merged, rejected, production, self.plan())
        self.assertEqual(sum(row["decision"] == "approved" for row in merged["reviews"]), 1)

    def test_stale_prior_approval_is_retained_as_stale_and_not_published(self):
        pt, en = self.plan()
        previous = {"reviews": [{"signature": pt["signature"], "decision": "approved"}]}
        merged = merge_reviews(previous, {"reviews": []}, {"takes": [pt, en]}, [en])
        self.assertEqual(merged["reviews"][0]["decision"], "stale")

    def test_forged_provenance_cannot_reuse_an_existing_signature(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            production, review, _ = self.review_fixture(root)
            production["takes"][0]["spoken_text"] = "Different subtitle."
            with self.assertRaisesRegex(DirectionError, "provenance differs"):
                approved_manifest(production, review, current_plan=self.plan(), root=root)

    def test_documentation_changes_do_not_rerender_the_same_performance(self):
        before = self.plan()[0]
        self.cast["personas"]["cida"]["biography"] = "New nonaudible production notes."
        self.cast["personas"]["cida"]["sources"] = ["world/places/sewers/SewerResident.gd"]
        after = self.plan()[0]
        self.assertEqual(before["signature"], after["signature"])
        self.assertNotEqual(before["cast_revision"], after["cast_revision"])

    def test_english_actor_notes_do_not_rerender_portuguese(self):
        before = self.plan()
        self.cast["personas"]["cida"]["direction"]["en"] = "An older woman, dry and deliberate English diction."
        after = self.plan()
        self.assertEqual(before[0]["signature"], after[0]["signature"])
        self.assertNotEqual(before[1]["signature"], after[1]["signature"])

    def test_unbound_procedural_emitter_blocks_publication_even_with_complete_cast(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.row["publication_blockers"] = ["Procedural dialogue is not bound to an actor instance"]
            production, review, _ = self.review_fixture(root)
            with self.assertRaisesRegex(DirectionError, "binding is unresolved"):
                approved_manifest(production, review, current_plan=self.plan(), root=root)


if __name__ == "__main__":
    unittest.main()
