"""Rádio da central da polícia (perseguição estilo GTA, 21/10/2026): roteiro, prompts e instalação.

O rádio monta a fala por pedaços, como o scanner do GTA: frase-base ("Suspeito em fuga"), trecho de
rua ("na Union Avenue") e sentido ("sentido norte"). Cada pedaço é gravado uma vez na ElevenLabs
(eleven_v4) em PT-BR e em inglês. Para gastar poucas chamadas, os pedaços de um grupo vão juntos
num texto só, separados por [long pause], e são recortados depois pelo silêncio.

Uso:
  python -I tools/police_radio_voice.py prompts            # imprime os textos de cada grupo e a soma de caracteres
  python -I tools/police_radio_voice.py install <pasta>    # <pasta>/<idioma>_<grupo>.mp3 -> audio/police_radio/
O `install` recorta, aplica o filtro de rádio (banda 300-3400 Hz, saturação leve, chiado de fundo),
gera os chiados de abrir/fechar o canal e grava `audio/police_radio/manifest.json`.
"""
from __future__ import annotations

import json
import math
import random
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "audio/police_radio"
FFMPEG = Path("C:/Users/rafae/AppData/Local/Programs/Python/Python311/Lib/site-packages/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe")
RATE = 24000
MODEL = "eleven_v4"
VOICES = {"pt": ("PZMcMFpToj1IIYF0QDwX", "HQ Marianne - Atendimento ao Cliente"),
          "en": ("NDTYOmYEjbDIVCKB35i3", "Paige - Engaging Narrator")}
HEADER = {"pt": "[calmly] [professional] ", "en": "[calmly] [professional] "}
PAUSE = " [long pause] "

# Frases-base. A chave é o que o jogo pede (PursuitRadio.gd).
PHRASES = {
    "all_units": ("Central para todas as unidades.", "Dispatch to all units."),
    "wanted": ("Suspeito procurado, unidades a caminho.", "Suspect wanted, units en route."),
    "escalated": ("Situação agravada, reforço autorizado.", "Situation escalating, backup authorized."),
    "spotted": ("Suspeito avistado.", "Suspect spotted."),
    "fleeing": ("Suspeito em fuga.", "Suspect fleeing."),
    "lost": ("Perdemos o contato, última posição.", "We lost visual, last seen."),
    "search": ("Vasculhem a área.", "Search the area."),
    "roadblock": ("Bloqueio montado.", "Roadblock in place."),
    "evaded": ("Suspeito despistou, encerrem a busca.", "Suspect evaded, call off the search."),
}
HEADINGS = {
    "norte": ("Sentido norte.", "Heading north."), "nordeste": ("Sentido nordeste.", "Heading northeast."),
    "leste": ("Sentido leste.", "Heading east."), "sudeste": ("Sentido sudeste.", "Heading southeast."),
    "sul": ("Sentido sul.", "Heading south."), "sudoeste": ("Sentido sudoeste.", "Heading southwest."),
    "oeste": ("Sentido oeste.", "Heading west."), "noroeste": ("Sentido noroeste.", "Heading northwest."),
}
# Trecho de rua por nome de exibição (PursuitRadio.street_name devolve estes nomes).
STREETS = {
    "estrada rural": ("Na estrada rural.", "On the rural road."),
    "praça do Memorial": ("Na praça do Memorial.", "At Memorial Square."),
    "Foundry Avenue": ("Na Foundry Avenue.", "On Foundry Avenue."),
    "Market Street": ("Na Market Street.", "On Market Street."),
    "Dock Street": ("Na Dock Street.", "On Dock Street."),
    "Westgate Drive": ("Na Westgate Drive.", "On Westgate Drive."),
    "Union Avenue": ("Na Union Avenue.", "On Union Avenue."),
    "Warehouse Way": ("Na Warehouse Way.", "On Warehouse Way."),
    "Quay Boulevard": ("No Quay Boulevard.", "On Quay Boulevard."),
    "Island Esplanade": ("Na Island Esplanade.", "On Island Esplanade."),
    "East Union Avenue": ("Na East Union Avenue.", "On East Union Avenue."),
    "Eastgate Drive": ("Na Eastgate Drive.", "On Eastgate Drive."),
    "Island Market Street": ("Na Island Market Street.", "On Island Market Street."),
    "Island Dock Street": ("Na Island Dock Street.", "On Island Dock Street."),
    "Exchange Lane": ("Na Exchange Lane.", "On Exchange Lane."),
    "Courtyard Lane": ("Na Courtyard Lane.", "On Courtyard Lane."),
    "Northbank Neighborhood Street": ("Na Northbank Neighborhood Street.", "On Northbank Neighborhood Street."),
    "Northbank Civic Avenue": ("Na Northbank Civic Avenue.", "On Northbank Civic Avenue."),
    "Northbank Gateway Avenue": ("Na Northbank Gateway Avenue.", "On Northbank Gateway Avenue."),
    "rodovia da ponte": ("Na rodovia da ponte.", "On the bridge highway."),
    "retorno da rodovia": ("No retorno da rodovia.", "At the highway turnaround."),
    "via de serviço do Westgate": ("Na via de serviço do Westgate.", "On the Westgate service lane."),
    "Medical Garden Lane": ("Na Medical Garden Lane.", "On Medical Garden Lane."),
    "porto sul": ("No porto sul.", "In the south port."),
    "ponte da serra": ("Na ponte da serra.", "On the mountain bridge."),
    "Cobra Court": ("No Cobra Court.", "At Cobra Court."),
    "acesso do ferro-velho": ("No acesso do ferro-velho.", "At the salvage yard access."),
    "estrada da serra": ("Na estrada da serra.", "On the mountain road."),
    "passagem da serra": ("Na passagem da serra.", "On the mountain pass."),
    "ponte": ("Na ponte.", "On the bridge."),
    "Rota 66": ("Na Rota 66.", "On Route 66."),
    "Estrada do Sal": ("Na Estrada do Sal.", "On the Salt Road."),
    "rodovia oeste": ("Na rodovia oeste.", "On the west highway."),
    "rua principal": ("Na rua principal.", "On Main Street."),
    "pista de arrancada": ("Na pista de arrancada.", "At the drag strip."),
    "rua do Digo": ("Na rua do Digo.", "On Digo Street."),
    "acesso do banco": ("No acesso do banco.", "At the bank approach."),
    "posto de caminhoneiros": ("No posto de caminhoneiros.", "At the truck stop."),
}


