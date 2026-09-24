# Reload Foley sources

The WAVs here are edited assemblies of these CC0 1.0 recordings. They replace
the previous procedural noise/tone effects. Original downloads, source URLs and
SHA-256 hashes are in `assets/audio-sources/reloads/sources.json`.

| Author | Source | Used for |
| --- | --- | --- |
| zer0_sol | [Handgun reload](https://opengameart.org/content/handgun-reload-sound-effect) | Magazine handling, seating and slide |
| zer0_sol | [Shotgun reloads](https://opengameart.org/content/shotgun-reload-sound-effects) | Shell insertion and pump |
| SpringySpringo | [Gun reload sounds](https://opengameart.org/content/gun-reload-sounds) | Airsoft magazine and rifle mechanisms |
| LFA | [Equipment clicks III](https://opengameart.org/content/equipment-clicks-iii) | Mechanical latches, slides and prop Foley |
| Brian MacIntosh / BMacZero | [Gun reload sound effects](https://opengameart.org/content/gun-reload-sound-effects) | Cartridge and magazine clicks |

License: https://creativecommons.org/publicdomain/zero/1.0/

Edits: mono conversion, resampling to 32 kHz PCM16, isolated gestures, edge fades,
rumble reduction, gentle material EQ, gain balancing and sequencing. Three takes
vary pauses, levels and selected cartridge recordings. No synthetic white noise,
oscillator rings or reverb are added. Revolver, break-action and special-weapon
sequences are composed Foley, not recordings of those exact guns. Source clipping
cannot be undone by output attenuation; output has ample headroom.

Rebuild: `python tools/fetch_reload_recordings.py`, then
`python tools/build_reload_audio.py` (NumPy, SciPy and imageio-ffmpeg).
