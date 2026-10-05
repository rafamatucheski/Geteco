"""Finite ASR check of all authored lines; human listening remains distinct."""
from pathlib import Path
import json, sys
from difflib import SequenceMatcher
from faster_whisper import WhisperModel
ROOT = Path(__file__).resolve().parent
cached = Path("D:/geteco/tools/opening_voice_models/whisper/models--Systran--faster-whisper-small/snapshots")
model = WhisperModel(str(next(cached.iterdir())), device="cpu", compute_type="int8", cpu_threads=4, local_files_only=True)
manifest = json.loads((ROOT / "voices.json").read_text(encoding="utf-8"))
selected = set(sys.argv[1:])
report = ROOT / "transcripts.json"
rows = json.loads(report.read_text(encoding="utf-8")) if selected and report.exists() else []
for line in manifest["lines"]:
    if selected and line["id"] not in selected: continue
    rows = [row for row in rows if row["id"] != line["id"]]
    segments, _ = model.transcribe(str(ROOT / "takes" / line["file"]), language="pt", beam_size=5, word_timestamps=True)
    recognized = " ".join(segment.text.strip() for segment in segments)
    ratio = SequenceMatcher(None, line["text"].lower(), recognized.lower()).ratio()
    row = dict(id=line["id"], expected=line["text"], recognized=recognized, similarity=round(ratio,3))
    rows.append(row)
    print(json.dumps(row, ensure_ascii=False), flush=True)
(ROOT / "transcripts.json").write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")
