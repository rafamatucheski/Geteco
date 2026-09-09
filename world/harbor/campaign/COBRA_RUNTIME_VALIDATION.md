# Cobra campaign runtime — 2026-09-06

## Implemented

- Five finite missions after the existing arrival/delivery: workshop conversation,
  one-lap race, resident protection, records recovery, local leadership confrontation.
- Explicit interaction and proximity gates; a real driven vehicle is required for
  the race and disembarking is required for conversations/evidence.
- Race rival is the production TrafficVehicle using the canonical four quarter
  lanes and junction connection metadata. Countdown stops its processing; victory
  requires ordered gates, remaining on the circuit and beating the physical rival.
- Encounters use CobraEncounter's finite, damaging actors. Completion requires
  opponent deaths followed by a separate world interaction, never just entering
  the destination radius. Resident death fails protection; explicit retry rebuilds
  its finite cast. Player death/retreat also resets attempts.
- Persistent ledger supplies next-day gates and once-only reward tokens. Runtime
  pays those tokens once; no rewards belong to encounter actors or the UI.
- A dedicated resident at (7210,1850), not an ambient guard, provides an optional
  conversation that removes one finale reinforcement. Paper records are visible
  at the supply objective. Temporary Cobra access persists between early jobs.
- Ferrugem is the existing live workshop guard, not disembodied dialogue. Death
  fails the contact mission; explicit retry replaces only guard slot 2 and keeps
  the three-guard roster bounded. Assault revokes access in the persistent ledger.
- PT/EN authored strings and an ambiguous final clue, without the map 2 reveal.

## Automated evidence

`test_cobra_campaign_runtime.gd`: zero failures with the authored road network and
Harbor junction controller. Covers proximity, two-step contact, next-day gate,
production rival creation/countdown immobility, false-start failure/retry, ordered
physical lap and rival movement, zero invalid lane contracts, real encounter actor
death gates, supply death/retry, neighbor flag once, reduced finale roster, and
1520 total cash paid exactly once across the five missions.
The final run also validates live-contact identity, death/retry with three guards
still in the roster, and persistent access revocation after aggression.

The driving subject in that test is a CharacterBody2D fixture moved by physics.
The separate `test_cobra_race_player_car.gd` uses the full production HarborPreview
and its unchanged PlayerCar: after initial staging/boarding, only throttle and
steering Input actions drive the entire race. It passed with 1872.3px travel,
5.12px maximum physics-frame step and 61.3px maximum radial deviation, beating
the canonical rival. No transform/velocity writes during the lap.

Damage tests invoke real actor damage APIs, not human aiming. Manual UI playthrough,
perceived difficulty and 50–70 minute pacing remain separate validation needs.

## Deliberate limits

- The supply operation is a stationary guarded records recovery, not a convoy.
- Finale has the encounter's leader repositioning phase, not a vehicle escape.
- There are no two extra optional race variants in this controller yet.
- The resident favor is a short conversation/advantage, not a full rescue side quest.
- Integration/UI, persistence ownership for the secret car, and end-to-end district
  playtesting are owned by the root task and are not claimed by this module.
- Godot reports environment log/certificate access errors. The final runtime run
  has zero assertion/script errors and no ObjectDB exit warning; an earlier
  isolated fixture and the production driving test reported exit warnings.

No commits made.
