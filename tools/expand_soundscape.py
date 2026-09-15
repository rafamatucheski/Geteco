"""Baixa e processa novas estações de rádio e novos ambientes complementares (CC0).

Garante padrão estrito do projeto:
- Músicas completas estéreo a 32 kHz, normalizadas a -19 dB RMS e pico de -3 dB com micro-fades.
- Camada de ambiente noturno mono a 32 kHz, filtrada entre 110 e 6500 Hz, RMS a -23 dB, loop suave.
- Detalhes pontuais mono a 32 kHz, normalizados a -23 dB com fades de 150 ms para eliminar estalos.
- Atualização do manifesto SOURCES.json com hashes SHA-256 e licenças verificadas.
"""
from pathlib import Path
import urllib.request
import re
import json
import hashlib
import subprocess
import numpy as np
from scipy.signal import butter, sosfilt
import imageio_ffmpeg

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'audio/living_city'
CACHE = ROOT / 'tools/.living_audio_cache'
RATE = 32000
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()

HEADERS = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'}

# Fontes CC0 1.0 selecionadas
NEW_STATIONS = {
    'porto_reggae': {
        'author': 'Zane Little Music',
        'title': 'Sweet Coast',
        'page': 'https://opengameart.org/content/reggae',
        'download': 'https://opengameart.org/sites/default/files/regea.mp3',
        'filename': 'regea.mp3'
    },
    'porto_club': {
        'author': 'Zane Little Music',
        'title': 'Electronic Outlaw',
        'page': 'https://opengameart.org/content/electronic-outlaw',
        'download': 'https://opengameart.org/sites/default/files/electronic_outlaw.mp3',
        'filename': 'electronic_outlaw.mp3'
    },
    'porto_estrada': {
        'author': 'Zane Little Music',
        'title': 'Freeway Fumes',
        'page': 'https://opengameart.org/content/freeway-fumes',
        'download': 'https://opengameart.org/sites/default/files/freeway_fumes.mp3',
        'filename': 'freeway_fumes.mp3'
    },
    'porto_cruise': {
        'author': 'Ragnar Random',
        'title': 'Midnight Cruiser',
        'page': 'https://opengameart.org/content/midnight-cruiser',
        'download': 'https://opengameart.org/sites/default/files/midnight_cruiser.mp3',
        'filename': 'midnight_cruiser.mp3'
    }
}

NEW_AMBIENTS = {
    'crickets': {
        'author': '2DPIXX',
        'page': 'https://opengameart.org/content/crickets-ambient-noise-loopable',
        'download': 'https://opengameart.org/sites/default/files/crickets-oneloop.mp3',
        'filename': 'crickets_oneloop.mp3'
    },
    'ship_horn': {
        'author': 'Lord_Tarkus',
        'page': 'https://freesound.org/people/Lord_Tarkus/sounds/777497/',
        'download': 'https://cdn.freesound.org/previews/777/777497_429945-hq.mp3',
        'filename': 'ship_horn_777497.mp3'
    },
    'dog': {
        'author': 'qubodup',
        'page': 'https://freesound.org/people/qubodup/sounds/813116/',
        'download': 'https://cdn.freesound.org/previews/813/813116_71257-hq.mp3',
        'filename': 'dog_bark_813116.mp3'
    }
}

def decode(path, stereo=False):
    channels = 2 if stereo else 1
    data = subprocess.check_output([
        FFMPEG, '-v', 'error', '-i', str(path), '-f', 'f32le', '-ar', str(RATE), '-ac', str(channels), '-'
    ])
    return np.frombuffer(data, dtype='<f4').reshape(-1, channels).copy()

def normalize(x, rms_db=-22, peak_db=-5):
    x -= x.mean(axis=0)
    rms = max(1e-8, np.sqrt(np.mean(x * x)))
    gain = min(10**(rms_db / 20) / rms, 10**(peak_db / 20) / max(1e-8, np.max(np.abs(x))))
    return x * gain

def tame_transients(x):
    scale = max(1e-6, float(np.sqrt(np.mean(x * x))) * 4.5)
    return np.tanh(x / scale) * scale

def loop(x, seconds=30, offset=0):
    overlap = 2 * RATE
    target_len = int(seconds * RATE) + overlap
    while len(x) < target_len + overlap:
        fade = np.linspace(0, 1, overlap)[:, None]
        extended = x.copy()
        x[-overlap:] = x[-overlap:] * (1 - fade) + extended[:overlap] * fade
        x = np.vstack([x, extended[overlap:]])
    size = int(seconds * RATE)
    start = min(int(offset * RATE), max(0, len(x) - size - overlap))
    x = x[start:start + size + overlap].copy()
    fade = np.linspace(0, 1, overlap)[:, None]
    x[:overlap] = x[-overlap:] * (1 - fade) + x[:overlap]*fade
    return x[:-overlap]

