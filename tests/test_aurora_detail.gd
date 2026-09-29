extends SceneTree
## Aurora Executive L: casco com as duas laterais visíveis, acabamentos e menos peças, sem
## perder o que os outros sistemas procuram (rodas, tinta, faróis, lanternas, vidro).
## Não certifica aparência nem FPS; as imagens estão em evidence/car-review/.
const CATALOG := preload("res://runtime/FleetCatalog.gd")
const DETAIL := preload("res://runtime/AuroraExecutiveDetail.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	print("AURORA ", "PASS " if condition else "FAIL ", label)
	if not condition: failures.append(label)

func mesh_parts(root_node: Node) -> Array:
	return root_node.find_children("*", "MeshInstance3D", true, false)

func triangles(part: MeshInstance3D) -> int:
	var total := 0
	for s in part.mesh.get_surface_count():
		var arrays := part.mesh.surface_get_arrays(s)
		var idx: Variant = arrays[Mesh.ARRAY_INDEX]
		total += (idx.size() if idx != null and idx.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return total

func run() -> void:
	# Modelo de fábrica, sem nenhum acabamento em tempo de execução.
	var raw: Node3D = (load("res://assets/fleet/aurora_executive.scn") as PackedScene).instantiate()
	var raw_parts := mesh_parts(raw)
	var raw_wheel_tris := 0
	for part in raw_parts: if part.has_meta("wheel_center"): raw_wheel_tris += triangles(part)
	var model: Node3D = CATALOG.create("aurora_executive")
	var parts := mesh_parts(model)
	check(parts.size() < 60 and raw_parts.size() >= 100, "peças caem de %d para %d" % [raw_parts.size(), parts.size()])
	var wheel_tris := 0
	var centers := {}
	var spin_parts := 0
	for part in parts:
		if part.has_meta("wheel_center"):
			wheel_tris += triangles(part)
			centers[part.get_meta("wheel_center")] = true
			if part.get_meta("wheel_spins", true): spin_parts += 1
	check(wheel_tris == raw_wheel_tris, "as rodas conservam todos os triângulos (%d)" % wheel_tris)
	check(centers.size() == 4 and spin_parts >= 8, "quatro eixos de roda e peças que giram em cada um (%d)" % spin_parts)
	check(DETAIL.flipped_triangles >= 240, "casco: %d triângulos de flanco tiveram o enrolamento corrigido" % DETAIL.flipped_triangles)
	# Nenhum triângulo do casco pode ficar de costas para fora (o Godot o descartaria).
	var hull: MeshInstance3D = null
	var best := 0
	for part in parts:
		if part.mesh is ArrayMesh and part.mesh.get_surface_count() == 1 and not part.has_meta("wheel_center") and part.material_override != null and part.material_override.resource_name == "paint":
			var n: int = part.mesh.surface_get_array_len(0)
			if n > best:
				best = n
				hull = part
	var arrays := hull.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var wrong := 0
	var flank_visible := 0
	var count := (idx.size() if idx.size() > 0 else v.size()) / 3
	for t in count:
		var a := v[idx[t * 3] if idx.size() > 0 else t * 3]
		var b := v[idx[t * 3 + 1] if idx.size() > 0 else t * 3 + 1]
		var c := v[idx[t * 3 + 2] if idx.size() > 0 else t * 3 + 2]
		var g := (b - a).cross(c - a)
		var middle := (a + b + c) / 3.0 - DETAIL.HULL_CENTER
		var outward := Vector3(middle.x / (DETAIL.HULL_RADII.x * DETAIL.HULL_RADII.x), middle.y / (DETAIL.HULL_RADII.y * DETAIL.HULL_RADII.y), middle.z / (DETAIL.HULL_RADII.z * DETAIL.HULL_RADII.z))
		if g.length_squared() > 1e-10 and g.dot(outward) > 0.0: wrong += 1
		elif absf((a + b + c).x / 3.0) > 0.85 and g.length_squared() > 1e-10: flank_visible += 1
	check(wrong == 0 and flank_visible > 150, "todo o casco fica virado para fora; %d triângulos de flanco visíveis" % flank_visible)
	# Linhas de porta: pontos do flanco achados por raio devem estar sobre o casco.
	var dark: MeshInstance3D = model.get_node("Aurora_dark")
	var dv: PackedVector3Array = dark.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var door_vertices := 0
	var off_hull := 0.0
	for p in dv:
		if absf(p.x) > 0.9 and p.z > -1.0 and p.z < 1.5 and p.y > 0.44 and p.y < 0.86 and absf(absf(p.x) - absf(DETAIL.hull_x(signf(p.x), p.y, p.z))) < 0.5:
			door_vertices += 1
			var x := DETAIL.hull_x(signf(p.x), p.y, p.z)
			off_hull = maxf(off_hull, absf(absf(p.x) - absf(x)))
	check(door_vertices >= 60 and off_hull < 0.02, "linhas de porta: %d vértices, no máximo %.1f mm da chapa" % [door_vertices, off_hull * 1000.0])
	# Sistemas que procuram peças por material, num Vehicle de verdade.
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	floor_shape.shape = box
	floor_body.position.y = -.5
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	var car := VEHICLE.new()
	car.archetype = "aurora_executive"
	car.vehicle_id = "aurora_test"
	world.add_child(car)
	car.position = Vector3(0, .1, 0)
	car.ensure_equipment(world)
	for _i in 30: await physics_frame
	check(car.wheels.size() == 4, "Vehicle registra 4 pivôs de roda (%d)" % car.wheels.size())
	check(car._paint.materials.size() >= 1, "tinta continua ligada à carroceria (%d materiais)" % car._paint.materials.size())
	car.paint_color = Color("b3372d")
	var tinted := false
	for material in car._paint.materials: tinted = tinted or material.albedo_color.is_equal_approx(Color("b3372d"))
	check(tinted, "trocar paint_color repinta")
	check(car.equipment.lens_materials.size() >= 2 and car.equipment.tail_materials.size() >= 1, "faróis (%d) e lanternas (%d) reconhecidos pelo equipamento" % [car.equipment.lens_materials.size(), car.equipment.tail_materials.size()])
	car.set_external_driver(true)
	car.throttle_input = 1.0
	car.brake_input = false
	for _i in 150: await physics_frame
	check(car.speed > 3.0 and car.wheel_spin > 5.0, "anda com as rodas girando (%.1f rad)" % car.wheel_spin)
	print("AURORA_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
