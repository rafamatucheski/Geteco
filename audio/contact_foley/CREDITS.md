# Contact Foley bank

The 41 clips in `bank.json` are offline edits of these CC0 sources:

- **Kenney — Impact Sounds 1.0**: <https://kenney.nl/assets/impact-sounds>.
  Original license retained in `source/Kenney-License.txt`. The selected impact,
  panel, cloth-like soft impact and footstep takes are retained unmodified.
- **Independent.nu, submitted by qubodup — 5 break, crunch impacts**:
  <https://opengameart.org/content/5-break-crunch-impacts>.
  CC0: <https://creativecommons.org/publicdomain/zero/1.0/>.
  Original `impactcrunch01` through `impactcrunch05` retained in `source/impcrunch`.
- **chewiesmissus — Glass Breaking**:
  <https://freesound.org/people/chewiesmissus/sounds/244238/>.
  CC0; downloaded from the Godot demo mirror:
  <https://github.com/godotengine/godot-demo-projects/blob/master/audio/audio_effects/sfx/glass_breaking.wav>.
  License confirmation: <https://github.com/godotengine/godot-demo-projects/blob/master/audio/audio_effects/README.md#sound-effects>.

Edits: mono downmix, removal of lead-in, band-limited resampling for weight,
high-pass removal of subsonic energy, selective low-pass EQ, layered material
contacts, short edge fades and peak headroom of 3–4 dB. Different source takes
provide variation; glass variants also vary playback rate. No added synthetic
noise, oscillators, clipping distortion or runtime DSP.

Rebuild with `python audio/contact_foley/build_bank.py` (numpy, scipy, soundfile).
The source directory is excluded from Godot imports. The game uses the existing
WAV paths, prewarm, positional playback, SFX slider, limiter and 12-voice pool.
WAV imports use uncompressed 16-bit PCM to preserve impact transients.

Body contacts deliberately remain at most 0.54 seconds; vehicle and debris tails
range from 0.55 to 1.35 seconds. No extra audio players or frame callbacks.
