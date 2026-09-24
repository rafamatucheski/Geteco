"""Deterministic, original sound design. Run offline; numpy/scipy are build-only.

Engine: combustion pulses -> exhaust reflections -> body resonances + intake.
Weapons: pressure transient -> gas turbulence -> mechanism -> early reflections.
This is perceptual synthesis informed by acoustics, not measured recordings.
Reload assets are deliberately outside this builder's output directory.
"""
from pathlib import Path
import hashlib
import json
import wave
import numpy as np
from scipy.signal import butter, sosfilt, iirpeak, lfilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "audio/acoustic"
RATE = 22050
METRICS = {}


def noise(rng, n, low, high):
    x = sosfilt(butter(2, [low, high], fs=RATE, btype="band", output="sos"), rng.normal(size=n))
    return x / max(np.std(x), 1e-9)


def write(name, x, loop=False):
    x = np.asarray(x)
    assert np.isfinite(x).all() and np.max(np.abs(x)) < 0.96
    data = np.round(x * 32767).astype("<i2")
    with wave.open(str(OUT / (name + ".wav")), "wb") as f:
        f.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        f.writeframes(data.tobytes())
    METRICS[name] = dict(peak=float(np.max(np.abs(x))), rms=float(np.sqrt(np.mean(x*x))),
                         seconds=len(x)/RATE, sha256=hashlib.sha256(data.tobytes()).hexdigest())
    # Explicit import options keep PCM, loop boundaries and resampler guards.
    # Importer enum: 0=detect, 1=disabled, 2=forward (differs from stream enum).
    params = 'loop_mode=2\nloop_begin=0\nloop_end=22050\n' if loop else 'loop_mode=1\n'
    (OUT / (name + '.wav.import')).write_text(
        '[remap]\nimporter="wav"\ntype="AudioStreamWAV"\n\n[deps]\nsource_file="res://audio/acoustic/'
        + name + '.wav"\n\n[params]\nforce/8_bit=false\nforce/mono=true\nforce/max_rate=false\n'
        'edit/trim=false\nedit/normalize=false\nedit/' + params.replace('\nloop_', '\nedit/loop_')
        + 'compress/mode=0\n', encoding='utf-8')


def engine(family, p, cycles, index):
    rng = np.random.default_rng(12000 + sum(family.encode())*31 + index)
    n = RATE
    t = np.arange(n)/RATE
    cyl = int(p['cyl'])
    pulses = np.zeros(n)
    phase = p.get('pattern_offset', [0]*cyl)
    amps = p.get('pattern_amp', [1]*cyl)
    # Cycle-specific timing/amplitude variation prevents an oscillator-like buzz.
    for event in range(cycles*cyl):
        slot = event % cyl
        at = (event + phase[slot] + rng.normal(0, .007))/ (cycles*cyl)
        age = np.arange(int(RATE*.032))/RATE
        tau = .0028 if cyl >= 6 else .0022
        pulse = (1-np.exp(-age/.00022))*np.exp(-age/tau)
        pulse -= .28*(1-np.exp(-age/.001))*np.exp(-age/(tau*2.3))
        ids = (round(at*RATE)+np.arange(len(age))) % n
        np.add.at(pulses, ids, pulse*amps[slot]*rng.uniform(.92,1.08))
    # Delay-line reflections stand for propagation in manifold and exhaust.
    exhaust = pulses.copy()
    delay = .0065 if family in ('muscle','truck','bus','fire_diesel') else .0038
    for bounce in range(1, 9):
        exhaust += np.roll(pulses, round(delay*bounce*RATE)) * (-.58)**bounce
    voiced = exhaust*.48
    repeated = np.tile(exhaust, 4)
    for freq, q, gain in p['res']:
        b,a = iirpeak(freq, max(0.7,q*.45), fs=RATE)
        voiced += lfilter(b,a,repeated)[-n:] * gain * 1.8
    level = cycles/max(p['redline'],1)
    intake = noise(rng,n*3,160,min(8000,p['intake'][1]*2))[-n:]
    # Circular band-limited turbulence: no boundary discontinuity.
    spectrum = np.fft.rfft(intake)
    intake = np.fft.irfft(spectrum, n)
    mod = .5+.5*np.sin(2*np.pi*cycles*cyl*t)
    voiced += intake*(.022+.07*level)*mod
    voiced += p['sub']*.2*np.sin(2*np.pi*cycles*2*t)
    if p['knock'][0]:
        voiced += .14*p['knock'][0]*noise(rng,n,1500,4500)*mod**6
    if p['whine'][1]:
        order = round(p['whine'][0]*cycles)
        voiced += p['whine'][1]*level*.18*np.sin(2*np.pi*order*t)
    # Circular frequency-domain high/low pass, with no filter startup transient.
    f = np.fft.rfftfreq(n,1/RATE)
    response = (f/np.maximum(f,32))**2 / np.sqrt(1+(f/7800)**8)
    voiced = np.fft.irfft(np.fft.rfft(voiced)*response,n)
    voiced = np.tanh(voiced/max(np.max(np.abs(voiced)),1e-8)*(1.1+.55*level))
    voiced -= np.mean(voiced)
    voiced *= min(.78/max(np.max(np.abs(voiced)),1e-8), .26/max(np.std(voiced),1e-8))
    # Remove only the random seam discontinuity over 64 samples; preserve pulses.
    edge = voiced[-1]-voiced[0]
    voiced[-64:] -= edge*np.linspace(0,1,64)**2
    return np.concatenate([voiced,voiced[:8]])


