# Pickup presentation — 2026-09-28

Recovered V1 `WeaponPickup.gd` presentation parameters: rotation at 1.6 rad/s,
bobbing at 3.2 rad/s, halo pulse at 2.5 rad/s and 0.25 s absorption. Field
inventory food, water and bags now share this presentation and use the already
imported V1 `reward_pickup_0..2.wav`. Inventory acceptance remains authoritative;
failed collection has no reward. Solid bag anchors do not rotate, and placement
checks include the full visual rotation envelope. Weapon/armor absorption now
also fades the center disc and model instead of abruptly deleting them.

## Rendered diagnostic

`tests/measure/measure_pickup_feedback.gd`, actual Main scene beside Union,
RTX 4060 Laptop, Godot 4.7.2, Mobile Vulkan, 1920x1080. Both reports include
actual VSync/max-FPS settings, raw frame intervals and 8 s warmup; each measured
window lasts 30 s. Provisional target: 60 FPS / 16.67 ms; >5% p95/p99 changes
require confirmation in equivalent conditions.

| Metric | Before | After |
| --- | ---: | ---: |
| Mean FPS | 122.54 | 79.70 |
| p50 ms | 4.756 | 13.779 |
| p95 ms | 13.130 | 18.551 |
| p99 ms | 28.326 | 20.492 |
| Maximum ms | 177.486 | 63.583 |
| Frames >33.3 ms | 27 | 1 |
| Frames >66.7 ms | 20 | 0 |

**Performance not approved.** Other Godot sessions were running, and additional
processes appeared during this work. These samples cannot isolate this change's
cost. p95 worsened beyond tolerance; p99 improved. An isolated equivalent rerun
is required, without terminating other sessions. Screenshots preserve ordinary
world occlusion (the bus shelter can cover the nearby pickup).

## Functional verification

`test_inventory_grid` and `test_pickup_feedback` pass headless. The latter covers
weapon/armor rotation, floor separation, one-shot absorption, disc fade, cleanup
and all three imported reward takes. `test_inventory_field` passed 35/35 checks
when rendered, including sound playback, bag collision, save roundtrip, no
duplicate grant and garage protections. In headless mode its two UI viewport
size assertions failed while all 33 other assertions passed; the rendered run
resolved those viewport checks. Engine texture/ObjectDB cleanup warnings remain
in test logs and also occurred in the unchanged rendered baseline.
