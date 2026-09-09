# Opening integrated into Harbor

The ten approved PNGs, scene, timeline and procedural audio were imported from
`D:/geteco/cutscene_godot_preview/cutscenes/opening`. The original preview project
was not changed. Images and narrative timeline are unchanged: 41.5 seconds of
shots, followed by the original 0.8-second final fade.

`HarborArrivalMission` owns an overlay on CanvasLayer 100. New games play it;
existing `harbor_arrival_seen` saves continue directly to the arrival phone call.
The world pauses while the presentation runs, so the player cannot be struck by
traffic underneath it. Previous pause state is restored on completion, skip and
scene teardown. Player dialogue lock remains owned until the phone call ends.

Both `finished(bus_terminal_arrival)` and `skipped(bus_terminal_arrival)` enter the
same guarded continuation after the fade. Completion persists
`harbor_arrival_seen`; only an actually presented prologue advances
`prologue_call`, and no later legacy beat is fabricated. Production controls are
Esc/Enter/Space to skip; arrows and R do not expose the preview's seek/restart.
The diagnostic HUD and end card are hidden.

Music uses the Music bus, ambience/foley use SFX. Audio is the original procedural
soundtrack; dialogue uses subtitles. There are no recorded character voices.

Validation: `tests/test_opening_cutscene_runtime.gd` passes with natural unsped
playback of all ten images while the tree is paused, real finish/skip fades,
single completion emissions, audio cues/stopping and production HUD checks.
The Harbor campaign tests separately exercise the continuation and save flow.
