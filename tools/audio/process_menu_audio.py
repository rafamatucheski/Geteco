"""Trata a música e os sons de menu gerados no Firefly (2026-10-15).

Música (60 s, 48 kHz estéreo, gerada alta e com fade no fim): vira loop sem emenda (o final
se mistura com o começo), volume casado com a música do menu que já existia (rms ~0,05) e
sai em Ogg Vorbis, que é o formato de loop do Godot sem pagar 11 MB por faixa.
Sons de menu: mono, corte de silêncio, fade e pico casado com os sons sintéticos antigos.
Originais ficam em evidence/firefly_originais_20261015/menu (fora do Git).

Uso: python tools/audio/process_menu_audio.py <pasta com menu_a.wav menu_b.wav loading.wav>
"""
import os, sys, shutil, glob, json
import numpy as np
import soundfile as sf

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MENU = os.path.join(ROOT, "audio", "menu")
BACKUP = os.path.join(ROOT, "evidence", "firefly_originais_20261015", "menu")
os.makedirs(BACKUP, exist_ok=True)
report = {}


def crossfade_loop(x, rate, seconds):
    """x: (n, canais). O trecho final se funde com o início (potência igual)."""
    n, xf = len(x), int(seconds * rate)
    m = n - xf
    out = x[:m].copy()
    t = np.linspace(0, 1, xf, endpoint=False)[:, None]
    out[:xf] = x[:xf] * np.sin(t * np.pi / 2) + x[m:m + xf] * np.cos(t * np.pi / 2)
    return out


def match_level(x, rms_target, peak_cap):
    rms = float(np.sqrt(np.mean(x ** 2)))
    y = x * (rms_target / rms)
    peak = float(np.max(np.abs(y)))
    if peak > peak_cap:
        y *= peak_cap / peak
    return y


def music(src, dst, xfade, rms_target=0.05, peak_cap=0.6):
    x, rate = sf.read(src, always_2d=True, dtype="float32")
    loop = crossfade_loop(x, rate, xfade)
    loop = match_level(loop, rms_target, peak_cap)
    # libsndfile fecha o processo ao gravar Vorbis de uma vez só (60 s); em blocos funciona.
    with sf.SoundFile(dst, "w", samplerate=rate, channels=loop.shape[1], format="OGG", subtype="VORBIS") as out:
        for i in range(0, len(loop), 24000):
            out.write(loop[i:i + 24000])
    report[os.path.basename(dst)] = f"{len(loop) / rate:.1f}s loop, rms={np.sqrt(np.mean(loop ** 2)):.3f} pico={np.max(np.abs(loop)):.2f}, {os.path.getsize(dst) // 1024} KB"


def sfx(src, dst, peak_target, max_len, fade_out):
    x, rate = sf.read(src, always_2d=True, dtype="float32")
    m = x.mean(axis=1)
    pk = np.max(np.abs(m))
    start = int(np.argmax(np.abs(m) > 0.04 * pk))
    start = max(0, start - int(0.003 * rate))
    m = m[start:]
    win = int(0.01 * rate)
    env = np.array([np.sqrt(np.mean(m[i:i + win] ** 2)) for i in range(0, len(m), win)])
    keep = np.where(env > pk * 10 ** (-42 / 20))[0]
    end = min(len(m), (int(keep[-1]) + 1) * win + int(0.05 * rate) if len(keep) else len(m), int(max_len * rate))
    m = m[:end].copy()
    a, b = min(len(m) // 2, int(0.002 * rate)), min(len(m) // 2, int(fade_out * rate))
    m[:a] *= np.linspace(0, 1, a)
    m[len(m) - b:] *= np.linspace(1, 0, b)
    m *= peak_target / np.max(np.abs(m))
    sf.write(dst, m, rate, subtype="PCM_16")
    report[os.path.basename(dst)] = f"{len(m) / rate:.2f}s pico={np.max(np.abs(m)):.2f}"


if __name__ == "__main__":
    raw = sys.argv[1] if len(sys.argv) > 1 else os.path.join(BACKUP, "musica")
    os.makedirs(os.path.join(BACKUP, "musica"), exist_ok=True)
    for name in ("menu_a.wav", "menu_b.wav", "loading.wav"):
        s = os.path.join(raw, name)
        d = os.path.join(BACKUP, "musica", name)
        if os.path.exists(s) and not os.path.exists(d):
            shutil.copy2(s, d)
    src = os.path.join(BACKUP, "musica")
    # menu_b termina em silêncio (cauda longa): mistura 8 s; menu_a tem fade curto; loading não tem fade
    music(os.path.join(src, "menu_a.wav"), os.path.join(MENU, "menu_music_0.ogg"), 5.0)
    music(os.path.join(src, "menu_b.wav"), os.path.join(MENU, "menu_music_1.ogg"), 8.0)
    # loading_music.ogg saiu daqui em 16/10: agora vem do Gemini via process_loading_music.py.
    # sons de menu: (pico alvo, duração máxima, fade final)
    spec = {"click": (0.50, 0.30, 0.12), "hover": (0.35, 0.20, 0.08), "back": (0.45, 0.40, 0.20), "start": (0.60, 2.2, 0.5)}
    for key, (peak, max_len, fade_out) in spec.items():
        for k in range(4):
            path = os.path.join(MENU, f"{key}_{k}.wav")
            orig = os.path.join(BACKUP, f"{key}_{k}.wav")
            if os.path.exists(path) and not os.path.exists(orig):
                shutil.copy2(path, orig)
            if os.path.exists(orig):
                sfx(orig, path, peak, max_len, fade_out)
    with open(os.path.join(BACKUP, "relatorio_menu.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=1)
    for k, v in sorted(report.items()):
        print(f"{k:22s} {v}")
