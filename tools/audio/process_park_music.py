"""Trata a música do parque gerada no Gemini (Lyria, 15/10/2026): loop sem emenda, volume
casado com a música do menu e saída em Ogg Vorbis. O original (3 min, 48 kHz estéreo, baixado
do vídeo do Gemini pelo navegador) fica em evidence/firefly_originais_20261015/musica.

Uso: python tools/audio/process_park_music.py
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import process_menu_audio as menu

SRC = os.path.join(os.path.dirname(menu.BACKUP), "musica", "park_calliope_raw.wav")
DST = os.path.join(menu.ROOT, "audio", "amusement_park", "park_music.ogg")

if __name__ == "__main__":
    os.makedirs(os.path.dirname(DST), exist_ok=True)
    # Começa baixinho e termina forte: o fim se funde com o começo em 6 s.
    menu.music(SRC, DST, 6.0, rms_target=0.05, peak_cap=0.6)
    for k, v in menu.report.items(): print(k, v)
