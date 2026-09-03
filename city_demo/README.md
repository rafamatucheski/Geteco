# GETECO Godot vertical slice

This folder is intentionally isolated from the existing player/car prototype.

- `CityDemo.gd` creates one fixed four-block district.
- Roads and sidewalks use a native `TileMapLayer`.
- Twelve visible traffic actors use `Path2D`/`PathFollow2D` and two-way lanes.
- The registry in `data/traffic.json` keeps all 50 named vehicles available.
- Pedestrians use `NavigationRegion2D`/`NavigationAgent2D` and four directional frames.
- Buildings are fixed `Sprite2D` + `StaticBody2D`; there is no camera-relative redraw.

The previous prototype nodes remain in `Main.tscn`, disabled and hidden for rollback.
