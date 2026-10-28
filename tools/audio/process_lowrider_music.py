"""Trata a trilha G-funk do encontro de lowriders gerada no Gemini (28/10/2026, "Sunday Chrome",
2:49, 44,1 kHz estéreo, MP3 baixado pelo botão "Somente áudio"). A faixa tem groove constante e um
fade de ~10 s no fim: corta antes do fade, funde o fim com o começo (loop sem emenda) e casa o
volume com a PORTO GROOVE (rms ~0,11), que toca no mesmo encontro. Original em
evidence/muscle-lowrider-20261027/audio (fora do Git).

Uso: python -I tools/audio/process_lowrider_music.py
"""
import os, subprocess, sys
import numpy as np
import soundfile as sf
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import process_menu_audio as menu

FFMPEG = "C:/Users/rafae/AppData/Local/Programs/Python/Python311/Lib/site-packages/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe"
SRC = os.path.join(menu.ROOT, "evidence", "muscle-lowrider-20261027", "audio", "gfunk_meet_raw.mp3")
WAV = os.path.join(os.path.dirname(SRC), "gfunk_meet_raw.wav")
CUT = os.path.join(os.path.dirname(SRC), "gfunk_meet_cut.wav")
DST = os.path.join(menu.ROOT, "audio", "lowrider", "gfunk_meet.ogg")
## Mesmo nível da PORTO GROOVE (medido: rms 0,112, pico 0,6).
RMS_TARGET = 0.112
XFADE = 4.0


def fade_start(mono, rate):
    """Início do fade final: último trecho de 2 s acima de metade da mediana."""
    win = int(2 * rate)
    levels = [float(np.sqrt(np.mean(mono[i:i + win] ** 2))) for i in range(0, len(mono) - win, win)]
    floor = np.median(levels) * 0.5
    last = max(i for i, v in enumerate(levels) if v > floor)
    return last * win


if __name__ == "__main__":
    subprocess.run([FFMPEG, "-y", "-loglevel", "error", "-i", SRC, WAV], check=True)
    x, rate = sf.read(WAV, always_2d=True, dtype="float32")
    end = fade_start(x.mean(1), rate)
    sf.write(CUT, x[:end], rate)
    os.makedirs(os.path.dirname(DST), exist_ok=True)
    menu.music(CUT, DST, XFADE, rms_target=RMS_TARGET, peak_cap=0.6)
    print(f"corte em {end / rate:.1f} s de {len(x) / rate:.1f} s")
    for k, v in menu.report.items(): print(k, v)
