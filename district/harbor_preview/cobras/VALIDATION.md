# Ashbend delivery validation — 2026-09-05

Three coordinated agents handled layout, territorial gameplay and independent
QA. The parent integrated the production scene, boundaries, lamps, crossings
and playable cars. Existing external board/CGI/prototype work was preserved.

## Reproduced and fixed during validation

1. Two semicircles shared identical endpoints, rejected by Unified. Changed
   only the provider to four quarter-arcs; no relaxed validator or open flags.
2. Automatic pedestrian/signal generation produced zebra fans at circle seams.
   The four local junctions now use explicit unsignalized overrides, with two
   deliberately authored crossings. Existing vehicle/pedestrian priority stays.
3. Street lamps were initialized before the weather manager. Local integration
   now connects all six after weather exists; daytime/nighttime tests pass.
4. Initial parked-car shape query included the car itself. The test excludes
   only that body's RID; all actual wall/building collisions remain queried.

## New functional tests: final exit 0

- `test_cobra_neighborhood`: eight solid non-overlapping buildings, five road
  definitions, 3,714 physical asphalt samples, clear pedestrian paths, all new
  lanes reachable from/to the city, six night lights and production population.
  Production PlayerCar drove about 923 px through the former eastern boundary.
- `test_cobra_territory`: warning before combat, withdrawal, reputation, real
  player aggression versus non-player damage, wall occlusion, pause/dialogue/
  control lock and driven-car detection. Real bullets caused 60 damage in the
  final hostile fixture. Resident routes reverse without diagonal shortcuts.
- `test_cobra_vehicles`: both physical parking spaces; entering, camera transfer,
  78.3 px of actual driving, articulated wheels, body-material repaint and exit.
- `test_cobra_traffic`: seven legal handoffs, 4,067.2 px, 58.8 simulated seconds,
  max step 15.45 px (<16.1), zero invalid lane contracts. One initial fixture
  placement and chosen legal destinations; no repositioning during the trip.
  This route test is not a congestion stress test with ambient cars.

## Existing gameplay regressions: final exit 0

Five additional selected tests passed with the integrated area:

- `test_harbor_campaign_flow`: arrival, phone, Maciota, board, completion,
  one-time reward, hospital respawn and save restoration.
- `test_harbor_road_contract`: original standalone district provider unchanged
  (20 roads / 40 lanes / 38 junctions). The expanded scene is separately covered
  by `test_cobra_neighborhood`; this old-provider test alone does not prove it.
- `test_harbor_safety`: 96 crossings, actual pedestrian request/grant, real
  civilian stop/resume and 64 handoffs. Its first run selected a new unsignalized
  crossing for a SIGNAL synchronization assertion and failed. The fixture now
  explicitly selects a crossing with signal state; no assertion removed.
  The new neighborhood test separately places the actual player on BOTH new
  unsignalized crossings and confirms traffic must yield there. Both tests
  passed again after that fixture correction.
- `test_harbor_coupe`: existing physical wall deformation and actual paint-bay
  service still pass, including repair, lights and return of controls.
- `test_harbor_terminal`: 2 visits, 2 departures, 4 boardings, 4 alightings,
  3,185.4 px traveled. All assertions pass; 4 ObjectDB teardown warnings remain.

Total: **nine selected functional tests passed**, plus rendered captures and
before/after benchmarks. Not the complete repository suite.

## Actual rendered captures

Compatibility renderer, 1600x1000:

- `D:/geteco/cobra-neighborhood-day.png`
- `D:/geteco/cobra-neighborhood-night.png`

Both reviewed after fixes. Minor visible curb steps at quarter-arc seams remain;
physical road samples and driving do not find a blocking obstacle there.

## Performance comparison — not a 60 FPS guarantee

Existing `measure_harbor_performance.gd`, real Compatibility renderer on RTX4060
Laptop, 1920x1080, 150 wall-time samples per scenario. Full benchmark includes
diagnostic scenarios with disabled groups; **those diagnostic results are not
used as normal gameplay numbers below**. Normal scenarios keep systems active.

| Existing scenario | Before avg FPS | After avg FPS |
| --- | ---: | ---: |
| Overview | 22.6 | 23.3 |
| Busy block walking | 59.4 | 56.1 |
| Initial driving sample | 74.9 | 64.9 |
| Driving, restored daytime at end | 56.0 | 63.0 |
| Night + rain driving | 59.7 | 65.4 |
| Garage | 90.1 | 113.8 |

These are single runs with moving traffic, not controlled repeated statistical
proof of a performance gain/loss. Walking/initial-driving samples worsened;
later samples improved. Do not claim the expansion is free or always 60 FPS.
Overview remains an existing expensive case, and frame-time spikes remain.
The existing report's population counters list HarborLife's 28 cars/39 walkers,
not the additional three guards, two residents and two parked local cars.

Raw reports: `D:/geteco/cobra-perf-before/REPORT.txt` and
`D:/geteco/cobra-perf-after/REPORT.txt`. Save/log/shader-cache/certificate access
warnings occurred under the restricted runtime; some headless teardown tests
report two retained ObjectDB instances. No claim of a clean warning-free engine
or of a whole-repository suite run. No commits.
