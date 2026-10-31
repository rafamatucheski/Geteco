"""Monta o programa CC0 Fronteira Country; a reprodução offline no jogo só precisa do OGG.

As fontes estão creditadas em audio/desert_country/CREDITS.md. Rodar de qualquer pasta:
    python tools/build_desert_country_radio.py
Requer numpy, soundfile e imageio-ffmpeg (já usados nas ferramentas locais de assets).
Baixa as fontes para a pasta temporária do sistema; nunca sobrescreve outra música.
"""
from __future__ import annotations

import hashlib
import json
import subprocess
import tempfile
import urllib.request
from pathlib import Path

import imageio_ffmpeg
import numpy as np
import soundfile as sf


ROOT = Path(__file__).resolve().parents[1]
RATE = 44100
TRACKS = [
    {
        "title": "Country",
        "artist": "Alex McCulloch (Pro Sensory)",
        "page": "https://opengameart.org/content/country",
        "url": "https://opengameart.org/sites/default/files/Country1_1.mp3",
    },
    {
        "title": "Gone Fishin'",
        "artist": "Memoraphile @ You're Perfect Studio",
        "page": "https://opengameart.org/content/gone-fishin",
        "url": "https://opengameart.org/sites/default/files/gone_fishin_by_memoraphile_CC0_0.mp3",
    },
    {
        "title": "Beary Fishy",
        "artist": "Memoraphile @ You're Perfect Studio",
        "page": "https://opengameart.org/content/gone-fishin",
        "url": "https://opengameart.org/sites/default/files/beary_fishy_menu_screen_by_memoraphile_CC0.mp3",
    },
]


def build() -> None:
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    result = []
    sequence = []
    cursor = 0.0
    with tempfile.TemporaryDirectory(prefix="geteco-country-") as folder:
        work = Path(folder)
        for index, source in enumerate(TRACKS):
            original = work / f"source-{index}.mp3"
            request = urllib.request.Request(source["url"], headers={"User-Agent": "Geteco-AssetBuild/1.0"})
            with urllib.request.urlopen(request, timeout=60) as response:
                original.write_bytes(response.read())
            decoded = work / f"track-{index}.wav"
            subprocess.run([
                ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", str(original),
                "-af", "loudnorm=I=-18:TP=-2:LRA=10", "-ar", str(RATE), "-ac", "2", str(decoded),
            ], check=True)
            samples, rate = sf.read(decoded, dtype="float32", always_2d=True)
            assert rate == RATE and samples.shape[1] == 2
            # Preserva cada execução inteira; fades curtos nas bordas evitam cliques de codec/corte.
            edge = min(int(.04 * RATE), len(samples) // 2)
            samples[:edge] *= np.linspace(0, 1, edge, dtype=np.float32)[:, None]
            samples[-edge:] *= np.linspace(1, 0, edge, dtype=np.float32)[:, None]
            duration = len(samples) / RATE
            sequence.append(samples)
            sequence.append(np.zeros((int(.3 * RATE), 2), dtype=np.float32))
            result.append({**source, "license": "CC0-1.0", "source_sha256": hashlib.sha256(original.read_bytes()).hexdigest(),
                           "start_seconds": round(cursor, 4), "duration_seconds": round(duration, 4)})
            cursor += duration + .3
        programme = np.concatenate(sequence)
        destination = ROOT / "audio/living_city/fronteira_country.ogg"
        wav = work / "programme.wav"
        sf.write(wav, programme, RATE, subtype="PCM_24")
        subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", str(wav),
                        "-c:a", "libvorbis", "-q:a", "5", "-metadata", "title=Fronteira Country",
                        "-metadata", "artist=Alex McCulloch; Memoraphile", str(destination)], check=True)
    rendered, rate = sf.read(destination, dtype="float32", always_2d=True)
    peak = float(np.max(np.abs(rendered)))
    rms = float(np.sqrt(np.mean(rendered ** 2)))
    assert rendered.shape[1] == 2 and len(rendered) / rate > 240, "Expected a full stereo programme"
    assert 0 < peak < 1.0 and rms > .015, "Radio must be audible and free of sample clipping"
    manifest = {"station": "FRONTEIRA COUNTRY", "license": "CC0-1.0", "license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
                "processing": "Full tracks, normalized to -18 LUFS / -2 dBTP; 40 ms edge fades and 300 ms between tracks; Ogg Vorbis q5",
                "sample_rate": rate, "channels": rendered.shape[1], "duration_seconds": round(len(rendered) / rate, 4),
                "peak_dbfs": round(20 * np.log10(peak), 3), "rms_dbfs": round(20 * np.log10(rms), 3),
                "sha256": hashlib.sha256(destination.read_bytes()).hexdigest(), "tracks": result}
    manifest_path = ROOT / "audio/desert_country/SOURCES.json"
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({"path": str(destination), "duration_seconds": manifest["duration_seconds"],
                      "peak_dbfs": manifest["peak_dbfs"], "rms_dbfs": manifest["rms_dbfs"], "bytes": destination.stat().st_size}))


if __name__ == "__main__":
    build()
