"""Receiver arithmetic/coverage contracts; no engine or process attachment."""
import unittest

from godot_native_profile_receiver import FrameAggregate


def frame(number, functions):
    return {'frame': number, 'frame_ms': 16.0, 'process_ms': 8.0,
            'physics_ms': 4.0, 'script_ms': sum(row['self_ms'] for row in functions),
            'functions': functions}


def function(signature, calls, own, total, internal=0):
    return {'signature': signature, 'signature_id': 1, 'calls': calls,
            'self_ms': own, 'total_ms': total, 'native_ms': internal}


class AggregateTests(unittest.TestCase):
    def test_sum_every_frame_without_inclusive_or_internal_double_count(self):
        aggregate = FrameAggregate(2048)
        for number in (50, 51):
            aggregate.add(frame(number, [function('res://a.gd::10::tick', 1, 2, 8, 6),
                                        function('res://a.gd::0::Node.get_children', 3, 6, 6, 6)]))
        result = aggregate.snapshot()
        self.assertEqual(result['script_self_ms'], 4)
        self.assertEqual(result['native_self_ms'], 12)
        self.assertEqual(result['functions'][0]['calls'], 6)
        self.assertTrue(result['coverage_ok'])

    def test_duplicate_does_not_inflate_and_gap_fails_coverage(self):
        aggregate = FrameAggregate()
        sample = frame(7, [function('res://a.gd::10::tick', 1, 2, 8)])
        aggregate.add(sample)
        aggregate.add(sample)
        aggregate.add(frame(9, []))
        result = aggregate.snapshot()
        self.assertEqual(result['script_self_ms'], 2)
        self.assertEqual(result['frames_received'], 2)
        self.assertEqual([row['kind'] for row in result['issues']], ['duplicate_frame', 'frame_discontinuity'])
        self.assertFalse(result['coverage_ok'])

    def test_unknown_signature_and_cap_are_explicit(self):
        aggregate = FrameAggregate(1)
        aggregate.add(frame(1, [function('?', 1, 5, 5)]))
        result = aggregate.snapshot()
        self.assertEqual(result['unknown_self_ms'], 5)
        self.assertEqual(result['capped_frames'], 1)
        self.assertFalse(result['coverage_ok'])


if __name__ == '__main__':
    unittest.main()
