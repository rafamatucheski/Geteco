extends SceneTree
const BENCH = preload("res://world/urban_detail/BenchFinish.gd")
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	for spec in [Vector4(1.6,.65,.52,1.14), Vector4(1.7,.44,.49,.93), Vector4(1.9,.48,.59,1.115), Vector4(2.2,.65,.55,1.1), Vector4(3.75,.75,.54,1.14), Vector4(4.6,.9,.59,0), Vector4(2.2,.32,.51,0), Vector4(1.5,.46,.55,1.115), Vector4(4.06,1.18,.6025,1.245)]:
		var model := BENCH.create(spec.x,spec.y,spec.z,spec.w)
		var copy := BENCH.create(spec.x,spec.y,spec.z,spec.w)
		var bounds := model.mesh.get_aabb()
		check(bounds.position.y >= -.001, "Bench feet below floor " + str(spec))
		check(bounds.end.y <= maxf(spec.z,spec.w)+.001, "Bench exceeds authored height " + str(spec))
		check(bounds.size.x <= spec.x+.001 and bounds.size.z <= spec.y+.001, "Bench exceeds collision footprint " + str(spec))
		check(model.mesh == copy.mesh and model.mesh.get_surface_count() == 2, "Bench fails shared two-surface geometry")
		check(model.mesh.surface_get_material(0).albedo_texture != null, "Wood has no texture")
		check(model.get_meta("seat_top") == spec.z, "Seat height changed")
		model.free()
		copy.free()
	print("BENCH_FINISH checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)
