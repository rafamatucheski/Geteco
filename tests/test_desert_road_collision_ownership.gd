extends SceneTree
## A pista e a areia conservam aparência/altura; um só colisor possui cada ponto.
const GEOMETRY := preload("res://world/desert/DesertGeometry.gd")
const OWNERSHIP := preload("res://world/desert/DesertGroundOwnership.gd")
const PROBE := preload("res://gameplay/vehicle_effects/VehicleSurfaceProbe.gd")
const REGION := preload("res://world/desert/DesertRegion.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const BRIDGE := preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(60).timeout.connect(func(): push_error("DESERT_ROAD_OWNERSHIP timeout"); quit(3))
	_run.call_deferred()

func _run() -> void:
	var chunk := Node3D.new()
	root.add_child(chunk)
	var corners := PackedVector3Array([Vector3(-10, 0, -10), Vector3(10, 0, -10), Vector3(10, 0, 10), Vector3(-10, 0, 10)])
	var material := StandardMaterial3D.new()
	var ground := GEOMETRY.quad(chunk, "DesertGround", corners, material, true)
	ground.set_meta("desert_base_ground", true)
	ground.set_meta("vehicle_surface", "dirt")
	var visual_mesh := ground.mesh
	var asphalt := GEOMETRY.quad(chunk, "WeatheredAsphalt", PackedVector3Array([Vector3(-10, 0, -2), Vector3(10, 0, -2), Vector3(10, 0, 2), Vector3(-10, 0, 2)]), material, true)
	asphalt.set_meta("vehicle_surface", "hard")
	var corridor := PackedVector2Array([Vector2(-10, -2), Vector2(10, -2), Vector2(10, 2), Vector2(-10, 2)])
	var rows: Array[Dictionary] = [{"bounds": Rect2(-10, -2, 20, 4), "polygon": corridor}]
	OWNERSHIP.compose_collision(chunk, Rect2(-10, -10, 20, 20), rows)
	check(ground.mesh == visual_mesh, "posse física preserva malha visual")
	var first_faces: PackedVector3Array = ground.get_child(0).get_child(0).shape.get_faces()
	OWNERSHIP.compose_collision(chunk, Rect2(-10, -10, 20, 20), rows)
	check(ground.get_child(0).get_child(0).shape.get_faces() == first_faces, "repetir composição não refaz nem degrada colisão")
	await physics_frame
	await physics_frame
	var vehicle := CharacterBody3D.new()
	vehicle.collision_layer = 0
	root.add_child(vehicle)
	for at in [Vector3(0, .2, 0), Vector3(9.99, .2, 0), Vector3(0, .2, 1.99)]:
		var hit := PROBE.sample(vehicle, at)
		check(not hit.is_empty() and hit.kind == "hard" and absf(hit.point.y) < .001, "pista plana tem apoio único hard em " + str(at))
	var sand := PROBE.sample(vehicle, Vector3(0, .2, 2.01))
	check(not sand.is_empty() and sand.kind == "dirt" and absf(sand.point.y) < .001, "areia imediatamente fora da pista mantém apoio dirt")
	var road_body: StaticBody3D = asphalt.get_child(0)
	var query := PhysicsRayQueryParameters3D.create(Vector3(0, 1, 0), Vector3(0, -1, 0), 1, [road_body.get_rid(), vehicle.get_rid()])
	check(root.world_3d.direct_space_state.intersect_ray(query).is_empty(), "não resta areia física duplicada sob asfalto")
	var whole := GEOMETRY.quad(chunk, "CoveredGround", corners, material, true)
	whole.set_meta("desert_base_ground", true)
	var complete: Array[Dictionary] = [{"bounds": Rect2(-11, -11, 22, 22), "polygon": PackedVector2Array([Vector2(-11, -11), Vector2(11, -11), Vector2(11, 11), Vector2(-11, 11)])}]
	OWNERSHIP.compose_collision(chunk, Rect2(-10, -10, 20, 20), complete)
	check(whole.get_child(0).get_child(0).disabled, "solo totalmente coberto desativa shape sem remover nós")
	vehicle.free()
	chunk.free()
	await physics_frame
	await _production_surfaces()
	for failure in failures: print("FALHOU: ", failure)
	print("test_desert_road_collision_ownership checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _production_surfaces() -> void:
	var region := REGION.new()
	region.initial_prewarm_only = true
	root.add_child(region)
	region.set_process(false)
	var cells := {}
	# Rodovia fora dos pátios, T do posto, emenda 96 m e rampa da ponte.
	for key in [Vector2i(3, -11), Vector2i(3, -10), Vector2i(3, -9), Vector2i(3, -8), Vector2i(3, -5)]:
		var cell := Node3D.new()
		region.add_child(cell)
		region._build_surfaces(cell, Rect2(Vector2(key) * 96.0, Vector2.ONE * 96.0))
		cells[key] = cell
	await physics_frame
	await physics_frame
	var wheel := CharacterBody3D.new()
	wheel.collision_layer = 0
	root.add_child(wheel)
	var asphalt_samples: Array[Vector3] = [
		Vector3(342.5, 0, -1050), Vector3(342.5, 0, -750),
		Vector3(342.5, 0, -960.05), Vector3(342.5, 0, -960),
		Vector3(342.5, 0, -959.95), Vector3(347.49, 0, -1050),
		Vector3(342.5, LAYOUT.surface_height(Vector2(342.5, -420)), -420)]
	for at in asphalt_samples:
		var contact := PROBE.sample(wheel, at + Vector3.UP * .2)
		check(not contact.is_empty() and contact.kind == "hard", "builder real conserva contato hard em " + str(at))
		var hits := _hits(at)
		var owned := not hits.is_empty()
		for hit in hits:
			if PROBE._surface_kind(hit.collider, hit.position) != "hard": owned = false
		check(owned, "builder real não deixa areia coplanar sob pista em " + str(at))
		if contact.is_empty(): continue
		var key := Vector2i(floori(at.x / 96.0), floori(at.z / 96.0))
		var asphalt: MeshInstance3D = cells[key].get_node_or_null("WeatheredAsphalt")
		var visual_y := _visual_y(asphalt, Vector2(at.x, at.z))
		var finish_offset := .026 if BRIDGE.enabled() else .018
		var expected_offset := finish_offset if BRIDGE.enabled() else 0.0
		check(not is_nan(visual_y) and absf(visual_y - contact.point.y - expected_offset) < .002, "acabamento visual mantém altura física prevista em " + str(at))
	for at in [Vector3(347.51, 0, -1050), Vector3(352, 0, -770)]:
		var contact := PROBE.sample(wheel, at + Vector3.UP * .2)
		check(not contact.is_empty() and contact.kind == "dirt" and absf(contact.point.y) < .001, "builder real preserva areia fora da pista em " + str(at))
	wheel.free()
	var car := VEHICLE.new()
	car.set("archetype", "jessica_jetta_gli")
	root.add_child(car)
	car.set_process(false)
	car.set_physics_process(false)
	var seam := await _drive(car, Vector3(342.5, .08, -951), Vector3(342.5, .08, -969), 8.0)
	check(seam.ok, "veículo real cruza emenda sem travar ou perder apoio: " + str(seam))
	var edge := await _drive(car, Vector3(344, .08, -1050), Vector3(350, .08, -1050), 3.0)
	check(edge.ok, "veículo real cruza borda asfalto/areia sem degrau ou buraco: " + str(edge))
	car.free()
	region.free()

func _hits(at: Vector3) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var exclude: Array[RID] = []
	for attempt in 8:
		var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 2, at + Vector3.DOWN * 2, 1, exclude)
		var hit: Dictionary = root.world_3d.direct_space_state.intersect_ray(query)
		if hit.is_empty(): break
		found.append(hit)
		exclude.append(hit.rid)
	return found

func _visual_y(node: MeshInstance3D, at: Vector2) -> float:
	if node == null or node.mesh == null: return NAN
	var faces := node.mesh.get_faces()
	for offset in range(0, faces.size(), 3):
		var a := Vector2(faces[offset].x, faces[offset].z)
		var b := Vector2(faces[offset + 1].x, faces[offset + 1].z)
		var c := Vector2(faces[offset + 2].x, faces[offset + 2].z)
		var denominator := (b - a).cross(c - a)
		if absf(denominator) < .000001: continue
		var wb := (at - a).cross(c - a) / denominator
		var wc := (b - a).cross(at - a) / denominator
		var wa := 1.0 - wb - wc
		if minf(wa, minf(wb, wc)) >= -.00001: return faces[offset].y * wa + faces[offset + 1].y * wb + faces[offset + 2].y * wc
	return NAN

func _drive(car: CharacterBody3D, start: Vector3, finish: Vector3, speed: float) -> Dictionary:
	var direction := (finish - start).normalized()
	car.position = start
	car.rotation.y = atan2(-direction.x, -direction.z)
	car.velocity = Vector3.ZERO
	var delta := 1.0 / float(Engine.physics_ticks_per_second)
	for settle in 24:
		await physics_frame
		car.velocity = Vector3(0, 0 if car.is_on_floor() else car.velocity.y - 18.0 * delta, 0)
		car.move_and_slide()
	var missing_floor := 0
	for frame in range(ceili(start.distance_to(finish) / speed / delta) + 90):
		await physics_frame
		car.velocity = direction * speed
		car.velocity.y = 0.0 if car.is_on_floor() else -18.0 * delta
		car.move_and_slide()
		if not car.is_on_floor(): missing_floor += 1
		if car.position.y < -.3 or car.position.y > 1.0: return {"ok": false, "position": car.position, "floor_lost": missing_floor}
		if (car.position - start).dot(direction) >= start.distance_to(finish) - .2:
			return {"ok": missing_floor <= 2, "position": car.position, "floor_lost": missing_floor}
	return {"ok": false, "position": car.position, "floor_lost": missing_floor}

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)
