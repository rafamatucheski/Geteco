"""Produz vozes inteligíveis e stems sincronizados. Python + edge-tts + scipy.

Vozes: Microsoft Edge TTS, via https://github.com/rany2/edge-tts.
Foley e composição: síntese original; ambiente urbano: banco CC0 do projeto.
Os arquivos finais são offline: nenhum acesso à rede acontece no jogo.
"""
from pathlib import Path
import asyncio, json, subprocess, wave
import numpy as np
from scipy.signal import butter, sosfilt
import imageio_ffmpeg
import edge_tts

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT.parents[2]
OUT = ROOT / 'audio'
OUT.mkdir(exist_ok=True)
SOURCES=ROOT/'production'/'sources'; SOURCES.mkdir(exist_ok=True)
MASTERS=ROOT/'production'/'masters'; MASTERS.mkdir(exist_ok=True)
RATE, LENGTH = 44100, 68
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
RNG = np.random.default_rng(110926)
LINES = {
 'pt': [('release', 'Seu irmão saiu da prisão.', 'pt-BR-ThalitaMultilingualNeural', '+0%', '+0Hz', 19.0),
        ('harbor', 'Viram ele em Harbor. Não tive mais notícias.', 'pt-BR-ThalitaMultilingualNeural', '-2%', '+0Hz', 22.7),
        ('dante', 'Ele falou com você?', 'pt-BR-AntonioNeural', '-12%', '-12Hz', 27.0)],
 'en': [('release', 'Your brother was released from prison.', 'en-US-JennyNeural', '-5%', '-8Hz', 19.0),
        ('harbor', 'He was seen in Harbor. Nothing since then.', 'en-US-JennyNeural', '-2%', '-8Hz', 23.0),
        ('dante', 'Did he talk to you?', 'en-US-GuyNeural', '-10%', '-10Hz', 27.0)]}

def read(path):
    raw = subprocess.check_output([FFMPEG, '-v', 'error', '-i', str(path), '-f', 'f32le', '-ar', str(RATE), '-ac', '2', '-'])
    return np.frombuffer(raw, dtype='<f4').reshape(-1, 2).copy()

def save(name, samples):
    samples = np.asarray(samples)
    if samples.ndim == 1: samples = np.column_stack([samples, samples])
    peak = float(np.max(np.abs(samples)))
    if peak > .91: samples *= .91 / peak
    path = MASTERS / (name + '.wav')
    with wave.open(str(path), 'wb') as w:
        w.setparams((2, 2, RATE, 0, 'NONE', 'not compressed'))
        w.writeframes((samples * 32767).astype('<i2').tobytes())
    subprocess.run([FFMPEG, '-v', 'error', '-y', '-i', str(path), '-c:a', 'libvorbis', '-q:a', '5', str(OUT / (name + '.ogg'))], check=True)
    return {'seconds': round(len(samples)/RATE, 3), 'peak_dbfs': round(20*np.log10(max(peak, 1e-9)), 2)}

def clock(d): return np.arange(round(d*RATE))/RATE
def filt(x, low=0, high=0):
    if low and high: return sosfilt(butter(3, [low, high], btype='bandpass', fs=RATE, output='sos'), x)
    return sosfilt(butter(3, high or low, btype='lowpass' if high else 'highpass', fs=RATE, output='sos'), x)
def noise(d, low=0, high=0): return filt(RNG.normal(0, 1, round(d*RATE)), low, high)
def fade(x, a=.015, b=.08):
    n=len(x); env=np.minimum(np.arange(n)/max(1,a*RATE),1)*np.minimum(np.arange(n)[::-1]/max(1,b*RATE),1)
    return x*env if x.ndim == 1 else x*env[:,None]
def put(track, x, at, gain=1, pan=0):
    if x.ndim == 1: x=np.column_stack([x*np.sqrt((1-pan)/2), x*np.sqrt((1+pan)/2)])
    start=round(at*RATE); count=min(len(x),len(track)-start)
    if count>0: track[start:start+count]+=x[:count]*gain
