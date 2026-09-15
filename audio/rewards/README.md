# Reward audio

Nine sound identities, thirteen stereo PCM WAV files at 48 kHz, all synthesized.
Completion is an original four-second D-Dorian phrase at 96 BPM. The GTA file
was only a stylistic reference; no recorded samples are inputs to the builder.

| Event | Character | Duration |
| --- | --- | --- |
| Pickup / healing / armor | Soft tactile onset and rising two-note response; three takes | 0.48 s |
| Cash | Muted metallic contact and bright response; three takes | 0.52 s |
| Weapon | Low mechanical contact and tuned confirmation | 0.55 s |
| Collectible | Original D-Dorian electric piano response, plucked guitar and bass | 1.15 s |
| Checkpoint | Immediate pulse, brief air movement, rising fifth | 0.68 s |
| Countdown | Brief muted pulse; the start uses the checkpoint accent | 0.22 s |
| Mission start | Short anticipation phrase | 0.90 s |
| Completion | Original electric piano phrase, plucked guitar chords, finger bass and dry drums | 4.00 s |
| Achievement | Original four-note phrase, fuller guitar/piano resolution and dry drums | 2.40 s |

Completion, discovery and achievement share D-Dorian instruments and harmony.
Other cues retain their B-major palette. WAV peaks are approximately -6 dBFS
(-5 dBTP for discovery, -3.5 dBTP for completion/achievement); gameplay
uses another -2 to -3 dB attenuation. Import normalization, trimming, looping and
compression are disabled. `metrics.json` records oversampled peaks and RMS.

The original completion cue is rebuilt by `python tools/build_mission_passed_audio.py`.
Its shorter siblings are built by `python tools/build_exploration_audio.py`.
The approved completion WAV remains unchanged. Player progression owns discovery
playback, so both ground pickups and mountain evidence play once per unique find.
Achievements queue in the HUD and wait for the discovery phrase to finish.
Run it after the general reward builder when regenerating the full bank. It only
replaces `complete.wav`; measurements and a listening copy are saved under
`artifacts/sa-hud-0913/v5-original`. The composition and instruments live in
`tools/mission_victory_arrangement.py`. The copied reference and its processing
script were removed; rebuilding has no dependency on the supplied MP3.

`RewardAudioBank.play()` keeps at most four scene-owned voices, coalesces repeats
within 65 ms, and cycles pickup/cash takes without detuning. Scene ownership keeps
pickup tails alive after the item disappears. It routes through the user's SFX
bus. Mission dialogue feedback retains its existing always-processing players.
Achievement playback remains attached to the HUD and now has its own cue.

Existing `ProceduralAudio` reward getters return cached bank streams, keeping
purchase, healing and mission consumers compatible. Checkpoints in the night
races and Cobra campaign now use the dedicated checkpoint cue. Weapon pickups
use equipment feedback instead of an accelerated gunshot.

Rebuild from workspace root: `python tools/build_reward_audio.py` (NumPy/SciPy).
Audition: `artifacts/reward-audio-0910/reward-showcase.wav`; accompanying cue sheet
lists timestamps. Preview order: pickup, cash, weapon, collectible, checkpoint,
mission start, completion, achievement, countdown.

Validation: `tests/test_reward_audio.gd` covers resources, variation, burst limits,
pickup-tail lifetime, SFX routing, the real achievement HUD, and scene cleanup.
The builder verifies finite samples, true peaks, DC offset and silent endpoints.
