extends "res://tests/measure/measure_desert_horizon.gd"
## Rendered visual review only. Reuses real Main setup and camera, never reports FPS.
func sample_warmup() -> void:
	await create_timer(1.0).timeout

func measure_grid(id: String) -> void:
	reports.append({"id":id,"visual_only":true,"performance_measured":false})

func metadata() -> Dictionary:
	var result := super.metadata()
	result.scenario="desert_relief_visual_preview"
	result.notes="Visual-only screenshots in actual Main using production drag and normal cameras. Fixture repositions are not traversal evidence. No frame-time measurement or FPS approval."
	return result
