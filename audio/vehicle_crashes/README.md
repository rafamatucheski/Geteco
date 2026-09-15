# Vehicle crash recordings

Replaces the rejected synthesized kick/tom-like impacts. All 20 WAVs are edits of
recorded crash Foley: metallic collisions, deformation, grit and glass. No sine
oscillators, generated low thumps or synthesized noise layers are used.

- Bumper: short, band-limited compression/crunch; no added glass tail.
- Metal: different passages of a recorded metallic crash, with a compact initial contact.
- Solid: compact impact with deformation and shorter settling debris.
- Heavy: recorded metal panels and glass, with a longer irregular debris tail.
- Motorcycle: four edits using only the metallic recording, without either glass-containing source. Used at every severity when either contact body is a motorcycle, including police motorcycles.

Sources are CC0, documented individually with page URLs, authors, download URLs and
SHA-256 hashes in SOURCES.json. The publicly available high-quality MP3 previews
were used; these are Foley/film effects, not claimed to be recordings of actual accidents.

Run `python tools/build_vehicle_crash_audio.py --download` from the game directory
to reproduce the bank (numpy, scipy, soundfile). Downloads are cached in the parent
workspace's assets/audio-sources/vehicle-crashes folder. The build also writes
metrics.json and audio/vehicle_crash_review.wav: two examples of each family in
the order bumper, metal, solid, heavy, motorcycle, with 550 ms of silence between clips.

Runtime uses imported, preloaded PCM resources, including in exported games.
It does not synthesize or load files during collisions. The existing severity and
material selection, spatial position and duplicate-contact suppression remain.
Tests only read the assets; rebuilding the recordings is an explicit tool action.
