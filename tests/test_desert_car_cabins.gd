extends SceneTree
## Actual fleet cabins: interior fit, opaque painted roofs and isolated glazing.
const VEHICLE := preload("res://scripts/Vehicle.gd")
const CATALOG := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const INTERIOR := preload("res://gameplay/VehicleInterior.gd")
const ROLES := preload("res://runtime/VehicleSurfaceRoles.gd")
const CABIN := preload("res://gameplay/desert_cars/DesertCarCabin.gd")
const COUPE := preload("res://gameplay/desert_cars/DesertZShape.gd")
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	checks += 1
	if ok:
		return
	failures.append(label)
	push_error(label)


func _spawn(id: String, identity: String, at: Vector3) -> CharacterBody3D:
	var car := VEHICLE.new()
	car.archetype = id
	car.vehicle_id = identity
	car.position = at
	root.add_child(car)
	car.set_physics_process(false)
	return car


func _run() -> void:
	_check(CATALOG.ids().size() >= 8, "All eight authored desert models are covered")
	for id: String in CATALOG.ids():
		_test_car(id)
	await process_frame
	print(
		"DESERT_CAR_CABINS_",
		"PASS" if failures.is_empty() else "FAIL",
		" checks=",
		checks,
		" failures=",
		failures.size()
	)
	quit(0 if failures.is_empty() else 1)


func _test_car(id: String) -> void:
	var spec: Dictionary = CATALOG.spec(id)
	var car := _spawn(id, "cabin_owner_" + id, Vector3.ZERO)
	var sibling := _spawn(id, "cabin_traffic_" + id, Vector3(8, 0, 0))
	var sibling_state := _snapshot(sibling.visual)
	_check(
		car.visual.has_meta("vehicle_interior_spec"),
		id + ": exterior carries its authored cabin dimensions"
	)
	_check_opaque_paint(car, id + ": before boarding")
	car.finish_doors()
	_check(
		car.door_presentation != null and car.door_presentation.ready_for_boarding,
		id + ": real door preparation completes"
	)
	var roof_before := _roof_area(car, spec)
	_check(roof_before > .20, id + ": fixture has a real painted roof")
	var glass_before := _glazing(car.visual)
	_check(not glass_before.is_empty(), id + ": cabin has glazing independent of paint")
	var mirrors := _mirror_surfaces(car, spec)
	_check(not mirrors.is_empty(), id + ": exterior reflective mirrors remain present")
	for entry: Dictionary in mirrors:
		_check(
			not INTERIOR._is_glass(entry.part, entry.surface, entry.material),
			id + ": exterior mirror is excluded from cabin glazing"
		)
	INTERIOR.attach(car)
	INTERIOR.attach(car)
	_check(
		car.visual.find_children("Interior", "MeshInstance3D", true, false).size() == 1,
		id + ": repeated boarding creates one interior"
	)
	var inside := car.visual.get_node_or_null("Interior") as MeshInstance3D
	_check(inside != null, id + ": boarding builds a real interior")
	if inside != null:
		_check_envelope(car, inside, spec, id)
	_check_opaque_paint(car, id + ": after boarding")
	_check_glazing(car, false, id + ": normal camera")
	var original_glass := glass_before
	_check_mirrors(mirrors, id + ": boarding")
	_check_roof(car, spec, roof_before, id + ": boarding")
	INTERIOR.set_low_camera_roof(car, true)
	_check_glazing(car, false, id + ": low camera")
	_check_opaque_paint(car, id + ": low camera")
	_check_mirrors(mirrors, id + ": low camera")
	_check_roof(car, spec, roof_before, id + ": low camera")
	INTERIOR.set_low_camera_roof(car, false)
	_check_glazing(car, false, id + ": restored normal camera")
	_check_glass_restored(original_glass, id)
	car.paint_color = Color("aa4c32")
	_check_opaque_paint(car, id + ": repainted after boarding")
	_check_roof(car, spec, roof_before, id + ": repainted after boarding")
	for paint: StandardMaterial3D in car._paint.materials:
		_check(
			paint.albedo_color.is_equal_approx(car.paint_color),
			id + ": repaint reaches actual body and door materials"
		)
	_check_glazing(car, false, id + ": repaint preserves glazing")
	_check_mirrors(mirrors, id + ": repaint")
	_check(
		_same_snapshot(sibling_state),
		id + ": sibling meshes and materials survive boarding, cameras and repaint unchanged"
	)
	_check(
		not sibling.visual.has_node("Interior"),
		id + ": boarding does not add an interior to traffic sibling"
	)
	INTERIOR.set_low_camera_roof(car, true)
	INTERIOR.close_view(car)
	_check_opaque_paint(car, id + ": close view from low camera")
	_check_roof(car, spec, roof_before, id + ": close view from low camera")
	INTERIOR.attach(car)
	_check_glazing(car, false, id + ": reboard after close view")
	_check_opaque_paint(car, id + ": reboard after close view")
	_check(_same_snapshot(sibling_state), id + ": reboarding preserves shared traffic resources")
	car.free()
	sibling.free()


