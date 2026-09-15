extends SceneTree

const CHAIR := preload("res://world/mountain_pass/MountainChairliftChair.gd")
const WORLD := preload("res://world/harbor/ContinuousWorld.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func run() -> void:
	var region := Node2D.new()
	region.position = WORLD.MOUNTAIN_OFFSET
	root.add_child(region)
	var area := Node2D.new()
	area.position = Vector2(75, -30)
	region.add_child(area)
	var chair := CHAIR.new()
	area.add_child(chair)
	chair.set_process(false)
	# Unequal segments and a bend make a straight endpoint lerp incorrect.
	chair.cable_points = PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 300)])
	var lane := Vector2(100, 300).direction_to(Vector2.ZERO).orthogonal() * 14.0
	for ascending in [true, false]:
		chair.is_ascending = ascending
		var offset := lane if ascending else -lane
		for sample in [
			[-0.1, Vector2(100, 300)],
			[0.0, Vector2(100, 300)],
			[0.375, Vector2(100, 150)],
			[0.75, Vector2(100, 0)],
			[0.875, Vector2(50, 0)],
			[1.0, Vector2.ZERO],
			[1.1, Vector2.ZERO],
		]:
			chair.cable_progress = sample[0]
			chair._update_position(0.0)
			var expected: Vector2 = sample[1] + offset
			expect(chair.position.is_equal_approx(expected), "chair follows cable segments at %s" % sample[0])
			expect(chair.global_position.is_equal_approx(area.to_global(expected)), "chair inherits world and area offset")
	chair.cable_points = PackedVector2Array([Vector2.ONE, Vector2.ONE])
	chair._update_position(0.0)
	expect(chair.position.is_equal_approx(Vector2.ONE), "zero-length cable remains finite")
	chair._build_view(false,Color.WHITE)
	for sway in [-.045,.045]:
		chair.model.set_swing(sway)
		var grip: Vector3 = chair.model.chair_root.to_global(Vector3(0,3.2,0))
		var pixel: Vector2 = chair.viewport_3d.get_camera_3d().unproject_position(grip)-Vector2(chair.viewport_3d.size)*.5
		expect(chair.sprite_3d.to_global(pixel).distance_to(chair.global_position)<.01,"Rendered grip stays attached to the cable during sway")
	region.free()
	print("CHAIRLIFT_WORLD_POSITION: %s (31 checks)" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
