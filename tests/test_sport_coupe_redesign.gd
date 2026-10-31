extends SceneTree
## Orçamento de geometria e contratos funcionais do cupê esportivo autoral.
## Usa código real de Vehicle, equipamento, pintura, dano e portas; sem save pessoal.
const VEHICLE := preload("res://scripts/Vehicle.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const BASELINE_MESHES := 39
const BASELINE_TRIANGLES := 61087
const TARGET_TRIANGLES := 12000
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func metrics(model: Node3D) -> Dictionary:
	var result := {"meshes":0,"surfaces":0,"triangles":0}
	for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null: continue
		result.meshes += 1
		result.surfaces += part.mesh.get_surface_count()
		for surface in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(surface)
			var count: int = arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX] != null and not arrays[Mesh.ARRAY_INDEX].is_empty() else arrays[Mesh.ARRAY_VERTEX].size()
			result.triangles += int(count / 3)
	return result

func spawn(stage: Node3D, color: Color, at: Vector3) -> CharacterBody3D:
	var car := VEHICLE.new()
	car.archetype = "sport_coupe"
	car.paint_color = color
	car.position = at
	stage.add_child(car)
	car.set_physics_process(false)
	return car

func run() -> void:
	var model := FLEET.create("sport_coupe")
	var geometry := metrics(model)
	check(geometry.meshes < BASELINE_MESHES, "fewer runtime meshes than the 39-mesh baseline")
	check(geometry.surfaces < BASELINE_MESHES, "fewer material surfaces than the 39-surface baseline")
	check(geometry.triangles < BASELINE_TRIANGLES and geometry.triangles <= TARGET_TRIANGLES, "triangle budget <=12000 and below 61087 baseline")
	model.free()
	var stage := Node3D.new()
	root.add_child(stage)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	ground.add_child(shape)
	stage.add_child(ground)
	var a := spawn(stage, Color("b63b32"), Vector3(0, .05, 0))
	var b := spawn(stage, Color("31577a"), Vector3(9, .05, 0))
	check(a.wheels.size() == 4, "four independently animated wheel pivots")
	var front := 0
	var anchors := []
	for pivot: Node3D in a.wheels:
		if pivot.get_meta("front", false): front += 1
		anchors.append(pivot.position)
		check(absf(absf(pivot.position.x) - .86) < .01 and absf(pivot.position.y - .36) < .01, "wheel lateral and height anchors preserved")
	check(front == 2, "two front steering wheels")
	check(anchors.has(Vector3(-.86,.36,-1.28)) and anchors.has(Vector3(.86,.36,1.22)), "front/rear axle positions preserved")
	check(not a._paint.materials.is_empty() and not b._paint.materials.is_empty(), "paint surfaces are bound on both instances")
	if a._paint.materials.is_empty() or b._paint.materials.is_empty():
		stage.free(); finish(geometry); return
	var first_paint: StandardMaterial3D = a._paint.materials[0]
	var second_paint: StandardMaterial3D = b._paint.materials[0]
	a.paint_color = Color("d5a544")
	check(first_paint != second_paint and second_paint.albedo_color.is_equal_approx(Color("31577a")), "painting one coupe does not repaint another")
	for material: StandardMaterial3D in a._paint.materials:
		check(material.albedo_color.is_equal_approx(Color("d5a544")), "all authored paint surfaces receive the new paint")
	var leaves := {}
	for part: MeshInstance3D in a.visual.find_children("*", "MeshInstance3D", true, false):
		if part.has_meta("coupe_gt_door_side"):
			leaves[int(part.get_meta("coupe_gt_door_side"))] = {"node":part,"mesh":part.mesh,"transform":part.global_transform}
	check(leaves.size() == 2, "both authored door leaves exist")
	var before_doors := metrics(a.visual)
	a.finish_doors()
	check(a.door_presentation.ready_for_boarding and a.door_presentation.coupe_ready, "authored doors enter the existing boarding path")
	check(metrics(a.visual) == before_doors, "preparing doors adds no meshes, surfaces or triangles")
	for side in [-1, 1]:
		if not leaves.has(side): continue
		var record: Dictionary = leaves[side]
		var leaf: MeshInstance3D = record.node
		check(leaf.mesh == record.mesh and leaf.global_transform.is_equal_approx(record.transform), "door reparenting preserves mesh and closed world pose")
		a.animate_driver_door(side, true, 0.0)
		check(absf(a.door_presentation.hinges[side].rotation.y) > 1.0, "door opens on its hinge")
		check(not leaf.global_transform.is_equal_approx(record.transform), "opening moves the actual authored door")
		a.animate_driver_door(side, false, 0.0)
		check(leaf.global_transform.is_equal_approx(record.transform), "closing restores the exact authored pose")
	a.paint_color = Color("6a963b")
	check(first_paint.albedo_color.is_equal_approx(Color("6a963b")) and second_paint.albedo_color.is_equal_approx(Color("31577a")), "paint stays independent after door preparation")
	var original_roughness := first_paint.roughness
	a.receive_damage(a.max_health * .55)
	check(first_paint.albedo_color.is_equal_approx(Color("6a963b")) and first_paint.detail_enabled, "damage adds wear while preserving paint hue")
	a.repair()
	check(a.health == a.max_health and not first_paint.detail_enabled and is_equal_approx(first_paint.roughness, original_roughness), "repair restores authored paint finish and health")
	check(second_paint.albedo_color.is_equal_approx(Color("31577a")), "damage and repair do not touch the other coupe")
	# O movimento real prova que a animação existente das rodas ainda aciona as rodas novas.
	a.set_external_driver(true)
	a.brake_input = false
	a.throttle_input = 1.0
	a.set_physics_process(true)
	var start := a.global_position
	for frame in 90: await physics_frame
	a.set_physics_process(false)
	check(a.global_position.distance_to(start) > 1.0, "coupe still moves using real Vehicle physics")
	check(a.is_on_floor(), "coupe remains supported by the ground")
	check(a.wheels.size() == 4 and absf(a.wheel_spin) > .1, "new wheels spin during physical movement")
	stage.free()
	await process_frame
	finish(geometry)

func finish(geometry: Dictionary) -> void:
	print("SPORT_COUPE_REDESIGN ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " geometry=", JSON.stringify(geometry), " failures=", failures)
	quit(0 if failures.is_empty() else 1)
