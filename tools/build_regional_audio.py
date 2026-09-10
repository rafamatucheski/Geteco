"""Prepara arquivos CC0 de vento/metal; cache local e manifesto de procedência."""
import json, hashlib, urllib.request
from concurrent.futures import ThreadPoolExecutor
import numpy as np
from scipy.signal import butter, sosfilt
import build_living_city_audio as audio

SOURCES = {
    'wind': ('Luke.RUSTLTD', 'wind1', 'wind1.wav'),
    **{name: ('Brian MacIntosh / BMacZero', 'metal-impact-sounds', name+'.wav') for name in ['bing1','bong1','clink1_0','clink2','clink3','thud2']},
}

def fetch(item):
    key, (author, slug, file) = item
    page = 'https://opengameart.org/content/'+slug
    url = 'https://opengameart.org/sites/default/files/'+file
    path = audio.CACHE / ('regional_'+file)
    manifest = audio.OUT/'SOURCES.json'
    known = json.loads(manifest.read_text(encoding='utf8'))['sources'].get(key) if manifest.exists() else None
    if known and path.exists() and hashlib.sha256(path.read_bytes()).hexdigest() == known['sha256']:
        return key, dict(known, path=path)
    html = urllib.request.urlopen(page, timeout=30).read().decode()
    assert 'creativecommons.org/publicdomain/zero' in html and url in html
    if not path.exists(): path.write_bytes(urllib.request.urlopen(url, timeout=45).read())
    return key, dict(author=author, page=page, download=url, license='CC0-1.0', sha256=hashlib.sha256(path.read_bytes()).hexdigest(), path=path)

def main():
    audio.OUT = audio.ROOT/'audio/regional'
    audio.OUT.mkdir(exist_ok=True)
    with ThreadPoolExecutor(max_workers=4) as pool: sources = dict(pool.map(fetch, SOURCES.items()))
    outputs = []
    wind = audio.decode(sources['wind']['path'])
    wind = sosfilt(butter(2,[110,6500],btype='bandpass',fs=audio.RATE,output='sos'),wind,axis=0)
    for i in range(2):
        outputs.append(audio.write(f'wind_{i}.ogg',audio.normalize(audio.loop(wind,31+i*6,i*17),-23),True))
    for i,start in enumerate([3,22,42]):
        clip=audio.normalize(wind[start*audio.RATE:(start+7)*audio.RATE].copy(),-22)
        clip[:audio.RATE]*=np.linspace(0,1,audio.RATE)[:,None]
        clip[-audio.RATE:]*=np.linspace(1,0,audio.RATE)[:,None]
        outputs.append(audio.write(f'gust_{i}.ogg',clip))
    metals=[]
    for key in list(SOURCES)[1:]:
        clip=audio.normalize(audio.decode(sources[key]['path']),-21,-4)
        n=min(160,len(clip)//4)
        clip[:n]*=np.linspace(0,1,n)[:,None]
        clip[-n:]*=np.linspace(1,0,n)[:,None]
        metals.append(clip)
    for i in range(6):
        # Três batidas isoladas e três cascatas de peças batendo/desmontando.
        clip=metals[i].copy()
        if i>=3:
            clip=np.zeros((3*audio.RATE,1))
            for j,offset in enumerate([0,.16,.38,.68,1.04,1.42]):
                piece=metals[(i+j)%6]
                start=int(offset*audio.RATE)
                length=min(len(piece),len(clip)-start)
                clip[start:start+length]+=piece[:length]*(.85**j)
            clip=audio.normalize(clip,-21,-4)
        outputs.append(audio.write(f'scrap_{i}.wav',clip))
    for source in sources.values(): source.pop('path')
    (audio.OUT/'SOURCES.json').write_text(json.dumps({'sources':sources,'processing':'32 kHz mono; vento pré-renderizado em PureData pelo autor, filtrado 110–6500 Hz, loops crossfade 2 s; rajadas fade 1 s; metal com fades 5 ms, três batidas e três composições de peças caindo; RMS/peak normalizados.','outputs':outputs},ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print(json.dumps(outputs,indent=2))

if __name__=='__main__': main()
