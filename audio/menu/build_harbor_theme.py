"""Original Geteco urban title theme, 92 BPM / E minor / 24 bars.

Offline sample-based production using GeneralUser GS 2.0.3 and TinySoundFont.
Runtime still loads one stereo WAV. See tools/menu_music/README.md for setup.
"""
from pathlib import Path
import json
import sys
import wave
import numpy as np
from scipy.signal import butter, sosfilt

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools/menu_music/packages'))
import tinysoundfont

RATE = 22050
BPM = 92
BEAT = 60 / BPM
BARS = 24
N = round(BARS * 4 * BEAT * RATE)
FONT = ROOT / 'tools/menu_music/GeneralUser-GS.sf2'
RNG = np.random.default_rng(20260914)
EVENTS = {name: [] for name in ['bass', 'keys', 'drums']}


def note(track, beat, pitch, duration, velocity):
    # One shared eighth-note swing grid keeps every part locked together.
    if abs(beat % 1 - .5) < .001:
        beat += .035
    start = max(0, round(beat * BEAT * RATE))
    end = start + round(duration * BEAT * RATE)
    velocity = int(np.clip(velocity + RNG.integers(-2, 3), 1, 110))
    EVENTS[track].append((start, 1, pitch, velocity))
    EVENTS[track].append((end, 0, pitch, 0))


# One four-bar phrase. Keyboard and bass share the three main accents;
# kick reinforces those accents, snare marks the same backbeat throughout.
# Harmony is voiced inside the keyboard riff, never a competing ostinato.
ROOTS = [40, 40, 33, 35]
LOW_VOICES = [[52,55], [52,55], [52,57], [51,57]]
TOP_LINE = [[64,67,62], [64,67,64], [64,67,60], [63,66,59]]
ACCENTS = [0., 1.5, 2.5]
for bar in range(BARS):
    base=bar*4
    c=bar%4
    sparse=12<=bar<16
    # The same pocket continues through the quieter section.
    for index,offset in enumerate(ACCENTS):
        interval=[0,0,7][index]
        note('bass',base+offset,ROOTS[c]+interval,[.7,.48,.65][index], [84,75,79][index])
        note('drums',base+offset,36,.14,[78,61,70][index])
        duration=[.65,.4,.65][index]
        top=TOP_LINE[c][index]
        note('keys',base+offset,top,duration,[76,66,71][index]-(8 if sparse else 0))
        if not sparse or index==0:
            for pitch in LOW_VOICES[c]:
                note('keys',base+offset,pitch,duration,48 if index==0 else 43)
    # Brief bass pickup belongs to the same eighth-note grid.
    if c in (1,3):
        note('bass',base+3.5,ROOTS[c]+7,.27,57)
    for offset,velocity in [(1.,63),(3.,68)]:
        note('drums',base+offset,38,.16,velocity)
    for step in range(8):
        if sparse and step%2: continue
        note('drums',base+step*.5,42,.09,43 if step%2==0 else 31)


def render(track, preset, pan, drums=False):
    synth=tinysoundfont.Synth(gain=-10, samplerate=RATE)
    sfid=synth.sfload(str(FONT))
    synth.program_select(0,sfid,0,preset,is_drums=drums)
    synth.control_change(0,10,pan)
    # Repeat once before the retained pass so sample releases carry over.
    events=sorted((time+cycle*N,on,pitch,velocity)
                  for cycle in range(2) for time,on,pitch,velocity in EVENTS[track])
    audio=np.zeros((2*N,2),dtype=np.float32)
    cursor=0
    for time,on,pitch,velocity in events:
        time=min(time,2*N)
        if time>cursor:
            audio[cursor:time]=np.frombuffer(synth.generate_simple(time-cursor),np.float32).reshape(-1,2)
            cursor=time
        if on: synth.noteon(0,pitch,velocity)
        else: synth.noteoff(0,pitch)
    if cursor<2*N:
        audio[cursor:]=np.frombuffer(synth.generate_simple(2*N-cursor),np.float32).reshape(-1,2)
    synth.sfunload(sfid)
    return audio[N:].astype(np.float64)


# Three roles only: bass, one electric-piano riff, and drums.
SETUP = {'bass':(33,64,.024,1500), 'keys':(4,62,.025,2800),
         'drums':(0,64,.021,6000)}
mix=np.zeros((N,2))
report={}
for track,(preset,pan,target,cutoff) in SETUP.items():
    stem=render(track,preset,pan,track=='drums')
    # Warm periodic filtering avoids a cold filter-state seam.
    sos=butter(2,cutoff,fs=RATE,output='sos')
    stem=sosfilt(sos,np.concatenate([stem,stem]),axis=0)[N:]
    rms=float(np.sqrt(np.mean(stem**2)))
    assert rms>1e-6, f'Silent instrument: {track}'
    stem*=min(target/rms, .18/max(float(np.max(np.abs(stem))),1e-9))
    report[track]={'rms':float(np.sqrt(np.mean(stem**2))),'peak':float(np.max(np.abs(stem)))}
    mix+=stem
    if track == 'keys':
        for seconds,gain in [(.043,.07),(.079,.045),(.127,.025)]:
            mix+=np.roll(stem[:,::-1],round(seconds*RATE),axis=0)*gain
mix-=mix.mean(axis=0)
# Keep the quieter level from the user's volume correction; never boost master.
gain=min(1.,.045/max(float(np.sqrt(np.mean(mix**2))),1e-9),.32/max(float(np.max(np.abs(mix))),1e-9))
mix*=gain
pcm=np.rint(mix*32767).astype('<i2')
out=Path(__file__).with_name('harbor_night_menu.wav')
with wave.open(str(out),'wb') as file:
    file.setnchannels(2); file.setsampwidth(2); file.setframerate(RATE)
    file.writeframes(pcm.tobytes())
report['master']={'seconds':N/RATE,'rms':float(np.sqrt(np.mean(mix**2))),'peak':float(np.max(np.abs(mix))),'seam':float(np.max(np.abs(mix[0]-mix[-1])))}
print(json.dumps(report,indent=2))
