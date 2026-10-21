# Prepared damage panels

These generated scene variants cover `sport_coupe` (initial car), `monaliza`
(personal car), `metro_hatch`, and `police_cruiser`. They preserve the canonical
`FleetCatalog.create()` presentation and separate its existing exterior into
three removable panels. The original fleet scenes remain the source of truth.

Regenerate with Godot 4.7.2 .NET after compiling `Harbor.csproj`, through the
shared runner so other game sessions and benchmarks are not interrupted:

```sh
GODOT_RUN_TIMEOUT=180 tools/run_godot_locked.sh --headless --path . --script res://tools/fleet_fixups/build_breakaway_prototype.gd
GODOT_RUN_TIMEOUT=180 tools/run_godot_locked.sh --headless --path . --script res://tests/test_vehicle_panel_geometry.gd
```

The baker stores source hashes, area conservation, mesh counts and panel bounds
in `manifest.json`. Extraction regions are authored per model in the baker;
there is no runtime triangle cutting for these three panels.
Append `-- --only=sport_coupe` to regenerate only that scene while preserving
the other scenes and their manifest records. The coupe additionally follows its
authored bonnet surface so the raised headlamp housings remain on the body.

Each removable panel is a direct `MeshInstance3D` child with `breakaway_part_id` equal to `hood`,
`bumper_front`, or `bumper_rear`, plus model-local `breakaway_pivot`,
`breakaway_bounds`, and `breakaway_local_direction`. Its transform is identity.
The exterior retains original material roles, UVs, UV2s, normals, colors and
tangents. The additional inner surface uses the neutral `damage_hardware` role.
Pristine mesh resources stay shared; runtime damage duplicates only the affected
instance. Paint must be bound after instantiation.

`BreakawayHardware` combines the engine bay and two bumper supports into one
fixed mesh/surface, tagged `breakaway_hardware=true`. Functional lenses, glass,
wheels and separately authored doors are excluded from extraction. Door
generation must skip both panel and fixed hardware metadata.

The geometry test checks the contract and per-instance paint isolation. It does
not approve appearance or performance: inspect intact and damaged variants in
the rendered game, then compare frame times using the same population and view.
