"""Trata a música da tela de carregamento. Desde 20/10/2026 é "Rain on the Borderline" (30 s,
escolhida pelo usuário), que já começa cheia e termina num fade curto a partir de ~28,5 s: o corte
fica antes desse fade e o loop volta a LOOP_OFFSET_SECONDS com a emenda misturada. O original fica
em evidence/firefly_originais_20261015/musica/loading_rain_on_the_borderline_raw.mp3, fora do Git.

Antes (16/10) era a faixa gerada no Gemini (Lyria), que substituiu o
synthwave alegre do Firefly: tema lento (~55-60 BPM) e dramático de cordas, violino, guitarra e
bateria pesada. Os originais (baixados dos vídeos do Gemini) ficam em
evidence/firefly_originais_20261015/musica, fora do Git. A primeira tentativa, a ~75 BPM
(loading_gtadark_raw.wav), ficou só lá: o usuário preferiu a mais lenta.

O arquivo começa limpo na introdução calma (a tela abre baixinho e a faixa cresce sozinha) e o
loop volta para LOOP_OFFSET_SECONDS, não para o zero: os últimos XFADE segundos antes do fim já
contêm a mistura com o trecho que antecede esse ponto, então o salto não tem emenda e a primeira
passada não ouve o final forte por cima da introdução. O LoadingMusic.gd usa o mesmo valor.

Uso: python tools/audio/process_loading_music.py
"""
import os, sys
import numpy as np
import soundfile as sf
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import process_menu_audio as menu

SRC = os.path.join(os.path.dirname(menu.BACKUP), "musica", "loading_rain_on_the_borderline_raw.mp3")
DST = os.path.join(menu.ROOT, "audio", "menu", "loading_music.ogg")
KEEP_SECONDS = 28.5           # o fade final do original começa aqui
XFADE = 3.0
LOOP_OFFSET_SECONDS = 3.0     # precisa ser >= XFADE

if __name__ == "__main__":
    x, rate = sf.read(SRC, always_2d=True, dtype="float32")
    end, xf, offset = int(KEEP_SECONDS * rate), int(XFADE * rate), int(LOOP_OFFSET_SECONDS * rate)
    out = x[:end].copy()
    t = np.linspace(0, 1, xf, endpoint=False)[:, None]
    out[end - xf:end] = x[end - xf:end] * np.cos(t * np.pi / 2) + x[offset - xf:offset] * np.sin(t * np.pi / 2)
    out = menu.match_level(out, 0.05, 0.6)
    with sf.SoundFile(DST, "w", samplerate=rate, channels=out.shape[1], format="OGG", subtype="VORBIS") as f:
        for i in range(0, len(out), 24000):
            f.write(out[i:i + 24000])
    head = float(np.sqrt(np.mean(out[:offset] ** 2)))
    print(f"{os.path.basename(DST)}: {len(out) / rate:.1f}s, loop volta a {LOOP_OFFSET_SECONDS}s, "
          f"rms={np.sqrt(np.mean(out ** 2)):.3f} (início {head:.3f}) pico={np.max(np.abs(out)):.2f}, {os.path.getsize(DST) // 1024} KB")