def groups() -> list[tuple[str, list[tuple[str, str, str]]]]:
    """(grupo, [(categoria, chave, índice do idioma)]) na ordem em que são falados."""
    streets = list(STREETS)
    half = (len(streets) + 1) // 2
    return [
        ("base", [("phrase", key) for key in PHRASES] + [("heading", key) for key in HEADINGS]),
        ("ruas1", [("street", key) for key in streets[:half]]),
        ("ruas2", [("street", key) for key in streets[half:]]),
    ]


def text_for(category: str, key: str, language: str) -> str:
    table = {"phrase": PHRASES, "heading": HEADINGS, "street": STREETS}[category]
    return table[key][0 if language == "pt" else 1]


def prompt(group: str, language: str) -> str:
    items = dict(groups())[group]
    return HEADER[language] + PAUSE.join(text_for(category, key, language) for category, key in items)


def cmd_prompts() -> None:
    total = 0
    for language in ("pt", "en"):
        for group, items in groups():
            text = prompt(group, language)
            total += len(text)
            print(f"== {language}_{group} ({len(items)} pedaços, {len(text)} caracteres)\n{text}\n")
    print(f"TOTAL {total} caracteres")


# --- Instalação ------------------------------------------------------------------------

def decode(path: Path) -> np.ndarray:
    raw = subprocess.run([str(FFMPEG), "-hide_banner", "-loglevel", "error", "-i", str(path), "-ac", "1", "-ar", str(RATE),
                          "-f", "s16le", "-"], check=True, capture_output=True, timeout=120).stdout
    return np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0


def split(samples: np.ndarray, expected: int) -> list[np.ndarray]:
    """Recorta pelos silêncios mais longos: exatamente `expected` trechos ou erro."""
    window = int(RATE * 0.02)
    frames = len(samples) // window
    energy = np.sqrt(np.mean(samples[: frames * window].reshape(frames, window) ** 2, axis=1))
    loud = energy > max(0.01, float(np.percentile(energy, 90)) * 0.06)
    gaps: list[tuple[int, int]] = []
    start = None
    for index, value in enumerate(loud):
        if not value and start is None: start = index
        elif value and start is not None:
            gaps.append((start, index)); start = None
    first = int(np.argmax(loud))
    last = len(loud) - int(np.argmax(loud[::-1]))
    inner = [gap for gap in gaps if gap[0] > first and gap[1] < last]
    if len(inner) < expected - 1: raise ValueError(f"só {len(inner) + 1} trechos, esperado {expected}")
    cuts = sorted(sorted(inner, key=lambda gap: gap[1] - gap[0], reverse=True)[: expected - 1])
    shortest = min((gap[1] - gap[0]) * 20 for gap in cuts) if cuts else 0
    bounds = [first] + [value for gap in cuts for value in gap] + [last]
    pieces = []
    for index in range(0, len(bounds), 2):
        a = max(0, bounds[index] - 3) * window
        b = min(frames, bounds[index + 1] + 4) * window
        pieces.append(samples[a:b].copy())
    print(f"   recorte: {expected} trechos, menor pausa usada {shortest} ms")
    return pieces


