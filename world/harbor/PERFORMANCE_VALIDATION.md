# Harbor: performance pass — 2026-09-05

## Scope and finding

Two agents assisted with render/camera changes and regression checks. No commits.
Existing worktree changes from other tasks were preserved. Old game/test processes
were stopped with user permission; the existing Godot editor was left open.

The primary measured CPU bottleneck was not the blue collision rectangles:
`JunctionTrafficController._lane_junction_projections()` included the entire
98,114-character graph signature in every cache lookup key. Multiple queries per
vehicle per frame repeatedly formatted and hashed that string, including cache hits.
The key now contains only path instance ID, road index and curve length.
`_sync_from_graph()` already clears the cache on signature changes; changing graph
source also forces that synchronization. Navigation and reservation rules are unchanged.

The callback diagnostic found expensive civilian vehicle updates around 2–3 ms
before this fix and around 0.2–0.3 ms afterward. This diagnostic manually invokes
callbacks and is CPU attribution evidence, not a gameplay/FPS benchmark.

## Other changes

- `AnimatedPedestrian3D.gd`: use camera canvas transform and actual screen rectangle
  with a 220 px margin for render visibility. Visible NPC SubViewports render at
  30 Hz, or 15 Hz when their projected size is tiny; hidden/offscreen rendering is
  disabled. Navigation, collision, combat and pose updates are not frame-skipped.
- `Player.gd`: disable hidden player's 3D viewport and restore it on visibility
  changes, including changes when physics processing is disabled.
- `DynamicCamera.gd`: finite positive zoom validation and exponential interpolation
  prevent long frames from extrapolating through zero/invalid zoom.
- `HarborWaterfront.gd`, `HarborRoadNetwork.gd`, `UnifiedRoadNetwork2D.gd`: batch
  existing water/edge/dashed-line drawing without changing geometry or collisions.
  Batching alone did not demonstrate the large FPS gain; the traffic cache fix did.
- `tests/measure_harbor_sustained_driving.gd`: actually accelerates the car and
  reports distance. The previous script entered the car but never accelerated.
- `HarborPreview.gd`: only creates PaintAndSpray when interiors are enabled.
  The exterior-door fixture intentionally disables interiors; unconditional setup
  previously called `add_child` on its nonexistent garage despite test exit code 0.

This is render LOD and targeted CPU optimization, **not full world streaming**.
Buildings, mission state and the road graph are not unloaded by distance.
No water boundary collision shapes were removed.

## Graphical measurements

Godot 4.7.2, Compatibility/OpenGL, RTX 4060 Laptop, 1920×1080,
VSync disabled, one game/test running at a time. Editor remained open.
These are bounded samples, not a promise of constant 60 FPS everywhere.

| Scenario | Before cache fix | After cache fix |
| --- | --- | --- |
| Street-level fixed camera | 43.24 ms/frame (~23 FPS) | 13.01 ms/frame (~77 FPS) |
| Whole-district overview | 75.52 ms/frame (~13 FPS) | 36.78 ms/frame (~27 FPS) |
| Actual accelerating drive, 600 frames | No valid moving baseline | 14.69 ms/frame (~68 FPS) |

Drive: (700,425) to (3393,425), 2,710 px traveled, 2,693 px net displacement.
Median 12.66 ms, P90 16.53 ms, P99 45.62 ms; 54/600 frames exceeded 16.67 ms.
Worst frame 236.98 ms: intermittent hitching remains unresolved.

Overview still submits ~8,280 draw calls and measured root rendering about 20 ms
CPU/GPU each. It remains a rendering bottleneck; distance culling has limited
benefit when everything is visible. A future overview-specific representation or
carefully layered spatial drawing requires separate implementation/validation.

## Reproduce

Run scripts with `godot --path <game> --rendering-method gl_compatibility --script
res://tests/measure_harbor_sustained_driving.gd` for the real moving sample.
`profile_harbor_costs.gd -- quick` measures street view then diagnostic disabled
states; `-- overview` measures overview and captures a PNG in the OS temp folder.
Never compare numbers while other game/test instances run concurrently.

## Regression caveat

`test_harbor_life.gd` again hit the Courtyard Lane queue described in the prior
Claude report: the probe entered `RoadLayout/courtyard_lane/forward_01` but failed
to leave, at (5402.394,1772), after 913.6 px. Both Exchange Lane directions completed
their entry/exit trips with no obstacle overlap. The run reached the 180-second
external timeout after emitting the Courtyard assertion; this is **not a pass**
and not merely an inconclusive timeout. Navigation/fixtures were not weakened.
The prior report supports that this issue was already observed, but is not a
controlled before/after proof for this particular run.

## Sequential headless regression run

Final result: **17 of 18 selected scripts passed their assertions and exited 0**.
Entrances and coupe were rerun after the disabled-interiors initialization fix:
neither final run contained SCRIPT ERROR or RID/resource leak messages. The
Courtyard Lane assertion/timeout remains unresolved; this is not an all-green suite.

| Test | Result |
| --- | --- |
| test_lane_projection_cache.gd | PASS; reuse, bounded keys, changed graph and source invalidation |
| test_dynamic_camera_finite.gd | PASS |
| test_player_render_visibility.gd | PASS |
| test_pedestrian_render_lod.gd | PASS; 60 near / 30 tiny render requests over 2 seconds |
| junction_traffic_contract_test.gd | PASS |
| district_one_traffic_integration_test.gd | PASS; 24 vehicles, connector handoff, max step 7.727 px |
| rail_level_crossing_runtime_test.gd | PASS; natural train passage, zero vehicle conflicts |
| test_harbor_life.gd | FAIL assertion + external timeout, detailed above |
| test_harbor_road_edges.gd | PASS; 644 segments, 42 contours, 137 access masks |
| test_harbor_road_contract.gd | PASS; 20 roads, 40 lanes, 38 junctions |
| test_harbor_safety.gd | PASS; 91 crossings, 37 handoffs |
| test_harbor_district.gd | PASS; 50 buildings, 46 accesses, 2391 road samples |
| test_harbor_gateway.gd | PASS; both highway lanes reached turnaround and returned south |
| test_harbor_bridge.gd | PASS; 1386 px each direction, no collisions |
| test_harbor_ship_access.gd | PASS; 641 capsule samples, 38 sweeps, 1089 water samples |
| test_harbor_entrances.gd | PASS; 7 doors |
| test_living_cast_contract.gd | PASS; 6 variants, melee, shooting, damage |
| test_harbor_coupe.gd | PASS; paint job and live viewport updates |

Engine output also contains environment warnings/errors for inaccessible user log
files, certificate store and graphics shader cache; some fixtures report ObjectDB
leaks. Functional PASS above means script assertions and exit status passed, not
that all engine output was clean. This selected regression battery is not the
entire repository suite or a fresh interiors-gameplay acceptance run.
