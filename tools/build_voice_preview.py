"""Create aligned listening reels from the actual published PT-BR/EN bank."""
from __future__ import annotations

import argparse
from array import array
import hashlib
import json
from pathlib import Path
import sys
import wave

ROOT = Path(__file__).resolve().parents[1]
SELECTION = [
    ("jessica", "2f74ccc16ed52b718b42204c49235f59574f5f599fab5aca4763f109dce41430"),
    ("maciota", "097f95303230fe217925e7a1276cb42fb653a6555a5d4d1885ff649bd31adc21"),
    ("cida", "eca694909fa9d61cd7745f5fa63649ddc88396757e7f90490b399413c936fd87"),
    ("policia_female", None),
    ("ferrugem", "9ca76f6e8092d1ca8cd0e6f018589d6aea38cc5098323b2d37be4e7c34e748d7"),
    ("digo", None),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=ROOT / "audio/mission_voices/directed/runtime.json")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--character", action="append", choices=[item[0] for item in SELECTION],
                        help="Limit the reel to selected characters; defaults to the full comparison")
    args = parser.parse_args()
    raw = args.manifest.read_bytes()
    bank = json.loads(raw.decode("utf-8-sig"))
    keys = []
    for identity, key in SELECTION:
        if args.character and identity not in args.character:
            continue
        if key is None:
            candidates = [(key, row) for key, row in bank["lines"]["pt_BR"].items()
                          if row["character_id"] == identity and len(row["spoken_text"].split()) >= 4
                          and key in bank["lines"]["en"]]
            key = min(candidates, key=lambda pair: (abs(pair[1]["duration_seconds"] - 4), pair[0]))[0]
        keys.append((identity, key))
    args.output.mkdir(parents=True, exist_ok=True)
    report = {"manifest_sha256": hashlib.sha256(raw).hexdigest(),
              "method": "Whole published takes, original 24 kHz PCM, runtime linear gain, 700 ms between characters",
              "artistic_review": "pending", "languages": {}}
    for language in ("pt_BR", "en"):
        samples = array("h", [0]) * 6000
        clips = []
        for identity, key in keys:
            row = bank["lines"][language][key]
            if row["character_id"] != identity or not row["technical_validation"]["passed"]:
                raise ValueError("Unvalidated/mismatched preview entry: " + key)
            source = (ROOT / row["path"].removeprefix("res://")).resolve()
            source.relative_to((ROOT / "audio/mission_voices/directed").resolve())
            if hashlib.sha256(source.read_bytes()).hexdigest() != row["audio_sha256"]:
                raise ValueError("Changed recording: " + str(source))
            with wave.open(str(source), "rb") as handle:
                if (handle.getnchannels(), handle.getsampwidth(), handle.getframerate()) != (1, 2, 24000):
                    raise ValueError("Unexpected PCM format")
                clip = array("h", handle.readframes(handle.getnframes()))
            if sys.byteorder != "little": clip.byteswap()
            factor = 10 ** (row["playback_gain_db"] / 20)
            peak = max(abs(value) for value in clip)
            if peak * factor >= 32767:
                raise ValueError("Preview gain would clip: " + key)
            start = len(samples) / 24000
            samples.extend(round(value * factor) for value in clip)
            clips.append({"character_id": identity, "source_key": key, "text": row["spoken_text"],
                          "start_seconds": start, "end_seconds": len(samples) / 24000,
                          "source_sha256": row["audio_sha256"], "playback_gain_db": row["playback_gain_db"]})
            samples.extend(array("h", [0]) * 16800)
        label = "-".join(identity for identity, _ in keys) + "-" if args.character else ""
        target = args.output / ("dublagem-" + label + language + ".wav")
        if sys.byteorder != "little": samples.byteswap()
        with wave.open(str(target), "wb") as handle:
            handle.setparams((1, 2, 24000, 0, "NONE", "not compressed"))
            handle.writeframes(samples.tobytes())
        report["languages"][language] = {"path": str(target.resolve()), "clips": clips,
                                         "seconds": len(samples) / 24000}
    (args.output / "listening-guide.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({lang: value["seconds"] for lang, value in report["languages"].items()}))


if __name__ == "__main__":
    main()