def impact(freq, d=.35):
    t=clock(d)
    return fade(sum(np.sin(2*np.pi*freq*r*t)*np.exp(-t*(10+9*r))/r for r in [1,1.48,2.31])+.1*noise(d,700,9000)*np.exp(-t*90))
def rustle(d):
    t=clock(d)
    return fade(noise(d,350,7000)*(.18+.3*np.sin(t*22)**4))
def engine(d, inside=False):
    t=clock(d); freq=43 + 1.7*np.sin(t*.5)+.4*np.sin(t*2.7)
    phase=2*np.pi*np.cumsum(freq)/RATE
    out=sum(np.sin(phase*k+.1*k*np.sin(t*6))*np.exp(-k*.30) for k in range(1,13))*.10
    out+=noise(d,35,380 if inside else 2400)*.16
    return fade(out,1.2,1.4)

async def main():
    metrics={}; manifest={}; voices={}
    for lang, lines in LINES.items():
        stem=np.zeros((LENGTH*RATE,2)); manifest[lang]=[]
        for key,text,voice,rate,pitch,at in lines:
            path=SOURCES/f'{lang}_{key}.mp3'
            if lang=='pt' and key!='dante': path=SOURCES/f'{lang}_{key}_thalita_v2.mp3'
            if not path.exists() or path.stat().st_size<100:
                await edge_tts.Communicate(text,voice,rate=rate,pitch=pitch).save(str(path))
            x=read(path)
            # Retirar somente silêncio de arquivo, preservando a interpretação.
            env=np.max(np.abs(x),axis=1); active=np.flatnonzero(env>.004)
            if len(active): x=x[max(0,active[0]-int(.06*RATE)):min(len(x),active[-1]+int(.14*RATE))]
            deadline=22.4 if key=='release' else (26.75 if key=='harbor' else 29.2)
            available=deadline-at
            if len(x)/RATE>available:
                # Ajuste leve de tempo, preservando pitch; nunca corta palavras.
                temp=MASTERS/f'{lang}_{key}_fit.wav'
                factor=(len(x)/RATE)/available
                subprocess.run([FFMPEG,'-v','error','-y','-i',str(path),'-af',f'atempo={factor:.5f}','-ar',str(RATE),str(temp)],check=True)
                x=read(temp)
                env=np.max(np.abs(x),axis=1); active=np.flatnonzero(env>.004)
                if len(active): x=x[max(0,active[0]-int(.02*RATE)):active[-1]+int(.07*RATE)]
            if key!='dante':
                # Coloração telefônica leve mantém consoantes e o timbre natural.
                phone=np.column_stack([filt(x[:,0],180,4800),filt(x[:,1],180,4800)])
                x=.82*phone+.18*x
            x=fade(x,.01,.04)
            x*=.42/max(np.max(np.abs(x)),.01)
            put(stem,x,at)
            manifest[lang].append({'id':key,'text':text,'voice':voice,'start':at,'end':round(at+len(x)/RATE,3)})
        voices[lang]=stem
        metrics['voice_'+lang]=save('voice_'+lang,stem)
    foley=np.zeros((LENGTH*RATE,2)); music=np.zeros_like(foley)
    t=clock(46)
    room=(noise(46,40,260)*.045+np.sin(t*2*np.pi*60)*.002)
    put(foley,fade(room,1.2,2),0)
    street=GAME/'audio/living_city/street_0.ogg'
    if street.exists():
        x=read(street); x=np.tile(x,(int(68*RATE/len(x))+1,1))
        x=np.column_stack([filt(x[:,0],high=1400),filt(x[:,1],high=1400)])
        put(foley,fade(x[:18*RATE],1,2),0,.10)
        put(foley,fade(x[:7*RATE],.8,1),61,.20)
    # Café: fluxo borbulhante e impacto cerâmico ao pousar.
    t=clock(2.2); pour=noise(2.2,180,4200)*(.12+.07*np.sin(t*37))
    put(foley,fade(pour,.25,.3),1.3,.45,-.15)
    for at,f,g in [(4.1,840,.13),(8.4,220,.10),(11.1,110,.22),(32.1,170,.12),(37.7,130,.15),(41.65,920,.08),(44.5,95,.36)]:
        put(foley,impact(f),at,g)
    for at,d,g in [(6.8,.6,.18),(10.6,.5,.16),(33.7,.8,.3),(36.2,1.2,.23),(38.0,1.1,.24),(41.55,.45,.17),(53.25,1.2,.22)]:
        put(foley,rustle(d),at,g,-.10)
    # Toque curto e vibração encostada em madeira.
    for at in [16.0,16.65,17.3]:
        t=clock(.38); ring=(np.sin(2*np.pi*660*t)+.32*np.sin(2*np.pi*990*t))*np.exp(-t*4)
        put(foley,fade(ring),at,.065,.22)
        put(foley,fade(np.sin(t*2*np.pi*92)*(.6+.4*np.sin(t*2*np.pi*21))),at,.026,.22)
    put(foley,impact(1100,.09),18.2,.08)
    for at in [29.45,29.8,32.0,32.35]:
        t=clock(.14); put(foley,fade(np.sin(2*np.pi*440*t),.01,.02),at,.04)
    for at in [42.2,42.75,43.3]: put(foley,impact(75,.25)+rustle(.25)*.20,at,.22)
    # Chuva e estrada entram pela porta e crescem durante a viagem.
    rain=fade(noise(24,350,8500),1.3,1.2)
    put(foley,rain,44,.055)
    put(foley,engine(9),44,.5)
    put(foley,engine(8,True),53,.48)
    put(foley,engine(6),61,.32)
    for at in [55.2,58.7]: put(foley,impact(135,.32),at,.028,.45)
    put(foley,fade(noise(1.3,800,7800),.12,.7),64.8,.17,-.3)
    put(foley,fade(noise(.9,300,4800),.08,.3),66.45,.10,-.3)
    # Motivo original de corda dedilhada em ré menor, com resposta aberta.
    def pluck(freq,d=3.2):
        t=clock(d); base=np.zeros(len(t))
        for k in range(1,15): base+=np.sin(2*np.pi*freq*k*t+.12*k)*np.exp(-t*(1.3+k*.24))/(k**1.55)
        return fade(base,.009,.4)
    for at,freq,g in [(38,146.83,.085),(40.8,174.61,.075),(43.0,220,.08),(46,146.83,.08),(49,174.61,.075),(51,196,.07),(54,146.83,.075),(57,174.61,.065),(60,220,.06),(63,196,.055)]:
        note=pluck(freq)
        put(music,note,at,g,-.22)
        put(music,note,at+.28,g*.24,.40)
        put(music,note,at+.57,g*.10,-.5)
    for at in [45,53,60]:
        t=clock(7); pad=sum(np.sin(2*np.pi*f*t) for f in [73.416,110,174.61])/3*np.sin(np.pi*t/7)**2
        put(music,pad,at,.036)
    music=fade(music,0.1,1.4); foley=fade(foley,.4,.18)
    metrics['foley']=save('foley',foley); metrics['music']=save('music',music)
    for lang in voices: metrics['review_'+lang]=save('review_'+lang,foley+music+voices[lang])
    (OUT/'voice_timing.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False),encoding='utf-8')
    (ROOT/'voice_timing.gd').write_text('extends RefCounted\n# Gerado por production/build_audio.py; incluído automaticamente no export.\nconst LINES := '+json.dumps(manifest,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    (OUT/'metrics.json').write_text(json.dumps(metrics,indent=2),encoding='utf-8')
    print(json.dumps(manifest,ensure_ascii=False))

if __name__=='__main__': asyncio.run(main())
