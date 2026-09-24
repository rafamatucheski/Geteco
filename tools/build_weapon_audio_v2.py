"""Original offline mono SFX: pressure, crack, mechanism, short reflections.
No external recordings and no synthesis work on the game's audio thread.
"""
from pathlib import Path
import json
import wave
import numpy as np
from scipy.signal import butter, sosfilt

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "audio/combat/arsenal_v2"
RATE = 44100
PRESETS = {"pistol":(.56,45,7200,.63), "magnum":(.95,23,5700,.63),
           "shotgun":(.93,18,4700,.67), "smg":(.28,60,7100,.55),
           "ak47":(.45,33,6100,.58), "m4a1":(.35,46,7000,.56),
           "hunting_rifle":(.90,24,5800,.61)}

def band(rng,n,low,high):
    raw = sosfilt(butter(2,[low,high],fs=RATE,btype="bandpass",output="sos"),rng.normal(size=n))
    return raw/max(np.std(raw),1e-9)

def env(t,start,decay,attack=.0005):
    age = np.maximum(0,t-start)
    return (t>=start)*(1-np.exp(-age/attack))*np.exp(-age*decay)

def render(kind,take,suppressed=False):
    length,decay,bright,peak = PRESETS[kind]
    rng = np.random.default_rng(91900+list(PRESETS).index(kind)*50+take)
    n = int(length*RATE)
    t = np.arange(n)/RATE
    raw = band(rng,n,1000,bright)*env(t,0,290)*.72
    raw += band(rng,n,65,1450)*env(t,.001,decay)*.66
    raw += band(rng,n,45,280)*env(t,.002,decay*.9)*.21
    if kind == "pistol":
        raw += band(rng,n,1800,9000)*env(t,.034,190)*.15
        raw += band(rng,n,600,4200)*env(t,.065,155)*.11
    elif kind == "magnum":
        raw += band(rng,n,250,2300)*env(t,.008,35)*.38
        raw += band(rng,n,1500,6800)*env(t,.012,175)*.22
    elif kind == "shotgun":
        raw += band(rng,n,180,2800)*env(t,.006,24)*.42
        for start,gain in [(.19,.13),(.32,.17)]:
            raw += band(rng,n,800,5400)*env(t,start,65,.003)*gain
            raw += band(rng,n,350,2700)*env(t,start+.044,160)*gain*1.1
    dry = raw.copy()
    if suppressed:
        raw = sosfilt(butter(2,2600,fs=RATE,output="sos"),dry)*.32
        raw += band(rng,n,1600,6800)*env(t,.035,130)*.1
        peak = .33
    else:
        reflection = sosfilt(butter(2,2600,fs=RATE,output="sos"),dry)
        for delay,level in [(.052,.11),(.099,.065),(.183,.04)]:
            shift = int((delay+rng.uniform(-.007,.007))*RATE)
            raw[shift:] += reflection[:-shift]*level
    raw = sosfilt(butter(2,35,fs=RATE,btype="highpass",output="sos"),raw)
    raw *= np.minimum(1,t/.00025)*np.minimum(1,(length-t)/.03)
    raw -= np.mean(raw)
    raw *= peak/max(np.max(np.abs(raw)),1e-8)
    raw[0] = raw[-1] = 0
    return raw

def write(path,data):
    with wave.open(str(path),"wb") as handle:
        handle.setparams((1,2,RATE,0,"NONE","not compressed"))
        handle.writeframes(np.round(data*32767).astype("<i2").tobytes())

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    metrics = {}
    for kind in PRESETS:
        for suppressed in [False,True]:
            if not suppressed and kind not in ["pistol","magnum","shotgun"]: continue
            if suppressed and kind == "magnum": continue
            for take in range(5):
                key = ("suppressed_" if suppressed else "")+kind+f"_{take}"
                data = render(kind,take,suppressed)
                write(OUT/f"{key}.wav",data)
                metrics[key] = {"seconds":len(data)/RATE,"peak":float(np.max(np.abs(data))),"rms":float(np.sqrt(np.mean(data**2))),"clipped":int(np.sum(np.abs(data)>=1))}
    (OUT/"metrics.json").write_text(json.dumps(metrics,indent=2),encoding="utf-8")
    preview = []
    for kind in ["pistol","magnum","shotgun"]:
        preview.extend([render(kind,0),np.zeros(int(RATE*.65)),render(kind,1),np.zeros(RATE)])
    write(OUT/"preview.wav",np.concatenate(preview))
    print(f"Created {len(metrics)} mono takes; peak <= {max(x['peak'] for x in metrics.values()):.3f}; no clipped samples")

if __name__ == "__main__": main()
