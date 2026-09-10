"""Prepara gravações CC0 para o bairro e músicas completas para a rádio.

Requer numpy, scipy e imageio-ffmpeg. Cache fica fora dos recursos de runtime.
As fontes, hashes e transformações ficam no manifesto junto dos arquivos finais.
"""
from pathlib import Path
import urllib.request, re, json, hashlib, subprocess
from concurrent.futures import ThreadPoolExecutor
import numpy as np
from scipy.signal import butter, sosfilt
import imageio_ffmpeg

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'audio/living_city'
CACHE = ROOT / 'tools/.living_audio_cache'
RATE = 32000
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
SOURCES = {
    'cafe': ('alistair.i.macdonald', 'https://freesound.org/people/alistair.i.macdonald/sounds/156909/'),
    'workshop': ('Walter_Odington', 'https://freesound.org/people/Walter_Odington/sounds/26802/'),
    'birds': ('patchytherat', 'https://freesound.org/people/patchytherat/sounds/532146/'),
    'water': ('Noted451', 'https://freesound.org/people/Noted451/sounds/531015/'),
    'street': ('florianreichelt', 'https://freesound.org/people/florianreichelt/sounds/451734/'),
    'gull': ('DaveGould', 'https://freesound.org/people/DaveGould/sounds/32930/'),
    'porto_fm': ('Zane Little Music', 'https://opengameart.org/content/empty-stretch'),
    'porto_noite': ('Julie Damsgaard / Spring Spring', 'https://opengameart.org/content/basically-not-fusion-jazz'),
}

def fetch(item):
    key, (author, page) = item
    manifest = OUT / 'SOURCES.json'
    if manifest.exists():
        known = json.loads(manifest.read_text(encoding='utf-8'))['sources'].get(key)
        if known and known['page'] == page and known['license'] == 'CC0-1.0':
            path = CACHE / (key + Path(known['download']).suffix)
            if path.exists() and hashlib.sha256(path.read_bytes()).hexdigest() == known['sha256']:
                return key, dict(known, path=path)
    html = urllib.request.urlopen(page, timeout=30).read().decode()
    if 'creativecommons.org/publicdomain/zero' not in html:
        raise RuntimeError('Licença CC0 não confirmada: ' + page)
    if 'freesound.org' in page:
        url = re.search(r'https://cdn.freesound.org/previews/[^"\s<>]+-hq.mp3', html).group()
    elif key == 'porto_fm':
        url = 'https://opengameart.org/sites/default/files/empty_stretch_1.mp3'
    else:
        url = 'https://opengameart.org/sites/default/files/fusion%20jazz_0.ogg'
    path = CACHE / (key + Path(url).suffix)
    if not path.exists():
        path.write_bytes(urllib.request.urlopen(url, timeout=60).read())
    print('Fonte:', key, path.stat().st_size, flush=True)
    return key, {'author': author, 'page': page, 'download':url, 'license':'CC0-1.0',
                 'sha256':hashlib.sha256(path.read_bytes()).hexdigest(), 'path':path}

def decode(path, stereo=False):
    channels = 2 if stereo else 1
    data = subprocess.check_output([FFMPEG,'-v','error','-i',str(path),'-f','f32le','-ar',str(RATE),'-ac',str(channels),'-'])
    return np.frombuffer(data, dtype='<f4').reshape(-1,channels).copy()

def normalize(x, rms_db=-22, peak_db=-5):
    x -= x.mean(axis=0)
    rms = max(1e-8, np.sqrt(np.mean(x*x)))
    gain = min(10**(rms_db/20)/rms, 10**(peak_db/20)/max(1e-8,np.max(np.abs(x))))
    return x * gain

def tame_transients(x):
    # Talheres/metal próximos não devem obrigar toda a gravação a ficar inaudível.
    scale = max(1e-6, float(np.sqrt(np.mean(x*x))) * 4.5)
    return np.tanh(x / scale) * scale

def loop(x, seconds=30, offset=0):
    # Sobreposição de 2 s: o fim encontra o começo na mesma gravação.
    overlap = 2*RATE
    size = min(int(seconds*RATE), len(x)-overlap)
    start = min(int(offset*RATE), max(0,len(x)-size-overlap))
    x = x[start:start+size+overlap].copy()
    fade = np.linspace(0,1,overlap)[:,None]
    x[:overlap] = x[-overlap:]*(1-fade) + x[:overlap]*fade
    return x[:-overlap]

def write(name, x, looped=False):
    path = OUT / name
    cmd = [FFMPEG,'-v','error','-y','-f','f32le','-ar',str(RATE),'-ac',str(x.shape[1]),'-i','-']
    cmd += ['-c:a','libvorbis','-q:a','5'] if path.suffix == '.ogg' else ['-c:a','pcm_s16le']
    subprocess.run(cmd+[str(path)],input=x.astype('<f4').tobytes(),check=True)
    return {'file':name,'seconds':round(len(x)/RATE,3),'rms_db':round(float(20*np.log10(max(1e-8,np.sqrt(np.mean(x*x))))),2),
            'peak_db':round(float(20*np.log10(max(1e-8,np.max(np.abs(x))))),2),'loop':looped}

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    CACHE.mkdir(parents=True,exist_ok=True)
    (CACHE/'.gdignore').touch()
    (CACHE/'.gitignore').write_text('*\n')
    with ThreadPoolExecutor(max_workers=6) as pool:
        sources = dict(pool.map(fetch,SOURCES.items()))
    outputs=[]
    for key in ['cafe','workshop','birds','water','street']:
        x=decode(sources[key]['path'])
        x=sosfilt(butter(2,[110,6500],btype='bandpass',fs=RATE,output='sos'),x,axis=0)
        for variant in range(2):
            bed=normalize(tame_transients(loop(x,29+variant*8,variant*33)),-23)
            outputs.append(write(f'{key}_{variant}.ogg',bed,True))
    # Eventos curtos são trechos distintos, com entradas e saídas suaves.
    for key, duration in [('gull',4.5),('birds',5.0),('workshop',3.0)]:
        x=decode(sources[key]['path'])
        for variant in range(3):
            start=int((len(x)/RATE-duration)*(.12+variant*.3)*RATE)
            clip=normalize(x[start:start+int(duration*RATE)].copy(),-23)
            n=int(.15*RATE)
            clip[:n]*=np.linspace(0,1,n)[:,None]
            clip[-n:]*=np.linspace(1,0,n)[:,None]
            outputs.append(write(f'{key}_detail_{variant}.wav',clip))
    for key in ['porto_fm','porto_noite']:
        x=normalize(decode(sources[key]['path'],True),-19,-3)
        n=int(.12*RATE)
        x[:n]*=np.linspace(0,1,n)[:,None]
        x[-n:]*=np.linspace(1,0,n)[:,None]
        outputs.append(write(key+'.ogg',x,True))
    for source in sources.values(): source.pop('path')
    manifest={'sources':sources,'processing':'32000 Hz; ambiente mono filtrado 110–6500 Hz, RMS/peak normalizados, loops com crossfade de 2 s; músicas completas estéreo; detalhes com fades de 150 ms.', 'outputs':outputs}
    (OUT/'SOURCES.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(outputs,indent=2))

if __name__ == '__main__': main()