SHOTS = {
    'pistol': (.48, .0020, 42, 6800, .72),
    'magnum': (.78, .0037, 24, 5400, .82),
    'smg': (.30, .0016, 60, 7300, .66),
    'ak47': (.52, .0025, 37, 8200, .77),
    'm4a1': (.42, .0015, 48, 9200, .73),
    'hunting_rifle': (.90, .0032, 27, 8400, .82),
    'shotgun': (.75, .0045, 22, 4800, .82),
    'sawed_off': (.65, .0050, 26, 6100, .84),
}


def shot(kind,take,suppressed=False):
    duration,tau,decay,bright,peak = SHOTS[kind]
    rng=np.random.default_rng(87100+list(SHOTS).index(kind)*97+take)
    n=int(duration*RATE)
    t=np.arange(n)/RATE
    tau*=rng.uniform(.94,1.06)
    # Bipolar blast pressure, with fast attack and longer negative phase.
    pressure=(1-t/tau)*np.exp(-t/tau)*(1-np.exp(-t/.00008))
    gas=noise(rng,n,110,bright)*(1-np.exp(-t/.00035))*np.exp(-t*decay)
    body=noise(rng,n,60,650)*(1-np.exp(-t/.001))*np.exp(-t*decay*.8)
    x=pressure*1.4+gas*.55+body*.38
    if suppressed:
        x=sosfilt(butter(2,1900,fs=RATE,output='sos'),x)*.22
        peak=.28
    # Short action sounds; no magazine/pump/reload sequence baked into shots.
    if kind not in ('magnum','shotgun','sawed_off','hunting_rifle'):
        for onset,gain in ((.028,.09),(.059,.055)):
            age=np.maximum(0,t-onset)
            x+=noise(rng,n,900,6000)*(t>=onset)*(1-np.exp(-age/.0003))*np.exp(-age*180)*gain
    dry=x.copy()
    reflected=sosfilt(butter(2,2400,fs=RATE,output='sos'),dry)
    for delay,level in ((.039,.13),(.083,.075),(.147,.038)):
        shift=int((delay+rng.uniform(-.004,.004))*RATE)
        x[shift:]+=reflected[:-shift]*level
    x=sosfilt(butter(2,38,fs=RATE,btype='high',output='sos'),x)
    x*=np.minimum(1,(duration-t)/.035)
    # Moderate crest control gives body without clipping or volume-only fixes.
    x=np.tanh(x*.8)
    x-=np.mean(x)
    # Leave headroom for WeaponCatalog gain (+2 dB) and take variation.
    x*=peak*.85/max(np.max(np.abs(x)),1e-8)
    x[0]=x[-1]=0
    return x


def impact(kind,take):
    rng=np.random.default_rng(32100+list(('metal','wood','glass','concrete','flesh')).index(kind)*43+take)
    n=int(RATE*.65); t=np.arange(n)/RATE
    x=noise(rng,n,100,7000)*np.exp(-t*240)*.35
    if kind=='metal':
        for f,g,d in ((510,.24,24),(1370,.16,18),(2890,.10,34),(4610,.05,44)):
            x+=np.sin(2*np.pi*f*rng.uniform(.94,1.06)*t)*np.exp(-t*d)*g
    elif kind=='wood':
        x+=noise(rng,n,110,1800)*np.exp(-t*65)*.45
        x+=np.sin(2*np.pi*210*t)*np.exp(-t*95)*.25
    elif kind=='glass':
        for start in rng.uniform(.015,.23,24):
            age=np.maximum(0,t-start)
            x+=np.sin(2*np.pi*rng.uniform(2100,8700)*age)*np.exp(-age*rng.uniform(70,150))*(t>=start)*.10
    elif kind=='concrete':
        x+=noise(rng,n,400,5200)*np.exp(-t*65)*.45
    else:
        x=noise(rng,n,60,900)*np.exp(-t*85)*.6 + noise(rng,n,900,3300)*np.exp(-t*170)*.15
    x*=np.minimum(1,t/.00015)*np.minimum(1,(n/RATE-t)/.025)
    x-=np.mean(x); x*=.55/max(np.max(np.abs(x)),1e-8); x[0]=x[-1]=0
    return x


