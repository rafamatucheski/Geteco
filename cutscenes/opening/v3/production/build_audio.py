"""Produz vozes inteligíveis e stems sincronizados. Python + edge-tts + scipy.

Vozes: Microsoft Edge TTS, via https://github.com/rany2/edge-tts.
Foley e composição: síntese original; ambiente urbano: banco CC0 do projeto.
Os arquivos finais são offline: nenhum acesso à rede acontece no jogo.
"""
from pathlib import Path
import asyncio, json, subprocess, wave, math
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
RATE, LENGTH, CALL_EXTENSION = 44100, 79, 2
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
RNG = np.random.default_rng(110926)
LINES = {
 'pt': [('dante','Quem tá falando?','pt-BR-AntonioNeural')],
 'en': [('release',"Dante? You don't know me, but listen. Your brother was released from prison.",'en-US-AndrewMultilingualNeural'),
        ('harbor',"He was seen in Harbor, near the bus station. Since then he hasn't been answering his phone.",'en-US-AndrewMultilingualNeural'),
        ('dante',"Who's speaking?",'en-US-GuyNeural')]}

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
def edit_time(at): return at if at<27 else at+CALL_EXTENSION
def filt(x, low=0, high=0):
    if low and high: return sosfilt(butter(3, [low, high], btype='bandpass', fs=RATE, output='sos'), x)
    return sosfilt(butter(3, high or low, btype='lowpass' if high else 'highpass', fs=RATE, output='sos'), x)
def noise(d, low=0, high=0): return filt(RNG.normal(0, 1, round(d*RATE)), low, high)
def fade(x, a=.015, b=.08):
    n=len(x); env=np.minimum(np.arange(n)/max(1,a*RATE),1)*np.minimum(np.arange(n)[::-1]/max(1,b*RATE),1)
    return x*env if x.ndim == 1 else x*env[:,None]
