"""Checagens puras de agenda; nunca abre nem se anexa a processo algum."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "owned_wait_schedule", Path(__file__).with_name("capture_owned_wait_points.py"))
sampler = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sampler)


class PeriodicScheduleTests(unittest.TestCase):
    def test_fixed_window_excludes_loading_first_pass_and_recovery(self):
        for seconds in (-1, 0, 29.999, 60, 90, 120):
            self.assertIsNone(sampler.periodic_slot(seconds, -1))
        self.assertEqual(sampler.periodic_slot(30, -1), 0)
        self.assertEqual(sampler.periodic_slot(59.999, -1), 119)

    def test_each_slot_has_one_point(self):
        self.assertEqual(sampler.periodic_slot(30.001, -1), 0)
        self.assertIsNone(sampler.periodic_slot(30.249, 0))
        self.assertEqual(sampler.periodic_slot(30.25, 0), 1)

    def test_late_attachment_skips_past_slots(self):
        self.assertEqual(sampler.periodic_slot(45.125, -1), 60)
        self.assertIsNone(sampler.periodic_slot(45.2, 60))

    def test_delayed_sampler_does_not_replay_backlog(self):
        self.assertEqual(sampler.periodic_slot(34.5, 2), 18)
        self.assertIsNone(sampler.periodic_slot(34.6, 18))

    def test_complete_window_is_bounded_to120_points(self):
        previous = -1
        captured = []
        for tick in range(24001):
            slot = sampler.periodic_slot(tick*.005, previous)
            if slot is not None:
                previous = slot
                captured.append(slot)
        self.assertEqual(captured, list(range(120)))


if __name__ == "__main__":
    unittest.main()
