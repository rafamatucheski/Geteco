extends SceneTree
const SYSTEM := preload("res://guns/combat/BloodTransferSystem.gd")
const WOUND := preload("res://guns/combat/BodyWound.gd")
const BLOOD := preload("res://guns/combat/GroundBlood.gd")
var failures: Array[String] = []
var checks := 0
var world: Node2D
var system: Node2D

class Walker extends Node2D:
	var walk_clock := 0.0
	var is_dead := false
	var is_flying := false
	var is_recovering := false

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func clear_effects() -> void:
	for stain in get_nodes_in_group("ground_blood"): stain.free()
	system.marks.clear()
	system._refresh_contacts()

func run() -> void:
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	system = SYSTEM.ensure(world)
	system.set_physics_process(false)
	# One wound, same elapsed time and route at four frame rates.
	for speed in [0.0, 52.0, 125.0]:
		var reference := -1
		for fps in [24, 30, 60, 144]:
			clear_effects()
			var actor := Walker.new()
			actor.add_to_group("pedestrian")
			world.add_child(actor)
			WOUND.apply(actor)
			var wound := actor.get_node("BodyWound")
			wound.set_process(false)
			system._refresh_contacts()
			check(system.tracks[actor.get_instance_id()].residue == [0.0, 0.0], "Impact does not dirty shoes without contact")
			for tick in fps * 6:
				actor.position.x += speed / fps
				wound._process(1.0 / fps)
			var stains := get_nodes_in_group("ground_blood")
			if reference < 0: reference = stains.size()
			check(stains.size() == reference, "Wound cadence independent of FPS at speed %s / %s Hz" % [speed, fps])
			check(stains.size() <= (1 if speed == 0 else 6), "Stationary/moving wound stays bounded")
			for stain in stains:
				if stain.is_drip: check(stain.radius <= 2.8 and stain.droplets.size() <= 1, "Drips remain compact")
			actor.free()
	clear_effects()
	# Flat, known pool gives both soles a true contact; marks themselves are not surfaces.
	var pool := Polygon2D.new()
	pool.polygon = PackedVector2Array([Vector2(-10,-15),Vector2(45,-15),Vector2(45,15),Vector2(-10,15)])
	pool.add_to_group("ground_blood")
	world.add_child(pool)
	var reference_positions: Array = []
	for fps in [24, 30, 60, 144]:
		system.marks.clear()
		var actor := Walker.new()
		actor.add_to_group("pedestrian")
		world.add_child(actor)
		system._refresh_contacts()
		var track: Dictionary = system.tracks[actor.get_instance_id()]
		system.sample_actor(actor, track)
		for tick in fps * 3:
			actor.position.x += 60.0 / fps
			actor.walk_clock = fposmod(actor.position.x * PI / 20.0, TAU)
			system.sample_actor(actor, track)
		var positions: Array = system.marks.map(func(m): return m.position)
		if reference_positions.is_empty(): reference_positions = positions
		check(positions.size() == reference_positions.size() and positions.size() >= 4, "Same planted contacts across frame rates")
		for index in mini(positions.size(), reference_positions.size()):
			check(positions[index].distance_to(reference_positions[index]) < 0.02, "Subframe foot placement follows phase crossing")
		check(system.marks.back().strength < system.marks.front().strength * 0.45, "Sole intensity decreases after leaving pool")
		var count: int = system.marks.size()
		for tick in 60: system.sample_actor(actor, track)
		check(system.marks.size() == count, "Stationary actor never stamps repeatedly")
		actor.free()
	var turning := Walker.new()
	turning.add_to_group("pedestrian")
	world.add_child(turning)
	system._refresh_contacts()
	var turning_track: Dictionary = system.tracks[turning.get_instance_id()]
	system.sample_actor(turning, turning_track)
	for tick in 40:
		turning.position.x += 1
		turning.walk_clock = fposmod(turning.walk_clock + PI / 20, TAU)
		system.sample_actor(turning, turning_track)
	for tick in 20:
		turning.position.y -= 1
		turning.walk_clock = fposmod(turning.walk_clock + PI / 20, TAU)
		system.sample_actor(turning, turning_track)
	check(absf(angle_difference(system.marks.back().angle, -PI / 2)) < 0.08, "Footprint rotates with a turn at the next support")
	var before_air: int = system.marks.size()
	turning.is_flying = true
	turning.position.y -= 20
	system.sample_actor(turning, turning_track)
	check(system.marks.size() == before_air and turning_track.residue == [0.0, 0.0], "Airborne motion cannot carry a ground trail")
	WOUND.apply(turning)
	turning.is_dead = true
	turning.get_node("BodyWound")._process(1.2)
	check(turning.get_node("BodyWound").is_queued_for_deletion(), "Death ends wound drips; death pool owns the effect")
	turning.free()
	pool.free()
	clear_effects()
	var actor := Walker.new()
	actor.add_to_group("pedestrian")
	world.add_child(actor)
	for index in 140: BLOOD.spawn(actor, false)
	check(get_nodes_in_group("ground_blood").size() == 64, "Same-frame burst respects global pool cap")
	await process_frame
	check(get_nodes_in_group("ground_blood").size() == 64, "Evicted pools are freed without deleting replacements")
	actor.add_to_group("vehicle")
	system._refresh_contacts()
	var loaded_track: Dictionary = system.tracks[actor.get_instance_id()]
	for index in 1200:
		loaded_track.residue = [SYSTEM.TIRE_DISTANCE, SYSTEM.TIRE_DISTANCE]
		actor.position.x += 4.0
		system.sample_actor(actor, loaded_track)
	check(system.marks.size() == SYSTEM.MAX_MARKS, "Sustained contact respects global mark budget")
	system._clock += SYSTEM.MARK_LIFETIME + 1
	system._physics_process(0)
	check(system.marks.is_empty(), "Marks expire")
	print("BLOOD_REVISION checks=", checks, " failures=", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
