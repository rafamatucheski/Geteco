# Living Cast — opt-in lab

This folder is isolated from HarborPreview and does not replace its population,
traffic, player, or the files currently under performance/art revision.

Run `res://prototypes/living_cast/LivingCastLab.tscn` in Godot. WASD moves,
Shift runs, E boards, F exits, and left click uses the player's equipped weapon.
The player starts with fists. Ordinary residents flee; the red-shirted brawler
retaliates unarmed; the watchman retaliates armed. Cars can be driven into the
solid barrier to the right. Reload the lab with its button to restore fixtures.

## Scope

- Six deterministic articulated civilian variants, derived from the civil study.
  Separate hair, clothing, build and accessory choices. This is a first pack,
  not a complete population replacement.
- Existing AnimatedPedestrian3D movement, panic, bullet, death/loot and viewport
  culling contracts are inherited, not modified. Added timed self-defense
  punches with contact/range/line-of-sight checks, flinch and a tweened fall.
  Death is authored articulation, **not physics ragdoll**.
- Six opt-in top-down car bodies reuse PlayerCar and existing catalog handling:
  sedan, wagon, delivery van, pickup, coupe, taxi. Local polygon deformation is
  clamped to 7 pixels; root transform and collision dimensions stay rigid.
  Existing collision audio, debris, damage and combustion systems are reused.
- Static mesh pieces are merged by material within joints. Materials are shared.
  Gameplay uses 96x96 viewports and inherited culling. The review sheet alone
  renders larger portraits. No claim of city-scale 60 FPS has been made.

## Validation

`--headless --path D:/geteco/game --script res://tests/test_living_cast_contract.gd`

Checks six rigs/car configurations, melee windup/single contact, wall occlusion,
panic movement, staged death, actual projectile dispatch, repair, bounded dents,
and real Player input boarding/driving into a physical barrier.

`--rendering-method gl_compatibility --script res://tests/visual/capture_living_cast.gd`

Writes `D:/geteco/living_cast_lineup.png` and `living_cast_damage.png`.
These are explicitly staged visual reviews, not evidence of navigation testing.

## Integration still pending

Do not instantiate these throughout the city until the other agents' work is
stable and this pack passes performance review in their final configuration.
City sidewalk authoring, spawn/pooling policy, vehicle persistence and district
response rules are not wired here. No changes to missions/save/settings.

The base vehicle door animation still uses its existing visual implementation;
custom door skins/interior trim and more detailed vehicle models need another
art pass. Destruction is localized visual deformation, not soft-body physics.
New art does not justify automatic aggression by all civilians.

Environment warnings concerning user:// logs/saves/certificates and ObjectDB
cleanup appeared during runs and are not represented as clean engine output.
No commits were made.
