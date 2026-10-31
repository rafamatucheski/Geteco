extends SceneTree
## Geometry/isolation contract only; rendered A/B determines performance.
## Frozen original model/body independently recreate all four liveries.
const COACH := preload("res://runtime/terminal/TerminalCoach.gd")
const ORIGINAL := preload("res://tests/fixtures/TerminalCoachBodyOriginal.gd")
const CRUSH := preload("res://gameplay/street_physics/HeavyVehicleCrush.gd")
const WORK := preload("res://runtime/StallWorkTrace.gd")

var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TERMINAL_BODY_CACHE: "+label)

func batches(model: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child in model.get_children():
		if child is MeshInstance3D and child.mesh is ArrayMesh: result.append(child)
	return result

func material_signature(material: Material) -> Array:
	if not material is StandardMaterial3D: return []
	return [material.albedo_color,material.roughness,material.metallic,
		material.emission_enabled,material.emission,material.emission_energy_multiplier]

func same_geometry(a: Array, b: Array) -> bool:
	if a.size() != b.size(): return false
	for index in a.size():
		if a[index].transform != b[index].transform: return false
		var first: ArrayMesh = a[index].mesh
		var second: ArrayMesh = b[index].mesh
		if first.get_surface_count() != second.get_surface_count() or first.get_aabb() != second.get_aabb(): return false
		for surface in first.get_surface_count():
			if first.surface_get_primitive_type(surface) != second.surface_get_primitive_type(surface): return false
			if first.surface_get_format(surface) != second.surface_get_format(surface): return false
			if first.surface_get_arrays(surface) != second.surface_get_arrays(surface): return false
	return true

func same_materials(a: Array, b: Array) -> bool:
	if a.size() != b.size(): return false
	for index in a.size():
		if material_signature(a[index].material_override) != material_signature(b[index].material_override): return false
		# As sobrescritas de paleta/dano pertencem à instância, nunca à malha compartilhada.
		for surface in a[index].mesh.get_surface_count():
			if a[index].mesh.surface_get_material(surface) != null: return false
	return true

func moving_details(model: Node3D) -> Array:
	var result: Array = []
	for child in model.get_children():
		if child is Label3D:
			result.append(["label",child.text,child.font_size,child.pixel_size,child.modulate,child.outline_size,child.transform])
		elif child is MeshInstance3D and child.mesh is CylinderMesh:
			var cylinder: CylinderMesh = child.mesh
			result.append(["wheel",cylinder.top_radius,cylinder.bottom_radius,cylinder.height,cylinder.radial_segments,child.transform,material_signature(child.material_override)])
	return result

func same_collision(a, b) -> bool:
	return a.shape.shape.size == b.shape.shape.size and a.shape.transform == b.shape.transform \
		and a.collision_layer == b.collision_layer and a.collision_mask == b.collision_mask \
		and a.clearance_query.shape.size == b.clearance_query.shape.size \
		and a.clearance_query.collision_mask == b.clearance_query.collision_mask \
		and a.clearance_query.exclude == [a.get_rid()] and b.clearance_query.exclude == [b.get_rid()] \
		and a.rotation_shape.size == b.rotation_shape.size and a.sensor_shape.size == b.sensor_shape.size \
		and a.half_width == b.half_width and a.half_length == b.half_length and a.body_height == b.body_height

func run() -> void:
	for frame in 2: await process_frame
	# Este processo independente é dono do cache de teste. A produção nunca o limpa.
	COACH._body_batches.clear()
	var stage := Node3D.new()
	root.add_child(stage)
	var originals: Array = []
	var candidates: Array = []
	var canonical: Array = []
	WORK.enabled = true
	WORK.take()
	for platform in 4:
		var candidate = COACH.new()
		candidate.platform = platform
		candidate.timer = 1+platform*11
		stage.add_child(candidate)
		candidates.append(candidate)
		var original = ORIGINAL.new()
		original.platform = platform
		original.timer = 1+platform*11
		stage.add_child(original)
		originals.append(original)
		var body := batches(candidate.model)
		var reference := batches(original.model)
		if platform == 0: canonical = body
		check(body.size()==7 and candidate.model.get_child_count()==24 and candidate.get_child_count()==original.get_child_count(),"Platform %d has exactly seven final batches, twelve wheels and five labels" % platform)
		check(same_geometry(body,reference),"Platform %d preserves every vertex, normal, tangent, UV, index, format and AABB" % platform)
		check(same_materials(body,reference),"Platform %d keeps original per-instance livery/material parameters" % platform)
		check(moving_details(candidate.model)==moving_details(original.model) and candidate.model.transform==original.model.transform,"Platform %d preserves independent labels/wheels and authored transform" % platform)
		check(same_collision(candidate,original) and candidate.shape.shape != original.shape.shape,"Platform %d keeps independent original hull/query/sensor contracts" % platform)
		check(candidate.timer==original.timer and candidate.state==original.state and candidate.passengers.is_empty() and candidate.health==original.health and candidate.path==null,"Platform %d changes no timer, service state, health, passenger or path" % platform)
		var shared := true
		for index in body.size():
			shared = shared and body[index].mesh==canonical[index].mesh
			if platform != 0: shared = shared and body[index].material_override!=canonical[index].material_override
		check(shared,"Platform %d shares only immutable geometry; every material belongs to its coach" % platform)
		check(candidate.coach_wheels.size()==12 and candidate.door_leaves.size()==2,"Platform %d preserves both moving doors and all independently animated wheels" % platform)
	var reuse_count := 0
	for event in WORK.take():
		if event.get("label","")=="terminal.coach.batch.reuse": reuse_count += 1
	check(reuse_count==3 and COACH._body_batches.size()==7,"First admission builds one canonical body; exactly the next three reuse it")
	var before_arrays: Array = []
	for batch in canonical: before_arrays.append(batch.mesh.surface_get_arrays(0))
	var first = candidates[0]
	var second = candidates[1]
	var second_door_positions: Array = []
	for door in second.door_leaves: second_door_positions.append(door.position)
	first.set_doors(1)
	var independent_doors := true
	for index in second.door_leaves.size(): independent_doors = independent_doors and second.door_leaves[index].position==second_door_positions[index]
	check(independent_doors,"Opening one coach door leaves the other coach unchanged")
	var second_wheel: Transform3D = second.coach_wheels[0].transform
	first.coach_wheels[0].rotate_object_local(Vector3.UP,.25)
	check(second.coach_wheels[0].transform==second_wheel and first.coach_wheels[0].mesh!=second.coach_wheels[0].mesh,"Wheel pose and cylinder resources remain independent")
	var original_color: Color = canonical[2].material_override.albedo_color
	var second_color: Color = batches(second.model)[2].material_override.albedo_color
	canonical[2].material_override.albedo_color = Color.MAGENTA
	check(batches(second.model)[2].material_override.albedo_color==second_color,"Changing one livery material never recolors another coach")
	canonical[2].material_override.albedo_color = original_color
	first.receive_damage(37)
	check(first.health==263 and second.health==300,"Damage preserves independent coach health")
	var second_scale: Vector3 = second.model.scale
	var second_shape: Shape3D = second.shape.shape
	CRUSH.apply_saved(first,.25)
	check(first.shape.shape is ConvexPolygonShape3D and second.shape.shape==second_shape and second.model.scale==second_scale,"Saved crush changes only the target hull and visual instance transform")
	CRUSH.restore(first)
	check(first.shape.shape is BoxShape3D and first.model.scale==originals[0].model.scale,"Crush restoration keeps original collision and visual scale")
	var untouched := true
	for index in canonical.size(): untouched = untouched and canonical[index].mesh.surface_get_arrays(0)==before_arrays[index]
	check(untouched,"Door/wheel/material/damage/crush lifecycle never mutates cached body arrays")
	var canonical_resources: Array = []
	for batch in canonical: canonical_resources.append(batch.mesh)
	for candidate in candidates: candidate.free()
	var replacement = COACH.new()
	replacement.platform = 0
	stage.add_child(replacement)
	var preserved := batches(replacement.model)
	var resources_survive := true
	for index in preserved.size(): resources_survive = resources_survive and preserved[index].mesh==canonical_resources[index]
	check(preserved.size()==7 and resources_survive and same_geometry(preserved,batches(originals[0].model)),"Re-admission after all coaches free keeps bounded immutable geometry and identical appearance")
	stage.free()
	WORK.enabled = false
	WORK.take()
	print("TERMINAL_BODY_CACHE ",checks," checks ",failures," failures")
	quit(1 if failures else 0)
