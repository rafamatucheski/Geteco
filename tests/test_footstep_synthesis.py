import math
import random

def generate_dry_footstep(variation=0):
    sample_rate = 22050
    duration = 0.07
    num_samples = int(sample_rate * duration)
    samples = []
    
    # Heel thud frequency variation (70 - 110 Hz)
    thud_freq = 75.0 + variation * 8.0
    decay_thud = 70.0 + variation * 5.0
    decay_texture = 90.0
    
    for i in range(num_samples):
        t = i / sample_rate
        # Smooth attack (4 ms) to eliminate harsh clicks
        attack = min(1.0, t / 0.004)
        
        # Soft low thud (heel impact on ground)
        thud = math.sin(2.0 * math.pi * thud_freq * t) * math.exp(-t * decay_thud) * 0.22
        
        # Soft friction / sole scuff (damped noise)
        noise = random.uniform(-0.12, 0.12) * math.exp(-t * decay_texture)
        
        val = (thud + noise) * attack
        samples.append(max(-1.0, min(1.0, val)))
        
    rms = math.sqrt(sum(s*s for s in samples) / len(samples))
    peak = max(abs(s) for s in samples)
    return rms, peak

def generate_wet_footstep(variation=0):
    sample_rate = 22050
    duration = 0.09
    num_samples = int(sample_rate * duration)
    samples = []
    
    thud_freq = 85.0 + variation * 6.0
    decay_thud = 65.0
    splash_freq = 1200.0 + variation * 180.0
    decay_splash = 110.0
    
    for i in range(num_samples):
        t = i / sample_rate
        # Smooth attack (3 ms)
        attack = min(1.0, t / 0.003)
        
        # Soft ground thud
        thud = math.sin(2.0 * math.pi * thud_freq * t) * math.exp(-t * decay_thud) * 0.18
        
        # Wet squelch / splash transient (liquid droplet dispersal)
        splash_sine = math.sin(2.0 * math.pi * splash_freq * t) * math.exp(-t * decay_splash) * 0.10
        wet_noise = random.uniform(-0.15, 0.15) * math.exp(-t * 85.0)
        
        # Subtle suction release (slight delay at 20-35ms)
        suction = 0.0
        if 0.015 < t < 0.05:
            ts = t - 0.015
            suction = math.sin(2.0 * math.pi * 400.0 * ts) * math.exp(-ts * 120.0) * 0.08
            
        val = (thud + splash_sine + wet_noise + suction) * attack
        samples.append(max(-1.0, min(1.0, val)))
        
    rms = math.sqrt(sum(s*s for s in samples) / len(samples))
    peak = max(abs(s) for s in samples)
    return rms, peak

for v in range(4):
    rms_dry, peak_dry = generate_dry_footstep(v)
    rms_wet, peak_wet = generate_wet_footstep(v)
    print(f"Variation {v}: Dry RMS={rms_dry:.4f}, Peak={peak_dry:.4f} | Wet RMS={rms_wet:.4f}, Peak={peak_wet:.4f}")