def write(name, x, looped=False):
    path = OUT / name
    cmd = [FFMPEG, '-v', 'error', '-y', '-f', 'f32le', '-ar', str(RATE), '-ac', str(x.shape[1]), '-i', '-']
    cmd += ['-c:a', 'libvorbis', '-q:a', '5'] if path.suffix == '.ogg' else ['-c:a', 'pcm_s16le']
    subprocess.run(cmd + [str(path)], input=x.astype('<f4').tobytes(), check=True)
    return {
        'file': name,
        'seconds': round(len(x) / RATE, 3),
        'rms_db': round(float(20 * np.log10(max(1e-8, np.sqrt(np.mean(x * x))))), 2),
        'peak_db': round(float(20 * np.log10(max(1e-8, np.max(np.abs(x))))), 2),
        'loop': looped
    }

def fetch(key, info):
    CACHE.mkdir(parents=True, exist_ok=True)
    source_path = CACHE / info['filename']
    if not source_path.exists():
        print(f"Baixando {key} de {info['download']}...", flush=True)
        req = urllib.request.Request(info['download'], headers=HEADERS)
        data = urllib.request.urlopen(req, timeout=90).read()
        source_path.write_bytes(data)
    else:
        print(f"Usando cache para {key}: {source_path.name}", flush=True)
    sha256 = hashlib.sha256(source_path.read_bytes()).hexdigest()
    return source_path, sha256

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    manifest_path = OUT / 'SOURCES.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8')) if manifest_path.exists() else {'sources': {}, 'outputs': []}
    
    # 1. Processar Novas Rádios
    for key, info in NEW_STATIONS.items():
        src, sha256 = fetch(key, info)
        raw = decode(src, stereo=True)
        x = normalize(raw, rms_db=-19, peak_db=-3)
        # Micro-fades de 120 ms no início e no fim para troca limpa
        n = int(0.12 * RATE)
        x[:n] *= np.linspace(0, 1, n)[:, None]
        x[-n:] *= np.linspace(1, 0, n)[:, None]
        out_meta = write(f"{key}.ogg", x, looped=True)
        manifest['sources'][key] = {
            'author': info['author'],
            'title': info['title'],
            'page': info['page'],
            'download': info['download'],
            'license': 'CC0-1.0',
            'sha256': sha256
        }
        manifest['outputs'] = [o for o in manifest['outputs'] if o['file'] != out_meta['file']]
        manifest['outputs'].append(out_meta)
        print(f"Rádio gerada: {out_meta['file']} ({out_meta['seconds']}s, RMS: {out_meta['rms_db']} dB)", flush=True)
        
    # 2. Processar Camada de Ambiente Noturno (Crickets Bed)
    src_crickets, sha_crickets = fetch('crickets', NEW_AMBIENTS['crickets'])
    x_crickets = decode(src_crickets, stereo=False)
    # Filtro passa-faixa padrão do projeto (110 a 6500 Hz)
    x_crickets = sosfilt(butter(2, [110, 6500], btype='bandpass', fs=RATE, output='sos'), x_crickets, axis=0)
    for variant in range(2):
        duration = 29 + variant * 8  # 29s e 37s
        bed = normalize(tame_transients(loop(x_crickets, seconds=duration, offset=variant * 15)), rms_db=-23)
        out_meta = write(f"crickets_{variant}.ogg", bed, looped=True)
        manifest['outputs'] = [o for o in manifest['outputs'] if o['file'] != out_meta['file']]
        manifest['outputs'].append(out_meta)
        print(f"Ambiente noturno gerado: {out_meta['file']} ({out_meta['seconds']}s)", flush=True)
    manifest['sources']['crickets'] = {
        'author': NEW_AMBIENTS['crickets']['author'],
        'page': NEW_AMBIENTS['crickets']['page'],
        'download': NEW_AMBIENTS['crickets']['download'],
        'license': 'CC0-1.0',
        'sha256': sha_crickets
    }

    # 3. Processar Detalhes Pontuais (Ship Horn & Dog Bark)
    details_cfg = [
        ('ship_horn', NEW_AMBIENTS['ship_horn'], 4.2),
        ('dog', NEW_AMBIENTS['dog'], 2.5)
    ]
    for kind, info, duration in details_cfg:
        src, sha = fetch(kind, info)
        x = decode(src, stereo=False)
        for variant in range(3):
            # Recorta trechos com ligeiro deslocamento
            start = int(min(max(0, len(x) / RATE - duration), variant * 0.8) * RATE)
            clip_len = min(int(duration * RATE), len(x) - start)
            clip = x[start:start + clip_len].copy()
            clip = normalize(clip, rms_db=-23)
            # Fades de 150 ms para evitar cliques
            n = min(int(0.15 * RATE), len(clip) // 3)
            clip[:n] *= np.linspace(0, 1, n)[:, None]
            clip[-n:] *= np.linspace(1, 0, n)[:, None]
            out_meta = write(f"{kind}_detail_{variant}.wav", clip, looped=False)
            manifest['outputs'] = [o for o in manifest['outputs'] if o['file'] != out_meta['file']]
            manifest['outputs'].append(out_meta)
            print(f"Detalhe gerado: {out_meta['file']}", flush=True)
        manifest['sources'][kind] = {
            'author': info['author'],
            'page': info['page'],
            'download': info['download'],
            'license': 'CC0-1.0',
            'sha256': sha
        }

    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print("Processamento concluído com sucesso!", flush=True)

if __name__ == '__main__':
    main()
