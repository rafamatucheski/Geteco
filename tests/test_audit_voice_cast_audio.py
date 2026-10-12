"""Auditing thresholds are fixed before examining production predictions."""
import math
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from audit_voice_cast_audio import POLICY, evaluate_scores
from voice_direction import DirectionError


class CastingAuditPolicy(unittest.TestCase):
    def test_support_never_becomes_human_approval(self):
        row = evaluate_scores([.97, .99, .98], "female")
        self.assertFalse(row["review"])
        self.assertFalse(row["human_approval"])
        self.assertEqual(row["interpretation"], "supports_authored_cast_not_approval")

    def test_opposite_voice_is_a_review_flag(self):
        row = evaluate_scores([.01, .02, .03], "female")
        self.assertTrue(row["review"])
        self.assertEqual(row["interpretation"], "review_likely_cast_mismatch")

    def test_weak_and_disagreeing_windows_are_not_approved(self):
        self.assertEqual(evaluate_scores([.5, .7, .6], "female")["interpretation"], "review_ambiguous_acoustic_profile")
        self.assertEqual(evaluate_scores([.99, .98, .01], "female")["interpretation"], "review_window_disagreement")

    def test_label_order_matches_primary_model(self):
        self.assertFalse(evaluate_scores([.01, .02, .03], "male")["review"])
        self.assertEqual(POLICY["confidence_threshold"], .8)

    def test_invalid_values_fail_closed(self):
        for predictions, expected in [([], "male"), ([math.nan], "female"), ([1.1], "male"), ([.2], "unknown")]:
            with self.assertRaises(DirectionError):
                evaluate_scores(predictions, expected)


if __name__ == "__main__":
    unittest.main()
