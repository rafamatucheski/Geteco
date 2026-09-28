# Tank audio

Original procedural samples authored for Geteco; no third-party recordings.
Regenerate with `python audio/tank/generate_tank_audio.py` (NumPy is a build-only dependency).
Runtime loads cached WAV resources; it does not synthesize samples per frame.

All eleven samples are mono PCM16, 24 kHz, approximately 1.2 MB total. Seven
diesel bands cover idle through loaded RPM. The steel track loop follows absolute
speed independently of engine RPM, including reverse. Startup, cannon muzzle
blast and shell impact are finite samples with separate envelopes and timbres.

`TankAudio.fire_stream()` and `impact_stream()` return cached non-looping WAVs
for the existing spatial gameplay audio pool. `engine_bank()`, `tracks_stream()`
and `start_stream()` serve the existing vehicle mixers. Foreground engine keeps
its two-band blend and reuses road/startup channels; NPC mixers retain two voices
per vehicle, six nearby vehicles maximum, and their existing 45 m range.

The first parked player entry starts the diesel; takeover of an already audible
NPC tank uses its running engine. Tank-to-normal-car transitions restore the
normal acoustic family and road loop. Existing scene pause, ownership, distance,
engine destruction and shutdown rules govern all emitters.
