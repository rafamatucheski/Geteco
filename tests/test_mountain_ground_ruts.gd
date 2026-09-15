extends SceneTree
var failures := 0
func _init() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures += 1
func run() -> void:
	var ground := Polygon2D.new()
	ground.polygon = PackedVector2Array([Vector2(-200,-200),Vector2(200,-200),Vector2(200,200),Vector2(-200,200)])
	root.add_child(ground)
	preload("res://world/mountain_pass/MountainGroundMaterials.gd").apply(ground,"earth")
	var car := CharacterBody2D.new()
	root.add_child(car)
	car.add_to_group("vehicle")
	var ruts := ground.get_node("WheelRuts")
	ruts.set_physics_process(false)
	ruts._physics_process(0.1)
	car.position.x = 15
	ruts._physics_process(0.1)
	check(ruts.segments.size() == 2,"two wheel impressions during normal driving")
	car.position.x = 160
	ruts._physics_process(0.1)
	check(ruts.segments.size() == 2,"teleports do not join tracks")
	car.position.x = 400
	ruts._physics_process(0.1)
	check(ruts.segments.size() == 2,"tracks persist after leaving ground")
	ruts._physics_process(10.0)
	check(ruts.segments.size() == 2,"tracks remain during initial ten seconds")
	ruts._physics_process(5.0)
	check(ruts.segments.is_empty(),"tracks expire after fifteen seconds with vehicle gone")
	var prop := preload("res://world/mountain_pass/MountainProp.gd").new()
	prop.model_script = preload("res://world/mountain_pass/art/winter_props/LumberjackCabin3D.gd")
	root.add_child(prop)
	var actor := CharacterBody2D.new()
	actor.add_to_group("player")
	root.add_child(actor)
	actor.position.y = -50
	prop._process(0.1)
	check(prop.sprite.z_index > 10,"roof occludes player behind cabin")
	actor.position.y = 100
	prop._process(0.1)
	check(prop.sprite.z_index < 10,"player remains visible in front of cabin")
	await physics_frame
	await physics_frame
	var query := PhysicsPointQueryParameters2D.new()
	query.position = prop.global_position
	query.collision_mask = 1
	check(not root.world_2d.direct_space_state.intersect_point(query).is_empty(),"cabin floor blocks actors and vehicles")
	var water := preload("res://world/mountain_pass/MountainLakeWater.gd").new()
	water.polygon = ground.polygon
	root.add_child(water)
	check(preload("res://audio/footsteps/FootstepSurfaceResolver.gd").resolve(actor, false) == "water", "lake selects splash audio")
	water.actor_step(actor, false)
	check(water.marks.size() == 1, "water step emits splash and ripple")
	var sound := preload("res://audio/footsteps/FootstepAudioBank.gd").sound("water", 0)
	check(sound != null and sound.data.size() > 1000, "water audio contains sample data")
	quit(failures)
