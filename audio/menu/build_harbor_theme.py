"""Original 96 BPM instrumental menu loop. Run with Python + NumPy."""
from pathlib import Path
import wave
import numpy as np

RATE = 22050
BEAT = 60 / 96
LENGTH = 32 * BEAT
N = round(RATE * LENGTH)
mix = np.zeros((N, 2))
rng = np.random.default_rng(908)

def add(signal, beat, gain=1., pan=0.):
    start = round(beat * BEAT * RATE)
    indices = (start + np.arange(len(signal))) % N
    mix[indices, 0] += signal * gain * np.sqrt((1-pan)/2)
    mix[indices, 1] += signal * gain * np.sqrt((1+pan)/2)

def clock(duration):
    return np.arange(round(duration * RATE)) / RATE

def tone(freq, duration, decay):
    t = clock(duration)
    return (np.sin(2*np.pi*freq*t) + .23*np.sin(4*np.pi*freq*t)) * np.minimum(t/.008, 1) * np.exp(-t*decay) * np.minimum((duration-t)/.025, 1)

# Sparse minor bass motif, low sustained harmony and dry half-time percussion.
roots = [73.416, 73.416, 65.406, 58.270, 73.416, 73.416, 58.270, 55.]
for bar, root in enumerate(roots):
    for beat, pitch, gain in [(0,root,.32),(1.75,root,.18),(2.5,root,.27),(3.5,root*1.5,.14)]:
        add(tone(pitch,.48,5), bar*4+beat,gain)
    for ratio in [1, 1.189207, 1.498307]:
        t = clock(4*BEAT)
        pad = np.sin(2*np.pi*root*2*ratio*t) * np.sin(np.pi*t/(4*BEAT))**2
        add(pad,bar*4,.035,(-.5 if ratio==1 else .5))
    for beat in [0, 1.5, 2.75]:
        t=clock(.35)
        kick=np.sin(2*np.pi*(45*t + 65*.025*(1-np.exp(-t/.025)))) * np.exp(-t*18) * np.minimum(t/.002,1)
        add(kick,bar*4+beat,.48)
    t=clock(.18)
    noise=rng.uniform(-1,1,len(t))
    snare=(noise*.6+np.sin(2*np.pi*180*t)*.4)*np.exp(-t*30)*np.minimum(t/.002,1)
    add(snare,bar*4+2,.23,.1)
    for step in range(8):
        t=clock(.05)
        noise=rng.uniform(-1,1,len(t))
        hat=np.diff(noise,prepend=0)*np.exp(-t*95)*np.minimum(t/.001,1)
        add(hat,bar*4+step*.5+(0.035 if step%2 else 0),.038 if step%2 else .06,.35)
    if bar in [1,3,5,7]:
        for beat,ratio in [(0,2),(1.5,2.378414),(3,2.244924)]:
            motif=tone(root*ratio,.9,4)
            add(motif,bar*4+beat,.10,-.25)
            add(motif,bar*4+beat+.75,.025,.5)

mix=np.tanh(mix*1.3)
mix*=.82/max(1.,np.max(np.abs(mix)))
pcm=(mix*32767).astype('<i2')
out=Path(__file__).with_name('harbor_night_menu.wav')
with wave.open(str(out),'wb') as file:
    file.setnchannels(2)
    file.setsampwidth(2)
    file.setframerate(RATE)
    file.writeframes(pcm.tobytes())
print(f'{out}: {LENGTH}s, peak={np.max(np.abs(mix)):.3f}')
