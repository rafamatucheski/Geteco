"""Original 84 BPM garage blues/funk loop; no recordings or external samples.

Render three identical twelve-bar choruses, take the central chorus with its
preceding note tails, then add circular stereo room taps before Ogg export.
"""
from pathlib import Path
import json
import numpy as np
import soundfile as sf
import subprocess
import imageio_ffmpeg

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "audio/workshop"
EVIDENCE = ROOT / "artifacts/tuning-design-20261019/workshop-music"
RATE, BPM = 44100, 84
BEAT = RATE * 60 // BPM
LENGTH = BEAT * 48
mix = np.zeros((LENGTH * 3, 2), dtype=np.float64)
event = 0


def tone(midi, duration, kind, seed):
    t = np.arange(int(duration * RATE)) / RATE
    hz = 440 * 2 ** ((midi - 69) / 12)
    phase = 2 * np.pi * hz * t
    attack = 1 - np.exp(-t * (170 if kind == "bass" else 420))
    if kind == "bass":
        y = np.sin(phase) + .22*np.sin(2*phase) + .06*np.sin(3*phase)
        env = attack * np.exp(-t*3.7)
    elif kind == "keys":
        y = np.sin(phase + .9*np.sin(2*phase)*np.exp(-t*8)) + .16*np.sin(3*phase)
        env = attack*np.exp(-t*5.5)
    elif kind == "guitar":
        y = sum(np.sin(k*phase + .08*k)*np.exp(-t*(3+k*2))/k for k in range(1,9))
        env = attack*np.exp(-t*2)
    else:
        vibrato = .004*np.sin(2*np.pi*5.2*t)*(1-np.exp(-t*9))
        phase = 2*np.pi*hz*(t + vibrato/(2*np.pi*5.2))
        y = np.sin(phase)+.22*np.sin(2*phase)+.07*np.sin(3*phase)
        env = attack*np.exp(-t*5)
    release = np.minimum(1, np.maximum(0,(duration-t)/.025))
    return y * env * release


def drum(kind, seed):
    rng = np.random.default_rng(seed)
    duration = {"kick":.32,"snare":.24,"hat":.11,"open":.25}[kind]
    t = np.arange(int(duration*RATE))/RATE
    noise = rng.normal(0,1,len(t))
    if kind == "kick":
        phase = 2*np.pi*(49*t + 42*(1-np.exp(-t*36))/36)
        y = np.sin(phase)*np.exp(-t*15)+.035*noise*np.exp(-t*140)
    elif kind == "snare":
        low_noise = np.convolve(noise,np.ones(6)/6,"same")
        y = .55*low_noise*np.exp(-t*23)+.12*np.sin(2*np.pi*175*t)*np.exp(-t*32)
    else:
        high_noise = noise-np.convolve(noise,np.ones(10)/10,"same")
        y = .16*high_noise*np.exp(-t*(55 if kind=="hat" else 23))
    return y*np.minimum(1,t/.002)*np.minimum(1,(duration-t)/.015)


def add(at, sound, gain, pan=0):
    global event
    stereo_gain = np.array([np.sqrt((1-pan)/2),np.sqrt((1+pan)/2)])*gain
    for repeat in range(3):
        start = repeat*LENGTH + round(at*BEAT)
        end = min(len(mix),start+len(sound))
        if end > start:
            mix[start:end] += sound[:end-start,None]*stereo_gain
    event += 1


# Dominant ninth voicings and an original, sparse pentatonic answer phrase.
roots = [40,40,40,40,45,45,40,40,47,45,40,47]
voicings = {40:[56,62,66,71],45:[55,61,64,71],47:[57,63,66,73]}
for bar, root in enumerate(roots):
    base = bar*4
    for beat, note in zip([0,.76,1.5,2,2.77,3.5],[root,root+12,root+7,root,root+10,root+7]):
        add(base+beat,tone(note,.60,"bass",event),.23)
    for beat in [.78,1.76,2.78,3.72]:
        for index,note in enumerate(voicings[root]):
            add(base+beat+index*.012,tone(note,.72,"keys",event),.067,-.25)
    for beat in [.5,2.5,3.5]:
        for index,note in enumerate(voicings[root][1:]):
            add(base+beat+index*.007,tone(note,.32,"guitar",event),.065,.34)
    for beat in [0,1.73,2.5]: add(base+beat,drum("kick",1000+event),.43)
    for beat in [1,3]: add(base+beat,drum("snare",1000+event),.37,-.08)
    for eighth in range(8):
        at = eighth*.5 + (.06 if eighth%2 else 0)
        add(base+at,drum("open" if eighth==7 and bar%2 else "hat",1000+event),.28 if eighth%2 else .21,.28)
for at,note,length in [(6.5,64,.35),(7.25,67,.42),(14.5,69,.38),(15.25,67,.47),(22.5,64,.38),(23.25,62,.50),(30.5,67,.32),(31.2,69,.45),(38.5,70,.30),(39.25,69,.43),(42.5,67,.33),(43.25,64,.48),(46.5,62,.35),(47.25,63,.36)]:
    add(at,tone(note,length,"lead",event),.11,.10)

chorus = mix[LENGTH:2*LENGTH].copy()
for milliseconds,gain in [(37,.085),(113,.065),(229,.035)]:
    chorus += np.roll(chorus[:,::-1],round(milliseconds*RATE/1000),axis=0)*gain
chorus = np.tanh(chorus*1.35)
chorus *= .14 / np.sqrt(np.mean(chorus**2))
if np.max(np.abs(chorus))>.82: chorus *= .82/np.max(np.abs(chorus))
OUT.mkdir(parents=True,exist_ok=True)
EVIDENCE.mkdir(parents=True,exist_ok=True)
sf.write(EVIDENCE/"digo_blues_preview.wav",chorus,RATE,subtype="PCM_16")
subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(),"-hide_banner","-loglevel","error","-y","-i",str(EVIDENCE/"digo_blues_preview.wav"),"-c:a","libvorbis","-q:a","5",str(OUT/"digo_blues_loop.ogg")],check=True)
report = {"original":True,"external_samples":False,"bpm":BPM,"bars":12,"meter":"4/4","sample_rate":RATE,"samples":LENGTH,"seconds":LENGTH/RATE,"rendered_choruses":3,"export":"central chorus with circular room tails","rms":float(np.sqrt(np.mean(chorus**2))),"peak":float(np.max(np.abs(chorus))),"seam_step":(chorus[0]-chorus[-1]).tolist(),"asset":"audio/workshop/digo_blues_loop.ogg"}
(EVIDENCE/"composition.json").write_text(json.dumps(report,indent=2),encoding="utf-8")
print(json.dumps(report))
