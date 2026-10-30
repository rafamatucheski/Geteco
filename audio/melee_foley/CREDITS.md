# Melee Foley

60 offline edits of existing CC0 recordings, with four different source takes
per event. Sources and retained license files are documented in
[the contact bank credits](../contact_foley/CREDITS.md): Kenney Impact Sounds
and Independent.nu / qubodup's crunch recordings. No new external assets.

Knife, bat, katana and axe have separate air/cloth, ordinary contact and heavy
contact families. Katana and axe also have complete severing contacts; these
replace, rather than stack over, the normal contact. Landing is its own event.
Air/cloth uses a shaped portion of a soft-contact recording with its initial
impact removed. No noise generator or oscillator is used.

Build: `python tools/audio/build_melee_foley.py` (numpy, scipy, soundfile).
Mono 44.1 kHz PCM16, 5–7 dB peak headroom. `bank.json` records hashes, durations
and peaks. Runtime selection avoids immediately repeating the same take.

These are edited game Foley, not recordings of actual injuries. Auditory
approval of timbre, synchronization and the in-game mix remains pending.