def effect(kind, take):
    rng=np.random.default_rng(73000+take*17+sum(kind.encode()))
    duration=2.1 if kind=='explosion' else .65
    n=int(duration*RATE); t=np.arange(n)/RATE
    if kind=='explosion':
        x=noise(rng,n,40,380)*np.exp(-t*3.5)*.65
        x+=noise(rng,n,180,5400)*np.exp(-t*23)*.9
        for start in rng.uniform(.12,.7,16):
            age=np.maximum(0,t-start)
            x+=noise(rng,n,700,4200)*(t>=start)*np.exp(-age*70)*.08
    elif kind=='rpg_launch':
        x=noise(rng,n,90,1700)*np.exp(-t*34)*.7
        x+=noise(rng,n,500,6600)*(1-np.exp(-t*90))*np.exp(-t*7)*.36
    else:
        x=noise(rng,n,1400,8500)*np.exp(-t*210)*.25
        # Glancing-metal ring falls in frequency as the projectile recedes.
        x+=np.sin(2*np.pi*(2900*t-1100*t*t))*np.exp(-t*16)*.32
        x+=np.sin(2*np.pi*4700*t)*np.exp(-t*65)*.10
    x*=np.minimum(1,t/.0002)*np.minimum(1,(duration-t)/.04)
    x=np.tanh(x); x-=np.mean(x); x*=.68/max(np.max(np.abs(x)),1e-8)
    x[0]=x[-1]=0
    return x


def skid(index):
    rng=np.random.default_rng(96100+index)
    t=np.arange(RATE)/RATE
    base=[1450,1720,1210,980,1590][index]
    # Stick-slip friction: integrated frequency modulation, not sin(f(t)*t).
    phase=2*np.pi*base*t+1.8*np.sin(2*np.pi*(13+index)*t)
    x=.24*np.sin(phase)+.09*np.sin(phase*2)
    x+=noise(rng,RATE,480,7500)*.13*(.75+.25*np.sin(2*np.pi*23*t))
    x*=.65/max(np.max(np.abs(x)),1e-8)
    x[-64:]-=(x[-1]-x[0])*np.linspace(0,1,64)**2
    return np.concatenate((x,x[:8]))


def main():
    OUT.mkdir(exist_ok=True)
    profiles=json.loads((OUT/'engine_profiles.json').read_text())
    manifest=['extends RefCounted', '## Generated by tools/build_acoustic_bank.py. Immutable PCM resources.', 'const ENGINES := {']
    nominal={}
    for family,p in profiles.items():
        if family=='electric': continue
        ladder=sorted(set(round(x) for x in np.geomspace(max(3,p['idle']),p['redline'],7)))
        nominal[family]=ladder
        paths=[]
        for index,cycles in enumerate(ladder):
            name=f'engine_{family}_{index}'
            write(name,engine(family,p,cycles,index),True)
            paths.append(f'preload("res://audio/acoustic/{name}.wav")')
        manifest.append(f'\t"{family}": [{", ".join(paths)}],')
    manifest+=['}', 'const NOMINAL := '+json.dumps(nominal), 'const EVENTS := {']
    for kind in SHOTS:
        for suppressed in (False,True):
            if suppressed and kind in ('magnum','sawed_off'): continue
            key=('suppressed_' if suppressed else '')+kind
            paths=[]
            for take in range(5):
                name=f'{key}_{take}'; write(name,shot(kind,take,suppressed)); paths.append(f'preload("res://audio/acoustic/{name}.wav")')
            manifest.append(f'\t"{key}": [{", ".join(paths)}],')
    for kind in ('metal','wood','glass','concrete','flesh'):
        paths=[]
        for take in range(5):
            name=f'{kind}_{take}'; write(name,impact(kind,take)); paths.append(f'preload("res://audio/acoustic/{name}.wav")')
        manifest.append(f'\t"{kind}": [{", ".join(paths)}],')
    for kind in ('explosion','rpg_launch','ricochet'):
        paths=[]
        for take in range(5):
            name=f'{kind}_{take}'; write(name,effect(kind,take)); paths.append(f'preload("res://audio/acoustic/{name}.wav")')
        manifest.append(f'\t"{kind}": [{", ".join(paths)}],')
    manifest+=['}', 'const SKIDS := {']
    for index,kind in enumerate(('street','sport','muscle','heavy','monaliza')):
        name='skid_'+kind; write(name,skid(index),True)
        manifest.append(f'\t"{kind}": preload("res://audio/acoustic/{name}.wav"),')
    manifest+=['}']
    (OUT/'AcousticBank.gd').write_text('\n'.join(manifest)+'\n',encoding='utf-8')
    (OUT/'metrics.json').write_text(json.dumps(METRICS,indent=2))
    preview=[]
    for kind in SHOTS:
        preview.extend((shot(kind,0),np.zeros(RATE//2),shot(kind,1),np.zeros(RATE)))
    write('weapons_preview',np.concatenate(preview))
    print(f'Built {len(METRICS)} original samples; no reload assets touched.')


if __name__=='__main__': main()
