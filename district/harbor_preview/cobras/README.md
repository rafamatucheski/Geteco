# Ashbend Court — Cobras residential enclave

Integrated into `HarborPreview.tscn`, therefore also the production
`HarborGame.tscn`. No debug teleport or separate prototype is needed to visit.

## Getting there

Cross Foundry Bridge to Northbank, follow Eastgate Drive south, and turn east
at world `(6450,1700)`. The access passes through the former eastern boundary
and reaches the two-way circular residential street at `(7400,1700)`.
The workshop is on the eastern side; pedestrian alleys run behind the houses.
The dark copper coupe is behind the southwest bungalow at `(7050,2290)`.

## Scope delivered

- Five connected authored road sections; shared Unified asphalt, lanes and
  connector paths. No open-end flags masking disconnected roads.
- Eight low-rise buildings with four roof/facade forms, workshop forecourt,
  footpaths, back entrances, segmented fences, washing lines, dry scrub,
  rocks, trees with solid trunks and six weather-connected street lamps.
- Four circle seams explicitly unsignalized; two intentional pedestrian
  crossings use the existing pedestrian priority system. Eastgate retains
  its real controlled junction.
- Three Cobra profiles using the existing articulated character rig and two
  non-hostile residents. Finite population, no automatic endless replacement.
- Perception with wall occlusion, warning before escalation, reputation,
  withdrawal and real existing combat/death mechanics. Cinematic/dialogue
  locks and pause suspend the encounter. Local notices support PT-BR/English.
- Existing playable pickup and articulated 3D coupe, with different handling.
  Coupe top speed 520 versus the stock Harbor coupe's 450 px/s; no free nitro.
  Existing boarding, exit, damage, repair and repaint APIs are reused.

## Deliberate limits / follow-up

This is one playable enclave, not the entire gang campaign or five-map build.
House facades and workshop shutters are scenery, not promised new interiors.
The character profiles are variations of the shared rig, not three new meshes.
The pickup reuses the existing vehicle atlas; the coupe is the existing 3D model.
New gang reputation/deaths and discovered-car ownership have no new save
integration in this change. Do not present discovery as a permanent unlock.

An eventual authored race can follow the access and full court, returning to
Eastgate. No race mission, rival AI, rewards or additional board contracts are
installed by this area. That needs separate progression/save validation.

## Tests

- `tests/test_cobra_neighborhood.gd`: production integration, graph access in
  both directions, physical road/footpath samples, lamps and real driving.
- `tests/test_cobra_territory.gd`: actual physics, warning/retreat, wall LOS,
  reputation, attack, suspension, vehicle occupancy and bullets.
- `tests/test_cobra_vehicles.gd`: discovery-car boarding, camera, physical
  movement, wheel animation, repaint and exit; both parking footprints.
- `tests/visual/capture_cobra_neighborhood.gd`: actual renderer day/night views.

Validation results and performance measurements are recorded in the parent
task's delivery, not inferred from compilation alone. No commits made.