func _check_opaque_paint(car: CharacterBody3D, label: String) -> void:
	var painted := 0
	var opaque := true
	for part: MeshInstance3D in car.visual.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null or part.name == "Interior":
			continue
		for surface in part.mesh.get_surface_count():
			if ROLES.key(part, surface) not in ["paint", "roof_paint"]:
				continue
			painted += 1
			var material := part.get_active_material(surface) as StandardMaterial3D
			opaque = (
				opaque
				and material != null
				and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
				and material.albedo_color.a >= .999
				and material.albedo_texture == null
			)
	_check(painted > 0 and opaque, label + ": all painted roof/body surfaces stay opaque")


func _check_roof(car: CharacterBody3D, spec: Dictionary, before: float, label: String) -> void:
	_check(
		car.visual.find_children("RoofCut*", "MeshInstance3D", true, false).is_empty(),
		label + ": no replacement or translucent roof is created"
	)
	_check(
		absf(_roof_area(car, spec) - before) < .002, label + ": painted roof geometry is preserved"
	)


func _check_glazing(car: CharacterBody3D, transparent: bool, label: String) -> void:
	var entries := _glazing(car.visual)
	var correct := not entries.is_empty()
	for entry: Dictionary in entries:
		var material: StandardMaterial3D = entry.material
		if transparent:
			correct = (
				correct
				and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA
				and material.albedo_color.a > .1
				and material.albedo_color.a < .75
			)
		else:
			correct = (
				correct
				and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
				and material.albedo_color.a >= .999
			)
	_check(correct, label + ": cabin glazing has the expected visibility")


func _glazing(visual: Node3D) -> Array:
	var entries: Array = []
	for part: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null or part.name == "Interior":
			continue
		for surface in part.mesh.get_surface_count():
			if ROLES.key(part, surface) not in ["glass", "tinted_glass", "windshield", "window"]:
				continue
			var material := part.get_active_material(surface) as StandardMaterial3D
			if material != null:
				entries.append({"part": part, "surface": surface, "material": material})
	return entries


func _check_glass_restored(entries: Array, id: String) -> void:
	var restored := true
	for entry: Dictionary in entries:
		var part: MeshInstance3D = entry.part
		restored = restored and part.get_active_material(entry.surface) == entry.material
	_check(restored, id + ": returning from low camera preserves the original glass materials")


func _mirror_surfaces(car: CharacterBody3D, spec: Dictionary) -> Array:
	var result: Array = []
	var width: float = float(spec["size"][0])
	var belt: float = float(spec.shoulder)
	for part: MeshInstance3D in car.visual.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null:
			continue
		var transform: Transform3D = car.global_transform.affine_inverse() * part.global_transform
		for surface in part.mesh.get_surface_count():
			var material := part.get_active_material(surface) as StandardMaterial3D
			if material == null or material.metallic < .65 or material.roughness > .35:
				continue
			var arrays := part.mesh.surface_get_arrays(surface)
			for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				var point: Vector3 = transform * vertex
				if absf(point.x) > width * .515 and point.y > belt + .12 and point.y < belt + .26:
					result.append({"part": part, "surface": surface, "material": material})
					break
	return result


func _check_mirrors(entries: Array, label: String) -> void:
	var correct := true
	for entry: Dictionary in entries:
		var part: MeshInstance3D = entry.part
		var material := part.get_active_material(entry.surface) as StandardMaterial3D
		correct = (
			correct
			and material == entry.material
			and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
		)
	_check(correct, label + ": reflective mirror surfaces stay separate and opaque")


