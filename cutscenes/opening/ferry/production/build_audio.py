"""Mix natural-duration dialogue, original score and the project's maritime recordings.
Python with numpy/scipy/imageio_ffmpeg. Sources and masters stay in production/.
"""
from pathlib import Path
import json, subprocess, math, wave
import numpy as np
from scipy.signal import butter, sosfilt
import imageio_ffmpeg
ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT.parents[2]
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
RATE = 48000
DURATION = 73.0
RNG = np.random.default_rng(3102026)

def read(path):
    data = subprocess.check_output([FFMPEG,"-v","error","-i",str(path),"-f","f32le","-ar",str(RATE),"-ac","2","-"])
    return np.frombuffer(data,dtype="<f4").reshape(-1,2).copy()

def fade(signal, attack=.02, release=.08):
    n = len(signal)
    weight = np.minimum(1,np.arange(n)/max(1,attack*RATE))*np.minimum(1,np.arange(n)[::-1]/max(1,release*RATE))
    return signal*weight[:,None] if signal.ndim == 2 else signal*weight

def put(track, signal, start, gain=1.0, pan=0.0):
    if signal.ndim == 1: signal=np.column_stack([signal*math.sqrt((1-pan)/2),signal*math.sqrt((1+pan)/2)])
    offset=round(start*RATE)
    count=min(len(signal),len(track)-offset)
    if count>0: track[offset:offset+count]+=signal[:count]*gain

def save(name, signal):
    peak=float(np.max(np.abs(signal)))
    assert peak<.96, (name,peak)
    path=ROOT/"production"/(name+".wav")
    with wave.open(str(path),"wb") as output:
        output.setparams((2,2,RATE,0,"NONE","not compressed"))
        output.writeframes((signal*32767).astype("<i2").tobytes())
    subprocess.run([FFMPEG,"-v","error","-y","-i",str(path),"-c:a","libvorbis","-q:a","5",str(ROOT/(name+".ogg"))],check=True)
    return dict(seconds=len(signal)/RATE,peak_dbfs=round(20*math.log10(max(peak,1e-9)),2))

def loop_recording(path, target_peak, duration=DURATION):
    signal=read(path)
    signal*=target_peak/max(.001,np.max(np.abs(signal)))
    result=np.zeros((round(duration*RATE),2))
    seam=min(.4,len(signal)/RATE*.2)
    source=fade(signal,seam,seam)
    at=0.0
    while at<duration:
        put(result,source,at)
        at+=len(source)/RATE-seam
    return fade(result,1.4,1.0)

def srt_time(t):
    ms=round(t*1000)
    return f"{ms//3600000:02}:{ms//60000%60:02}:{ms//1000%60:02},{ms%1000:03}"

def main():
    manifest=json.loads((ROOT/"production/voices.json").read_text(encoding="utf-8"))
    voices=np.zeros((round(DURATION*RATE),2))
    rows=[]
    previous=0.0
    for line in manifest["lines"]:
        signal=read(ROOT/"production/takes"/line["file"])
        start=line["start"]
        assert start>=previous+.25, "Overlapping natural-duration performances"
        memory=line["id"] in ["release","surprise","clue","identity"]
        if memory:
            signal=sosfilt(butter(2,[300,3700],btype="bandpass",fs=RATE,output="sos"),signal,axis=0)
        signal=fade(signal,.008,.04)
        signal*=.48/max(.001,np.max(np.abs(signal)))
        put(voices,signal,start)
        previous=start+len(signal)/RATE
        row={key:line[key] for key in ["id","speaker","text","en"]}
        row.update(start=start,end=round(previous,3),memory=memory)
        rows.append(row)
    ambience=loop_recording(GAME/"audio/living_city/water_0.ogg",.07)
    ambience+=loop_recording(GAME/"audio/acoustic/engine_diesel_0.wav",.045)
    ambience+=loop_recording(GAME/"audio/weather/rain_bed.wav",.06)
    ambience+=loop_recording(GAME/"audio/weather/rain_drops.wav",.028)
    # Perspective of the remembered call: sea recedes, then returns with the pier.
    time=np.arange(len(ambience))/RATE
    duck=1-.64*np.clip((time-29)/1.5,0,1)*np.clip((54-time)/1.5,0,1)
    ambience*=duck[:,None]
    # Gentle wooden/guitar-like original motif. No licensed music or trailer hit.
    music=np.zeros_like(ambience)
    def pluck(freq,duration=3.8):
        t=np.arange(round(duration*RATE))/RATE
        note=sum(np.sin(2*np.pi*freq*k*t+.05*k)*np.exp(-t*(1.2+k*.23))/k**1.7 for k in range(1,13))
        return fade(note,.008,.45)
    notes=[(1,130.81),(4,196),(7,293.66),(10,164.81),(27,146.83),(30,164.81),(35,110),(40,164.81),(45,146.83),(51,196),(54,130.81),(57,196),(60,261.63),(63,293.66),(67,196),(69,130.81)]
    for i,(start,freq) in enumerate(notes):
        note=pluck(freq)
        gain=.030 if 29<start<52 else .043
        put(music,note,start,gain,-.25 if i%2 else .25)
        put(music,note,start+.23,gain*.25,.45)
    # Brief disconnect belongs to the remembered call, before returning to the sea.
    for start in [52.0,52.35]:
        t=np.arange(round(.13*RATE))/RATE
        put(voices,fade(np.sin(2*np.pi*440*t),.012,.025),start,.027)
    music=fade(music,.1,1.8)
    metrics={"voice":save("voice",voices),"ambience":save("ambience",ambience),"music":save("music",music)}
    save("review_mix",voices+ambience+music)
    timing={"duration":DURATION,"fps":30,"language":"pt-BR","shots":[0.0,7.0,12.0,16.0,21.0,25.0,29.0,36.5,42.0,49.0,54.0,61.0,67.5],"lines":rows}
    (ROOT/"timing.json").write_text(json.dumps(timing,ensure_ascii=False,indent=2),encoding="utf-8")
    (ROOT/"production/audio_metrics.json").write_text(json.dumps(metrics,indent=2),encoding="utf-8")
    for lang in ["pt","en"]:
        blocks=[]
        for i,row in enumerate(rows):
            text=row["text" if lang=="pt" else "en"]
            if row["memory"]: text=("[Lembrança] " if lang=="pt" else "[Memory] ")+text
            blocks.append(f"{i+1}\n{srt_time(row['start'])} --> {srt_time(row['end']+.18)}\n{text}\n")
        (ROOT/"production"/(lang+".srt")).write_text("\n".join(blocks),encoding="utf-8")
    print(json.dumps(metrics,indent=2))

if __name__=="__main__": main()
