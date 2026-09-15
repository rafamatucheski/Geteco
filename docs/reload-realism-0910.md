# Revised reload Foley — 2026-09-10

The first reload set sounded too similar because every mechanism was generated
from filtered noise and resonant tones. Replaced all 33 samples (11 weapons,
three takes each) with edited CC0 recordings of handling and mechanical actions.
Source credits: `audio/reload/CREDITS.md`; originals and hashes are outside the
game under `assets/audio-sources/reloads/`.

- Pistol: magazine release, seating, then slide; about 1.7 seconds.
- Magnum: latch/open, several cartridge sounds, then heavier closure.
- SMG: brisk magazine handling; AK: magazine latch plus separate charging action.
- M4: magazine seat, tap and short release, with different recordings from AK.
- Shotgun: two separated shell gestures and an actual recorded pump action.
- Sawed-off and hunting rifle: composed hinged/bolt sequences and cartridges.
- RPG, flamethrower and grenade: separate recorded prop Foley compositions.

These are sound designs, not exact-model recordings for every weapon. Shotgun
loading is a fixed sound sequence, not a simulation of each shell transferred.
The follow-up synchronization now selects an actual WAV before playback and uses
its playback position to drive the hand/weapon pose. The audio finished signal
commits ammunition and unlocks firing; both manual and automatic reloads wait.
Switching weapons, hiding/boarding, death, arrest, dialogue and restoring a save
cancel without transferring ammunition. Repeated R does not restart a reload.
Pausing freezes sound and animation; muting SFX still allows completion.

Build: `python tools/build_reload_audio.py` (NumPy, SciPy, imageio-ffmpeg).
All outputs are mono 32 kHz PCM16, peak 0.54, durations 0.94–2.83 seconds.
Three takes vary handling pauses and levels, with alternate cartridge samples.

Validation: Godot import, `test_reload_audio.gd`,
`test_manual_weapon_reload.gd`, and `test_combat_audio.gd -- combat-only` passed.
`test_reload_audio.gd -- record` captures the real SFX bus to
`artifacts/reload-sync-0910/reload-preview.wav` in bank weapon order:
pistol, magnum, SMG, shotgun, sawed-off, AK47, M4A1, hunting rifle, RPG,
flamethrower, grenade. `tools/check_reload_audio.py` checks sample format,
headroom, silent edges and the optional mixer capture. Technical checks do not
substitute for the user's listening judgment.

Synchronization checks: `test_reload_sync.gd` tests the actual recording end,
loaded-round firing block, single ammunition transfer, cancellation, pause and
muted completion. Run headless with `--max-fps 60` so an uncapped renderless
process does not starve the dummy audio thread. `-- capture` also saves real GPU
renders of four reload poses under `artifacts/reload-sync-0910/`.
The existing 13-weapon combat pose regression suite still passes. Reload motion
uses the existing arm IK, animated shotgun pump and swing-out revolver cylinder;
it does not simulate individual inserted rounds or a detachable magazine mesh.