func _check_envelope(
	car: CharacterBody3D, inside: MeshInstance3D, spec: Dictionary, id: String
) -> void:
	var width: float = float(spec["size"][0])
	var height: float = float(spec["size"][1])
	var length: float = float(spec["size"][2])
	var belt: float = float(spec.shoulder)
	var transform: Transform3D = car.global_transform.affine_inverse() * inside.global_transform
	var min_y := INF
	var max_y := -INF
	var max_x := 0.0
	var outside_side := 0.0
	var above_roof := 0.0
	var roof_samples := 0
	var unique: Dictionary = {}
	var opaque := true
	for surface in inside.mesh.get_surface_count():
		var material := inside.get_active_material(surface) as StandardMaterial3D
		opaque = (
			opaque
			and material != null
			and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
		)
		var arrays := inside.mesh.surface_get_arrays(surface)
		for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			var point: Vector3 = transform * vertex
			var key := Vector3i(
				roundi(point.x * 1000), roundi(point.y * 1000), roundi(point.z * 1000)
			)
			if unique.has(key):
				continue
			unique[key] = true
			min_y = minf(min_y, point.y)
			max_y = maxf(max_y, point.y)
			max_x = maxf(max_x, absf(point.x))
			if point.y > belt + .10:
				var skin: Vector3 = (
					COUPE._cabin_side(spec, 1.0, point.z, point.y)
					if str(spec.body) == "coupe"
					else CABIN._side_point(spec, 1.0, point.z, point.y)
				)
				outside_side = maxf(outside_side, absf(point.x) - absf(skin.x))
			if (
				point.y > height - .25
				and point.z >= length * float(spec.roof_front)
				and point.z <= length * float(spec.roof_back)
			):
				var roof: Vector3 = (
					COUPE.roof_point(spec, point.x, point.z)
					if str(spec.body) == "coupe"
					else CABIN.roof_point(spec, point.x, point.z)
				)
				above_roof = maxf(above_roof, point.y - roof.y)
				roof_samples += 1
	_check(opaque, id + ": interior contains no translucent external headliner")
	_check(max_x <= width * .47, id + ": interior fits inside body width, independent of mirrors")
	_check(
		outside_side <= .025,
		(
			id
			+ (
				": raised trim and seats remain inside actual tapered cabin sides (overrun %.3f m)"
				% outside_side
			)
		)
	)
	_check(
		max_y < height - .01 and roof_samples > 0 and above_roof <= .025,
		id + ": interior stays below actual curved roof (overrun %.3f m)" % above_roof
	)
	_check(
		min_y >= float(spec.wheel_radius) * .72 - .035,
		id + ": cabin floor/console stay above the chassis underside (bottom %.3f m)" % min_y
	)
	print(
		"DESERT_CABIN_ENVELOPE ",
		id,
		" ",
		JSON.stringify(
			{
				"min_y": min_y,
				"max_y": max_y,
				"max_half_width": max_x,
				"side_overrun": outside_side,
				"roof_overrun": above_roof,
				"roof_samples": roof_samples
			}
		)
	)


func _roof_area(car: CharacterBody3D, spec: Dictionary) -> float:
	var area := 0.0
	var height: float = float(spec["size"][1])
	var length: float = float(spec["size"][2])
	for part: MeshInstance3D in car.visual.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null or part.name == "Interior":
			continue
		var transform: Transform3D = car.global_transform.affine_inverse() * part.global_transform
		for surface in part.mesh.get_surface_count():
			if ROLES.key(part, surface) not in ["paint", "roof_paint"]:
				continue
			var arrays := part.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = (
				arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			)
			var count := vertices.size() if indices.is_empty() else indices.size()
			for triangle in range(0, count, 3):
				var a: Vector3 = (
					transform * vertices[triangle if indices.is_empty() else indices[triangle]]
				)
				var b: Vector3 = (
					transform
					* vertices[triangle + 1 if indices.is_empty() else indices[triangle + 1]]
				)
				var c: Vector3 = (
					transform
					* vertices[triangle + 2 if indices.is_empty() else indices[triangle + 2]]
				)
				var center := (a + b + c) / 3.0
				var normal := (b - a).cross(c - a)
				if (
					center.y < height - .20
					or center.z < length * float(spec.roof_front)
					or center.z > length * float(spec.roof_back)
					or absf(normal.normalized().y) < .7
				):
					continue
				area += normal.length() * .5
	return area


func _snapshot(visual: Node3D) -> Array:
	var result: Array = []
	for part: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null:
			continue
		for surface in part.mesh.get_surface_count():
			var material: Material = part.get_active_material(surface)
			var row := {
				"part": part,
				"mesh": part.mesh,
				"surface": surface,
				"material": material,
				"visible": part.visible
			}
			if material is StandardMaterial3D:
				row["color"] = material.albedo_color
				row["transparency"] = material.transparency
				row["texture"] = material.albedo_texture
			result.append(row)
	return result


func _same_snapshot(entries: Array) -> bool:
	for entry: Dictionary in entries:
		var part: MeshInstance3D = entry.part
		if not is_instance_valid(part) or part.mesh != entry.mesh or part.visible != entry.visible:
			return false
		var material: Material = part.get_active_material(entry.surface)
		if material != entry.material:
			return false
		if (
			material is StandardMaterial3D
			and (
				material.albedo_color != entry.color
				or material.transparency != entry.transparency
				or material.albedo_texture != entry.texture
			)
		):
			return false
	return true
