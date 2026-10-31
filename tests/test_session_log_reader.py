"""Contratos do leitor: estados mistos numa janela, rotação, truncamento e logs antigos."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("reader", Path(__file__).resolve().parents[1] / "tools/read_session_log.py")
reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reader)


class SessionReaderTests(unittest.TestCase):
    def test_rotated_mixed_state_and_tail(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            rows = [
                {"type": "session_start", "schema": 5},
                {"type": "runtime_state_changed", "id": 1, "scene": "Main", "paused": False, "focused": True},
                {"type": "runtime_state_changed", "id": 2, "scene": "Main", "paused": True, "focused": True},
                {"type": "context_update", "id": 1, "context": {"region": "harbor", "place": "street"}},
                {"type": "operation_begin", "id": 7, "operation": "unfinished"},
                {"type": "metrics", "frame_ms": [10, 40, 100], "frame_context_ids": [1, 1, 1], "frame_state_ids": [1, 2, 1]},
            ]
            (path / "session-000.jsonl").write_text("\n".join(json.dumps({"data": row}) for row in rows), encoding="utf-8")
            tail = {"type": "session_end", "remaining_frame_ms": [20], "remaining_context_ids": [1], "remaining_state_ids": [2]}
            (path / "session-001.jsonl").write_text(json.dumps({"data": tail}) + '\n{"incomplete":', encoding="utf-8")
            result = reader.summarize(path / "session-001.jsonl")
            active = next(s["metrics"] for s in result["scenarios"] if s["scenario"]["paused"] is False)
            paused = next(s["metrics"] for s in result["scenarios"] if s["scenario"]["paused"] is True)
            self.assertEqual(active["frames"], 2)
            self.assertAlmostEqual(active["fps"], 2000 / 110)
            self.assertEqual(active["over_66_7_ms"], 1)
            self.assertEqual(paused["frames"], 2)
            self.assertAlmostEqual(paused["fps"], 2000 / 60)
            self.assertEqual(result["events"]["invalid_record"], 1)
            self.assertEqual(result["unfinished_operations"][0]["id"], 7)
            self.assertTrue(result["normal_end_seen"])

    def test_legacy_and_missing_end(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            rows = [{"data": {"type": "session_start", "schema": 4}},
                    {"data": {"type": "metrics", "frame_ms": [10, 20], "context": {"scene": "Main", "paused": False, "focused": True}}},
                    {"type": "records_dropped", "total": 3}]
            (path / "session-000.jsonl").write_text("\n".join(map(json.dumps, rows)), encoding="utf-8")
            result = reader.summarize(path)
            self.assertFalse(result["normal_end_seen"])
            self.assertEqual(result["records_dropped"], 3)
            self.assertEqual(result["scenarios"][0]["metrics"]["frames"], 2)


if __name__ == "__main__": unittest.main()
