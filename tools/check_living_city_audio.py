"""Valida os assets decodificados e exporta uma prévia das capturas reais."""
from pathlib import Path
import json, subprocess
import numpy as np
import imageio_ffmpeg

ROOT = Path(__file__).resolve().parents[1]
BANK = ROOT/'audio/living_city'
REPORT = ROOT/'docs/measurements/living-city-0910'
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()

def decode(path):
    raw = subprocess.check_output([FFMPEG,'-v','error','-i',str(path),'-f','f32le','-ac','2','-ar','32000','-'])
    return np.frombuffer(raw,dtype='<f4').reshape(-1,2)

def metrics(path):
    data = decode(path)
    return data, {'file':path.name,'seconds':round(len(data)/32000,3),
                  'peak_db':round(float(20*np.log10(max(1e-9,np.abs(data).max()))),2),
                  'rms_db':round(float(20*np.log10(max(1e-9,np.sqrt(np.mean(data*data))))),2)}

def main():
    manifest = json.loads((BANK/'SOURCES.json').read_text(encoding='utf-8'))
    measured=[]
    for item in manifest['outputs']:
        data, info=metrics(BANK/item['file'])
        assert np.isfinite(data).all(), item['file']
        assert -70 < info['rms_db'] < -10, info
        assert info['peak_db'] < -1, info
        assert abs(info['seconds'] - item['seconds']) < .1, info
        measured.append(info)
    print('ASSETS: %d arquivos decodificados, sem clipping ou silêncio inesperado' % len(measured))
    REPORT.mkdir(parents=True,exist_ok=True)
    (REPORT/'asset-metrics.json').write_text(json.dumps(measured,indent=2)+'\n')
    clips=[]
    captures=[]
    for name in ['01_diner','02_terminal','03_oficina_rua','04_oficina_dentro','05_cais']:
        path=REPORT/(name+'.wav')
        if not path.exists(): continue
        data,info=metrics(path)
        captures.append(info)
        # Apenas montagem; preserva o volume real da captura do jogo.
        clips += [data, np.zeros((8000,2),dtype=np.float32)]
    if clips:
        subprocess.run([FFMPEG,'-v','error','-y','-f','f32le','-ar','32000','-ac','2','-i','-',
                        '-c:a','libmp3lame','-b:a','160k',str(REPORT/'previa_bairro.mp3')],
                       input=np.concatenate(clips).astype('<f4').tobytes(),check=True)
        (REPORT/'capture-metrics.json').write_text(json.dumps(captures,indent=2)+'\n')
        print('CAPTURA: %d locais; prévia com volumes originais' % len(captures))

if __name__ == '__main__': main()