def _biquad(samples: np.ndarray, b: tuple[float, float, float], a: tuple[float, float, float]) -> np.ndarray:
    out = np.zeros_like(samples)
    x1 = x2 = y1 = y2 = 0.0
    b0, b1, b2 = b
    _, a1, a2 = a
    for index, x in enumerate(samples):
        y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, x, y1, y
        out[index] = y
    return out


def _coefficients(kind: str, frequency: float, q: float = 0.707) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
    w = 2.0 * math.pi * frequency / RATE
    alpha = math.sin(w) / (2.0 * q)
    cosine = math.cos(w)
    if kind == "high":
        b = ((1 + cosine) / 2, -(1 + cosine), (1 + cosine) / 2)
    else:
        b = ((1 - cosine) / 2, 1 - cosine, (1 - cosine) / 2)
    a0 = 1 + alpha
    a = (1.0, -2 * cosine / a0, (1 - alpha) / a0)
    return tuple(value / a0 for value in b), a  # type: ignore[return-value]


def radio(samples: np.ndarray, seed: int) -> np.ndarray:
    """Banda de rádio (300-3400 Hz, duas passagens), saturação leve e chiado de fundo."""
    voice = samples / max(1e-6, float(np.max(np.abs(samples)))) * 0.9
    for _ in range(2):
        voice = _biquad(voice, *_coefficients("high", 300.0))
        voice = _biquad(voice, *_coefficients("low", 3400.0))
    voice = np.tanh(voice * 2.2) / math.tanh(2.2)
    rng = np.random.default_rng(seed)
    hiss = _biquad(rng.normal(0.0, 1.0, len(voice)).astype(np.float32), *_coefficients("high", 1800.0))
    hiss = _biquad(hiss, *_coefficients("low", 5200.0))
    hiss = hiss / max(1e-6, float(np.max(np.abs(hiss)))) * 0.045
    out = voice * 0.82 + hiss
    return np.clip(out / max(1e-6, float(np.max(np.abs(out)))) * 0.85, -1.0, 1.0)


def squelch(seed: int, opening: bool) -> np.ndarray:
    """Chiado de abrir (estalo + rajada curta) ou fechar o canal (rajada mais longa que corta seco)."""
    rng = np.random.default_rng(seed)
    length = int(RATE * (0.16 if opening else 0.32))
    noise = rng.normal(0.0, 1.0, length).astype(np.float32)
    noise = _biquad(noise, *_coefficients("high", 900.0))
    noise = _biquad(noise, *_coefficients("low", 4600.0))
    t = np.arange(length) / RATE
    envelope = np.minimum(1.0, t / 0.004) * (np.exp(-t * (9.0 if opening else 4.5)))
    if not opening: envelope *= (t < (length / RATE) * 0.92)
    click = np.zeros(length, dtype=np.float32)
    click[: int(RATE * 0.003)] = 1.0
    tone = 0.25 * np.sin(2 * math.pi * 1250.0 * t) * np.exp(-t * 40.0) if opening else 0.0
    out = noise / max(1e-6, float(np.max(np.abs(noise)))) * envelope * 0.6 + click * 0.7 + tone
    return np.clip(out, -1.0, 1.0)


def write_wav(path: Path, samples: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = (np.clip(samples, -1.0, 1.0) * 32767.0).astype("<i2").tobytes()
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(data)


def cmd_install(folder: Path) -> None:
    manifest: dict = {"model": MODEL, "voices": {lang: {"id": VOICES[lang][0], "name": VOICES[lang][1]} for lang in VOICES},
                      "rate": RATE, "squelch": {"open": "squelch_open.wav", "close": "squelch_close.wav"},
                      "phrases": {}, "headings": {}, "streets": {}}
    missing = []
    for language in ("pt", "en"):
        for group, items in groups():
            source = folder / f"{language}_{group}.mp3"
            # Grupo ainda não gerado (21/10: a cota mensal da ElevenLabs acabou depois do pt_base):
            # o jogo pula o pedaço que falta e o rádio continua em texto.
            if not source.exists():
                missing.append(source.name)
                continue
            print(f"== {source.name}")
            pieces = split(decode(source), len(items))
            for index, ((category, key), piece) in enumerate(zip(items, pieces)):
                name = f"{language}/{category}_{index:02d}_{group}.wav"
                write_wav(OUT / name, radio(piece, hash((language, group, index)) & 0xFFFF))
                table = {"phrase": "phrases", "heading": "headings", "street": "streets"}[category]
                manifest[table].setdefault(key, {})[language] = name
    write_wav(OUT / "squelch_open.wav", squelch(11, True))
    write_wav(OUT / "squelch_close.wav", squelch(23, False))
    manifest["missing_groups"] = missing
    (OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"instalado em {OUT}; grupos sem gravação: {missing}")


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "prompts": cmd_prompts()
    elif len(sys.argv) >= 3 and sys.argv[1] == "install": cmd_install(Path(sys.argv[2]))
    else: print(__doc__)
