"""Anchored synthesis provenance and honest runtime publication contracts."""
import copy
import hashlib
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import build_voice_bank as bank
from mix_directed_voices import gain_for_measurement
from voice_backend import generation_termination
from voice_direction import DirectionError


class AnchoredBankContracts(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        output = root / "audio/mission_voices/directed"
        output.mkdir(parents=True)
        self.addCleanup(patch.stopall)
        patch.object(bank, "ROOT", root).start()
        patch.object(bank, "OUTPUT", output).start()
        path = output / "anchor.wav"
        path.write_bytes(b"immutable audio fixture")
        self.anchor = {"path": "res://audio/mission_voices/directed/anchor.wav",
                       "audio_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                       "voice_gender": "female", "text": "Fala de referência."}
        self.take = {"signature": "a"*64, "source_key": "b"*64, "character_id": "cida", "persona": "cida",
                     "voice_gender": "female", "spoken_text": "Pode falar daí.", "source": "Pode falar daí.",
                     "language": "pt_BR", "settings": {"seed": 14, "max_new_tokens": 200},
                     "direction": "Brazilian woman's voice. Scene performance overrides habitual emotion: firm warning.",
                     "casting_blockers": []}
        self.settings = {"model": "Base", "model_revision": "revision", "quantization": "none"}

    def plan(self, takes=None):
        return bank.clone_plan(takes or [self.take], {"cida": self.anchor}, self.settings, "experimental_text")

    def test_both_languages_share_reference_without_sharing_signature(self):
        english = {**self.take, "signature": "c"*64, "language": "en", "spoken_text": "Stay there."}
        by_language = {take["language"]: take for take in self.plan([self.take, english])}
        pt, en = by_language["pt_BR"], by_language["en"]
        self.assertEqual(pt["anchor_sha256"], en["anchor_sha256"])
        self.assertNotEqual(pt["signature"], en["signature"])
        self.assertEqual(pt["reference_mode"], "icl")
        self.assertEqual(en["reference_mode"], "speaker_embedding")

    def test_batch_membership_is_deterministic_and_signed(self):
        english = {**self.take, "signature": "c"*64, "language": "en", "spoken_text": "Stay there."}
        planned = bank.clone_plan([self.take, english], {"cida": self.anchor}, self.settings, "experimental_text", batch_size=2)
        reversed_input = bank.clone_plan([english, self.take], {"cida": self.anchor}, self.settings, "experimental_text", batch_size=2)
        self.assertEqual(planned, reversed_input)
        self.assertEqual(planned[0]["batch_id"], planned[1]["batch_id"])
        self.assertNotEqual(planned[0]["signature"], self.plan([self.take, english])[0]["signature"])

    def test_missing_reference_cannot_invent_default_voice(self):
        with self.assertRaisesRegex(DirectionError, "Missing actor"):
            bank.clone_plan([self.take], {}, self.settings, "reference")

    def test_reference_gender_mismatch_stops_plan(self):
        self.anchor["voice_gender"] = "male"
        with self.assertRaisesRegex(DirectionError, "gender"):
            self.plan()

    def test_changed_reference_bytes_stop_plan(self):
        (bank.OUTPUT / "anchor.wav").write_bytes(b"different")
        with self.assertRaisesRegex(DirectionError, "provenance"):
            self.plan()

    def test_actual_quantization_and_conditioning_are_signed(self):
        original = self.plan()[0]["signature"]
        self.settings["quantization"] = "nf4"
        self.assertNotEqual(original, self.plan()[0]["signature"])
        reference = bank.clone_plan([self.take], {"cida": self.anchor}, self.settings, "reference")
        self.assertNotEqual(reference[0]["signature"], self.plan()[0]["signature"])

    def recording(self):
        plan = self.plan()[0]
        return plan, {**plan, **self.anchor, "status": "generated", "duration_seconds": 2.0,
                      "artistic_review": "pending", "technical_validation": {"passed": True},
                      "transcription_validation": {"status": "pending"}}

    def test_runtime_generation_does_not_fabricate_artistic_approval(self):
        plan, record = self.recording()
        manifest = bank.runtime_manifest([plan], [record])
        entry = manifest["lines"]["pt_BR"][plan["source_key"]]
        self.assertEqual(entry["artistic_review"], "pending")
        self.assertEqual(entry["status"], "generated")
        self.assertNotIn("reviewer", entry)

    def test_unbound_character_cannot_be_published(self):
        plan, record = self.recording()
        plan["casting_blockers"] = ["runtime emitter gender unresolved"]
        manifest = bank.runtime_manifest([plan], [record])
        self.assertEqual(manifest["coverage"]["generated"], 0)
        self.assertEqual(len(manifest["coverage"]["blocked"]), 1)

    def test_changed_current_text_cannot_publish_old_audio(self):
        plan, record = self.recording()
        plan["spoken_text"] = "New source text"
        with self.assertRaisesRegex(DirectionError, "provenance"):
            bank.runtime_manifest([plan], [record])

    def test_failed_transcript_is_excluded(self):
        plan, record = self.recording()
        record["transcription_validation"] = {"status": "failed"}
        manifest = bank.runtime_manifest([plan], [record])
        self.assertFalse(manifest["coverage"]["complete"])

    def test_subset_publication_never_claims_full_bank_completion(self):
        plan, record = self.recording()
        manifest = bank.runtime_manifest([plan], [record], expected_total=1130)
        self.assertEqual(manifest["coverage"]["expected"], 1130)
        self.assertEqual(manifest["coverage"]["generated"], 1)
        self.assertFalse(manifest["coverage"]["complete"])

    def test_retake_changes_only_requested_language_and_keeps_words_actor_anchor(self):
        english = {**self.take, "signature": "c"*64, "language": "en", "spoken_text": "Stay there."}
        original = self.plan([self.take, english])
        before = copy.deepcopy(original)
        request = {"repairs": [{"source_key": self.take["source_key"], "language": "en", "seed": 33,
                                 "variant": "lexical_1", "reason": "ASR found a substituted word"}]}
        alternative = bank.repair_plan(original, request, self.settings)
        selected = bank.selected_repaired_plan(original, {"repairs": alternative})
        self.assertEqual(original, before)
        self.assertEqual([t for t in selected if t["language"] == "pt_BR"], [t for t in original if t["language"] == "pt_BR"])
        old_en = next(t for t in original if t["language"] == "en")
        new_en = next(t for t in selected if t["language"] == "en")
        self.assertNotEqual(old_en["signature"], new_en["signature"])
        for field in ("spoken_text", "character_id", "voice_gender", "anchor_sha256"):
            self.assertEqual(old_en[field], new_en[field])

    def test_retake_requires_reason_seed_and_variant(self):
        with self.assertRaisesRegex(DirectionError, "reason"):
            bank.repair_plan(self.plan(), {"repairs": [{"source_key": self.take["source_key"], "language": "pt_BR"}]}, self.settings)

    def test_changed_word_cannot_be_hidden_inside_a_repair_selection(self):
        original = self.plan()
        request = {"repairs": [{"source_key": self.take["source_key"], "language": "pt_BR", "seed": 33,
                                 "variant": "lexical_1", "reason": "Substituted word"}]}
        alternatives = bank.repair_plan(original, request, self.settings)
        alternatives[0]["spoken_text"] = "Different script"
        with self.assertRaisesRegex(DirectionError, "authored word"):
            bank.selected_repaired_plan(original, {"repairs": alternatives})

    def test_loudness_gain_preserves_peak_ceiling(self):
        gain, method = gain_for_measurement(-31, -4)
        self.assertEqual(gain, 2.5)
        self.assertEqual(method, "integrated_loudness")
        self.assertLessEqual(-4+gain, -1.5)

    def test_short_cry_has_explicit_peak_based_mix_without_compression(self):
        gain, method = gain_for_measurement(float("-inf"), -18)
        self.assertEqual(gain, 12)
        self.assertEqual(method, "short_utterance_peak")

    def test_asr_flag_cannot_publish_as_validated_content(self):
        plan, record = self.recording()
        report = {"asr_model": "test_model", "takes": [{"waveform": {"sha256": record["audio_sha256"]},
                    "language": "pt_BR", "expected": record["spoken_text"], "technical_errors": [],
                    "asr": {"review": True, "transcript": "Different words", "word_similarity": .4}}]}
        audited = bank.apply_content_audits([record], [report])
        manifest = bank.runtime_manifest([plan], audited)
        self.assertEqual(manifest["coverage"]["generated"], 0)
        self.assertEqual(len(manifest["coverage"]["content_review"]), 1)

    def test_asr_verdict_cannot_transfer_to_new_audio_or_text(self):
        _, record = self.recording()
        report = {"takes": [{"waveform": {"sha256": "changed"}, "language": "pt_BR",
                    "expected": record["spoken_text"], "asr": {"review": False}}]}
        self.assertEqual(bank.apply_content_audits([record], [report])[0]["transcription_validation"]["status"], "pending")

    def test_final_publication_can_require_content_audit(self):
        plan, record = self.recording()
        manifest = bank.runtime_manifest([plan], [record], require_audit=True)
        self.assertEqual(manifest["coverage"]["generated"], 0)
        self.assertEqual(len(manifest["coverage"]["content_pending"]), 1)

    def test_homophone_adjudication_is_explicit_and_not_artistic_approval(self):
        plan, record = self.recording()
        report = {"takes": [{"waveform": {"sha256": record["audio_sha256"]}, "language": "pt_BR",
                    "expected": record["spoken_text"], "asr": {"review": True, "transcript": "Homophone"}}]}
        decision = {"audio_sha256": record["audio_sha256"], "language": "pt_BR", "expected": record["spoken_text"],
                    "decision": "lexically_equivalent", "reason": "Established homophones; the spelling cannot prove an audible error."}
        audited = bank.apply_content_audits([record], [report], {"decisions": [decision]})
        entry = bank.runtime_manifest([plan], audited, require_audit=True)["lines"]["pt_BR"][plan["source_key"]]
        self.assertEqual(entry["transcription_validation"]["status"], "lexically_equivalent")
        self.assertFalse(entry["transcription_validation"]["human_listening"])
        self.assertEqual(entry["artistic_review"], "pending")

    def test_character_resume_preserves_complete_signed_batch(self):
        takes = [{"character_id": "cida", "batch_id": "one", "signature": "first"},
                 {"character_id": "dante", "batch_id": "one", "signature": "second"},
                 {"character_id": "dante", "batch_id": "two", "signature": "third"}]
        self.assertEqual(bank.complete_character_batches(takes, {"cida"}), takes[:2])

    def reference_requests(self):
        specs = {identity: {"character_id": identity, "signature": identity*4, "direction": "Established identity",
                           "text": "Exact reference words", "voice_gender": "male"} for identity in ("one", "two", "three")}
        requests = {"batch_size": 4, "batch_seed": 42, "anchors": [
            {"character_id": identity, "seed": 42, "reason": "Independent content flag", "variant": "clarity_1",
             "direction_suffix": "Articulate supplied words clearly."} for identity in specs]}
        return specs, requests

    def test_reference_alternatives_sign_actual_shared_batch_and_seed(self):
        specs, requests = self.reference_requests()
        planned = bank.reference_retake_plan(specs, requests, self.settings)
        self.assertEqual(len(planned), 3)
        self.assertEqual(len({item[2]["batch_id"] for item in planned}), 1)
        self.assertEqual({item[2]["batch_position"] for item in planned}, {0, 1, 2})
        self.assertTrue(all(item[2]["batch_size"] == 3 and item[2]["seed"] == 42 for item in planned))
        requests["anchors"].pop()
        changed = bank.reference_retake_plan(specs, requests, self.settings)
        self.assertNotEqual(planned[0][3], changed[0][3])

    def test_reference_batch_cannot_misreport_individual_seed(self):
        specs, requests = self.reference_requests()
        requests["anchors"][0]["seed"] = 99
        with self.assertRaisesRegex(DirectionError, "shared batch_seed"):
            bank.reference_retake_plan(specs, requests, self.settings)

    def test_selected_failing_takes_can_share_a_signed_repair_batch(self):
        english = {**self.take, "signature": "c"*64, "language": "en", "spoken_text": "Stay there."}
        original = self.plan([self.take, english])
        requests = {"batch_size": 8, "batch_seed": 77, "repairs": [
            {"source_key": take["source_key"], "language": take["language"], "seed": 77,
             "variant": "lexical_1", "reason": "Independent ASR content flag"} for take in original]}
        replacements = bank.repair_plan(original, requests, self.settings)
        self.assertEqual(len({t["batch_id"] for t in replacements}), 1)
        self.assertTrue(all(t["batch_size"] == 2 and t["batch_seed"] == 77 for t in replacements))
        selected = bank.selected_repaired_plan(original, {"repairs": replacements})
        self.assertEqual({t["spoken_text"] for t in selected}, {t["spoken_text"] for t in original})
        replacements[0]["batch_seed"] = 78
        with self.assertRaisesRegex(DirectionError, "batch differs"):
            bank.selected_repaired_plan(original, {"repairs": replacements})

    def test_portuguese_repair_can_remove_icl_without_changing_actor_or_words(self):
        original = self.plan()
        request = {"repairs": [{"source_key": self.take["source_key"], "language": "pt_BR", "seed": 33,
                    "variant": "embedding_diagnostic", "reason": "Two ASRs suggest reference-text interference",
                    "reference_mode": "speaker_embedding"}]}
        alternatives = bank.repair_plan(original, request, self.settings)
        selected = bank.selected_repaired_plan(original, {"repairs": alternatives})[0]
        self.assertEqual(selected["reference_mode"], "speaker_embedding")
        self.assertEqual(selected["repair_recipe"]["reference_mode"], "speaker_embedding")
        self.assertEqual(selected["anchor_sha256"], original[0]["anchor_sha256"])
        self.assertEqual(selected["spoken_text"], original[0]["spoken_text"])

    def test_timing_retake_adds_signed_direction_without_changing_words(self):
        original = self.plan()
        request = {"repairs": [{"source_key": self.take["source_key"], "language": "pt_BR", "seed": 33,
                    "variant": "timing_1", "reason": "Full line exceeded the cinematic slot",
                    "direction_suffix": "Use compact pauses and keep the full phrase inside 4.82 seconds.",
                    "max_duration_seconds": 4.82}]}
        replacement = bank.repair_plan(original, request, self.settings)
        selected = bank.selected_repaired_plan(original, {"repairs": replacement})[0]
        self.assertTrue(selected["direction"].startswith(original[0]["direction"]))
        self.assertEqual(selected["spoken_text"], original[0]["spoken_text"])
        self.assertEqual(selected["repair_recipe"]["max_duration_seconds"], 4.82)

    def test_timing_failure_is_excluded_without_truncating_audio(self):
        plan, record = self.recording()
        record["timing_validation"] = {"passed": False, "maximum_seconds": 1, "actual_seconds": 2}
        self.assertEqual(bank.runtime_manifest([plan], [record])["coverage"]["generated"], 0)
        self.assertEqual(record["duration_seconds"], 2)

    def test_codec_cap_without_eos_is_rejected_not_mistaken_for_completion(self):
        observed = generation_termination([[10, 20, 99, 99], [10, 20, 30, 40]], 99, 4)
        self.assertTrue(observed[0]["passed"])
        self.assertEqual(observed[0]["generated_steps"], 3)
        self.assertFalse(observed[1]["passed"])
        self.assertTrue(observed[1]["hit_limit_without_eos"])
        plan, record = self.recording()
        record["generation_validation"] = observed[1]
        self.assertEqual(bank.runtime_manifest([plan], [record])["coverage"]["generated"], 0)

    def test_short_vocalization_repair_budget_cannot_expand_to_dialogue_budget(self):
        english = {**self.take, "signature": "c"*64, "language": "en", "spoken_text": "Stay there."}
        original = self.plan([self.take, english])
        requests = {"batch_size": 8, "batch_seed": 77, "repairs": [
            {"source_key": take["source_key"], "language": take["language"], "seed": 77,
             "variant": "lexical_1", "reason": "Independent content flag", "max_new_tokens": 48 if take["language"] == "pt_BR" else 180}
            for take in original]}
        alternatives = bank.repair_plan(original, requests, self.settings)
        self.assertEqual(len({take["batch_id"] for take in alternatives}), 2)
        self.assertTrue(all(take["batch_max_new_tokens"] == take["max_new_tokens"] for take in alternatives))

    def test_repair_diagnostic_cannot_target_newer_audio(self):
        plan, record = self.recording()
        request = {"repairs": [{"source_key": plan["source_key"], "language": plan["language"],
            "seed": 33, "variant": "repair", "reason": "Specific diagnostic",
            "supersedes_audio_sha256": "f"*64}]}
        replacement = bank.repair_plan([plan], request, self.settings)
        with self.assertRaisesRegex(DirectionError, "different current audio SHA"):
            bank.validate_repair_targets([plan], request, [record], replacement)
        request["repairs"][0]["supersedes_audio_sha256"] = record["audio_sha256"]
        bank.validate_repair_targets([plan], request, [record], replacement)

    def test_resume_optimization_cannot_replace_a_completed_take(self):
        plan, record = self.recording()
        request = {"repairs": [{"source_key": plan["source_key"], "language": plan["language"],
            "seed": 33, "variant": "resume", "reason": "Missing pain codec budget", "requires_missing": True}]}
        replacement = bank.repair_plan([plan], request, self.settings)
        with self.assertRaisesRegex(DirectionError, "existing recording"):
            bank.validate_repair_targets([plan], request, [record], replacement)
        bank.validate_repair_targets([plan], request, [], replacement)

    def test_completed_repair_checkpoint_preserves_earlier_selection_and_rejects_capped_audio(self):
        plan, record = self.recording()
        request = {"repairs": [{"source_key": plan["source_key"], "language": plan["language"],
            "seed": 33, "variant": "repair", "reason": "Specific diagnostic"}]}
        replacement = bank.repair_plan([plan], request, self.settings)[0]
        completed = {**record, **replacement, "generation_validation": {"passed": True}}
        bank.checkpoint_repair_selections([completed])
        first = bank.read_json(bank.OUTPUT / "repair-selections.json")
        self.assertEqual(len(first["repairs"]), 1)
        failed = {**completed, "signature": "f"*64, "generation_validation": {"passed": False}}
        bank.checkpoint_repair_selections([failed])
        self.assertEqual(bank.read_json(bank.OUTPUT / "repair-selections.json"), first)


if __name__ == "__main__":
    unittest.main()