def put(track, x, at, gain=1, pan=0, edit=True):
    if x.ndim == 1: x=np.column_stack([x*np.sqrt((1-pan)/2), x*np.sqrt((1+pan)/2)])
    start=round((edit_time(at) if edit else at)*RATE); count=min(len(x),len(track)-start)
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
    global CALL_EXTENSION, LENGTH
    metrics={}; manifest={}; voices={}; prepared={}
    alignment=json.loads((SOURCES/'caller_alignment_v2.json').read_text(encoding='utf-8'))
    caller=read(SOURCES/'pt_caller_qwen_v2.wav')
    latest_end=19+len(caller)/RATE
    for lang, lines in LINES.items():
        prepared[lang]=[]; next_caller=19.0
        for key,text,voice in lines:
            path=SOURCES/f'{lang}_{key}_anonymous_v5.mp3'
            if not path.exists() or path.stat().st_size<100:
                await edge_tts.Communicate(text,voice,rate='+0%',pitch='+0Hz').save(str(path))
            x=read(path)
            env=np.max(np.abs(x),axis=1); active=np.flatnonzero(env>.004)
            if len(active): x=x[max(0,active[0]-int(.06*RATE)):min(len(x),active[-1]+int(.14*RATE))]
            at=27.0 if key=='dante' else next_caller
            prepared[lang].append({'id':key,'text':text,'voice':voice,'x':x,'start':at})
            if key!='dante':
                latest_end=max(latest_end,at+len(x)/RATE)
                next_caller=at+len(x)/RATE+.65
    CALL_EXTENSION=max(0,math.ceil(latest_end+.9-27))
    LENGTH=77+CALL_EXTENSION
    for lang, rows in prepared.items():
        stem=np.zeros((LENGTH*RATE,2)); manifest[lang]=[]
        if lang=='pt':
            # Uma única tomada PT-BR, com a entonação e as pausas originais.
            x=fade(caller,.008,.035); x*=.42/max(np.max(np.abs(x)),.01)
            put(stem,x,19,edit=False)
            for caption in alignment['captions']:
                manifest[lang].append(dict(caption,voice='Qwen3-TTS-VoiceDesign/caller-v2',
                    start=round(19+caption['start'],3),end=round(19+caption['end'],3)))
        for row in rows:
            x=row['x']; at=edit_time(row['start']) if row['id']=='dante' else row['start']
            x=fade(x,.01,.04)
            x*=.42/max(np.max(np.abs(x)),.01)
            put(stem,x,at,edit=False)
            manifest[lang].append({'id':row['id'],'text':row['text'],'voice':row['voice'],
                'start':at,'end':round(at+len(x)/RATE,3)})
        voices[lang]=stem
        metrics['voice_'+lang]=save('voice_'+lang,stem)
    foley=np.zeros((LENGTH*RATE,2)); music=np.zeros_like(foley)
    t=clock(55+CALL_EXTENSION)
    room=(noise(55+CALL_EXTENSION,40,260)*.045+np.sin(t*2*np.pi*60)*.002)
    put(foley,fade(room,1.2,2),0)
    street=GAME/'audio/living_city/street_0.ogg'
    if street.exists():
        x=read(street); x=np.tile(x,(int(68*RATE/len(x))+1,1))
        x=np.column_stack([filt(x[:,0],high=1400),filt(x[:,1],high=1400)])
        put(foley,fade(x[:18*RATE],1,2),0,.10)
        put(foley,fade(x[:7*RATE],.8,1),70,.20)
    # Café: fluxo borbulhante e impacto cerâmico ao pousar.
    t=clock(2.2); pour=noise(2.2,180,4200)*(.12+.07*np.sin(t*37))
    put(foley,fade(pour,.25,.3),1.3,.45,-.15)
    for at,f,g in [(4.2,840,.13),(32.1,170,.12),(51.0,95,.36)]:
        put(foley,impact(f),at,g)
    for at,d,g in [(42.15,.6,.10),(47.0,1.1,.20),(67.7,1.2,.12)]:
        put(foley,rustle(d),at,g,-.10)
    put(foley,impact(1100,.06),42.2,.035)
    # Toque curto e vibração encostada em madeira.
    for at in [16.0,16.65,17.3]:
        t=clock(.38); ring=(np.sin(2*np.pi*660*t)+.32*np.sin(2*np.pi*990*t))*np.exp(-t*4)
        put(foley,fade(ring),at,.065,.22)
        put(foley,fade(np.sin(t*2*np.pi*92)*(.6+.4*np.sin(t*2*np.pi*21))),at,.026,.22)
    put(foley,impact(1100,.09),18.2,.08)
    for at in [29.45,29.8]:
        t=clock(.14); put(foley,fade(np.sin(2*np.pi*440*t),.01,.02),at,.04)
    for at in [47.55,48.05,48.55,49.05,49.55,50.05]: put(foley,impact(75,.25)+rustle(.25)*.20,at,.18)
    # Chuva e estrada entram pela porta e crescem durante a viagem.
    rain=fade(noise(24,350,8500),1.3,1.2)
    put(foley,rain,53,.055)
    put(foley,engine(9),53,.5)
    put(foley,engine(8,True),62,.48)
    put(foley,engine(6),70,.32)
    for at in [64.2,67.7]: put(foley,impact(135,.32),at,.028,.45)
    put(foley,fade(noise(1.3,800,7800),.12,.7),73.8,.17,-.3)
    put(foley,fade(noise(.9,300,4800),.08,.3),75.45,.10,-.3)
    # Motivo original de corda dedilhada em ré menor, com resposta aberta.
    def pluck(freq,d=3.2):
        t=clock(d); base=np.zeros(len(t))
        for k in range(1,15): base+=np.sin(2*np.pi*freq*k*t+.12*k)*np.exp(-t*(1.3+k*.24))/(k**1.55)
        return fade(base,.009,.4)
    for at,freq,g in [(45,146.83,.065),(49.8,174.61,.075),(52.0,220,.08),(55,146.83,.08),(58,174.61,.075),(60,196,.07),(63,146.83,.075),(66,174.61,.065),(69,220,.06),(72,196,.055)]:
        note=pluck(freq)
        put(music,note,at,g,-.22)
        put(music,note,at+.28,g*.24,.40)
        put(music,note,at+.57,g*.10,-.5)
    for at in [54,62,69]:
        t=clock(7); pad=sum(np.sin(2*np.pi*f*t) for f in [73.416,110,174.61])/3*np.sin(np.pi*t/7)**2
        put(music,pad,at,.036)
    music=fade(music,0.1,1.4); foley=fade(foley,.4,.18)
    metrics['foley']=save('foley',foley); metrics['music']=save('music',music)
    for lang in voices: metrics['review_'+lang]=save('review_'+lang,foley+music+voices[lang])
    (OUT/'voice_timing.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False),encoding='utf-8')
    header=('extends RefCounted\n# Gerado por production/build_audio.py.\n'
            f'const CALL_EXTENSION_SECONDS := {float(CALL_EXTENSION)}\n'
            f'const CALLER_HARBOR_START := {manifest["pt"][1]["start"]}\n')
    (ROOT/'voice_timing.gd').write_text(header+'const LINES := '+json.dumps(manifest,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    (OUT/'metrics.json').write_text(json.dumps(metrics,indent=2),encoding='utf-8')
    print(json.dumps(manifest,ensure_ascii=False))

if __name__=='__main__': asyncio.run(main())
