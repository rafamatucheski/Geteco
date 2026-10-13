extends SceneTree
## Contrato P6 e única medição permitida: montagem headless, 20 pares por variação.
const FACTORY := preload("res://world/urban_detail/UrbanBuildingFactory.gd")
const BAKE := preload("res://tools/building_bake/bake_commercial.gd")
const CATALOG := preload("res://assets/buildings/baked/BuildingBakeCatalog.gd")
const DRESSING := preload("res://world/city_look/CityChunkDressing.gd")
const ACCESS := preload("res://world/places/harbor_buildings/HarborBuildingExteriorAccess.gd")
const PLACES := preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd")
var failures: Array[String] = []
var checks := 0
var results: Array[Dictionary] = []
var _material_keys := {}

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func mount(record: Dictionary, baked: bool) -> UrbanBuildingBase:
	FACTORY.baked_enabled = baked
	var building := FACTORY.build_building(record) as UrbanBuildingBase
	root.add_child(building)
	return building

func material_key(material: Material) -> String:
	if not material is StandardMaterial3D: return str(material)
	if _material_keys.has(material.get_instance_id()): return _material_keys[material.get_instance_id()]
	var texture: Texture2D = material.albedo_texture
	var signature := var_to_str([material.albedo_color, material.roughness, material.metallic,
		material.transparency, material.emission_enabled, material.emission, material.emission_energy_multiplier,
		material.uv1_scale, material.uv1_triplanar, material.uv1_world_triplanar,
		texture.get_image().get_data().hex_encode().sha256_text() if texture != null else ""])
	_material_keys[material.get_instance_id()] = signature
	return signature

func geometry(building: UrbanBuildingBase) -> Dictionary:
	var result := {}
	for node: MeshInstance3D in building.find_children("*", "MeshInstance3D", true, false):
		if node.get_meta("baked_lod", false): continue
		for surface in node.mesh.get_surface_count():
			var arrays := node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var frame := node.transform
			var ancestor := node.get_parent() as Node3D
			while ancestor != building:
				frame = ancestor.transform * frame
				ancestor = ancestor.get_parent() as Node3D
			var mat := material_key(node.get_active_material(surface))
			for cursor in (indices.size() if not indices.is_empty() else vertices.size()):
				var index: int = indices[cursor] if not indices.is_empty() else cursor
				var point := frame * vertices[index]
				var normal := (frame.basis.inverse().transposed() * normals[index]).normalized()
				var signature := "%s|%s|%s|%d" % [mat, Vector3i((normal * 1000).round()), Vector2i((uvs[index] * 1000).round()), node.cast_shadow]
				if not result.has(signature): result[signature] = []
				result[signature].append(point)
	return result

func same_geometry(before: Dictionary, after: Dictionary) -> bool:
	if before.size() != after.size(): return false
	var maximum_error := 0.0
	for signature in before:
		if not after.has(signature) or before[signature].size() != after[signature].size(): return false
		var buckets := {}
		for point: Vector3 in before[signature]:
			var cell := Vector3i((point * 1000).floor())
			if not buckets.has(cell): buckets[cell] = []
			buckets[cell].append(point)
		for point: Vector3 in after[signature]:
			var cell := Vector3i((point * 1000).floor())
			var matched := false
			for x in range(-1, 2):
				for y in range(-1, 2):
					for z in range(-1, 2):
						if matched: continue
						var nearby := cell + Vector3i(x, y, z)
						if not buckets.has(nearby): continue
						var candidates: Array = buckets[nearby]
						for index in candidates.size():
							var error := point.distance_to(candidates[index])
							# Mesmo limite de 0,1 mm do contrato de fusão existente.
							if error <= .0001:
								maximum_error = maxf(maximum_error, error)
								candidates.remove_at(index)
								matched = true
								break
			if not matched:
				print("P6_VERTICE_SEM_PAR ", point, " material/normal/uv=", signature)
				return false
	print("P6_ERRO_MAXIMO_GEOMETRIA metros=", maximum_error)
	return true

func boxes(building: UrbanBuildingBase) -> Array[String]:
	var result: Array[String] = []
	for shape: CollisionShape3D in building.find_children("*", "CollisionShape3D", true, false):
		var frame := building.global_transform.affine_inverse() * shape.global_transform
		result.append(var_to_str([frame, shape.shape.size, shape.get_parent().collision_layer]))
	result.sort()
	return result

func live(building: UrbanBuildingBase) -> Array[String]:
	var result: Array[String] = []
	for node in building.visuals_root.find_children("*", "Node3D", true, false):
		var label := str(node.name).to_lower()
		var glass: bool = node is MeshInstance3D and node.material_override in [UrbanMaterials.glass_window(), UrbanMaterials.glass_window_lit(true), UrbanMaterials.glass_window_lit(false), UrbanMaterials.glass_display()]
		if glass or label.contains("door") or label.contains("handle") or node is Label3D:
			result.append(var_to_str(["glass" if glass else str(node.name), node.transform, node.text if node is Label3D else ""]))
	result.sort()
	return result

func median(samples: Array[float]) -> float:
	samples.sort()
	return (samples[9] + samples[10]) * 0.5

func verify_access(building: UrbanBuildingBase, data: Dictionary) -> void:
	var definition := PLACES.for_source(str(data.id))
	if definition.is_empty() or not definition.size.is_equal_approx(data.size): return
	building.rotation.y = float(definition.exterior_rotation)
	var access := ACCESS.install(building, str(data.id))
	await physics_frame
	access.set_open_amount(1.0)
	await physics_frame
	await physics_frame
	check(access.access_ready, str(data.id) + " acesso preparado")
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.30
	capsule.height = 1.78
	query.shape = capsule
	query.collision_mask = 1
	query.transform = Transform3D(Basis.IDENTITY, access.to_global(definition.entrance_local + Vector3(0, .96, 1.0)))
	query.motion = access.global_basis * Vector3(0, 0, -2.5)
	var sweep := building.get_world_3d().direct_space_state.cast_motion(query)
	check(sweep[0] > .995, str(data.id) + " cápsula atravessa porta aberta")
	query.motion = Vector3.ZERO
	query.transform.origin = access.to_global(Vector3(0, .96, 0))
	check(building.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(), str(data.id) + " interior oco")
	access.set_floor_view(0, float(definition.storey_height), false)
	access.set_floor_view(int(definition.floor_count), float(definition.storey_height), true)
	access.restore_exterior()
	await physics_frame
	await physics_frame
	check(not access.access_ready, str(data.id) + " saída restaura fachada")
	query.transform.origin = building.to_global(Vector3(0, 1.0, 0))
	check(not building.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(), str(data.id) + " corpo fechado volta a bloquear")

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or DisplayServer.get_name() != "headless":
		push_error("Execute headless com --no-save; o tempo de montagem é somente indicativo.")
		quit(2)
		return
	var enabled_before := FACTORY.baked_enabled
	for record in BAKE.records():
		var only := ""
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--only="): only = arg.trim_prefix("--only=")
		if not only.is_empty() and str(record.id) != only: continue
		var original := mount(record, false)
		var baked := mount(record, true)
		var data: Dictionary = baked.get_meta("_urban_data")
		var id := str(data.id)
		check(baked.get_meta("baked_commercial", false), id + " usa arquivo assado")
		var original_geometry := geometry(original)
		var baked_geometry := geometry(baked)
		check(same_geometry(original_geometry, baked_geometry), id + " preserva vértices, normais, UV e materiais perto")
		check(boxes(original) == boxes(baked), id + " preserva caixas físicas exatas")
		check(live(original) == live(baked), id + " preserva portas, vidros e letreiros")
		check(DRESSING._roof_slabs(original) == DRESSING._roof_slabs(baked), id + " preserva leitura da laje")
		var roof: float = DRESSING._roof_box(original).end.y + .012
		check(DRESSING._roof_obstacles(original, roof) == DRESSING._roof_obstacles(baked, roof), id + " preserva obstáculos do telhado")
		check(DRESSING.LIFE._read_facade(original) == DRESSING.LIFE._read_facade(baked), id + " preserva fachada viva")
		var lod := baked.visuals_root.get_node("BakedFacadeLOD") as MeshInstance3D
		check(lod.visibility_range_begin == 50.0 and lod.visibility_range_begin_margin == 2.0, id + " LOD aos 50 m com margem")
		for mesh: MeshInstance3D in baked.visuals_root.find_children("*", "MeshInstance3D", true, false):
			if not mesh.get_meta("baked_detail", false): continue
			var detail_enabled: bool = CATALOG.detail_enabled()
			check(mesh.cast_shadow == (GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if detail_enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_ON), id + " sombra responde ao interruptor P5")
			check(mesh.visibility_range_end <= 50.0 and mesh.visibility_range_end >= 40.0, id + " detalhe respeita limites P5/P6")
		var before := BAKE.counts(original)
		var after := BAKE.counts(baked)
		check(after.meshes < before.meshes and after.bodies == 1 and after.boxes == 2, id + " reduz malhas e corpos sem eliminar sólidos")
		original.free()
		await verify_access(baked, data)
		baked.free()
		await physics_frame
		if "--diagnostic" in OS.get_cmdline_user_args(): continue
		var baseline: Array[float] = []
		var optimized: Array[float] = []
		# Caches já aquecidos. Sem medir frames, espera do servidor ou custo de descarte.
		for iteration in 20:
			for use_bake in [false, true]:
				var started := Time.get_ticks_usec()
				var instance := mount(record, use_bake)
				var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
				if use_bake: optimized.append(elapsed)
				else: baseline.append(elapsed)
				instance.free()
		results.append({"id": id, "key": CATALOG.key(data), "before": before, "after": after,
			"assembly_median_ms_before": median(baseline), "assembly_median_ms_after": median(optimized), "iterations": 20})
		print("P6_CONTAGEM_MONTAGEM_INDICATIVA ", JSON.stringify(results.back()))
		var changed := data.duplicate(true)
		changed.size += Vector2.ONE
		check(CATALOG.create(changed) == null, id + " variação ausente usa fallback")
	FACTORY.baked_enabled = enabled_before
	var destination := "res://tools/building_bake/validation.json"
	if "--diagnostic" in OS.get_cmdline_user_args(): destination = "res://tools/building_bake/validation_p5_off.json" if not CATALOG.detail_enabled() else "res://tools/building_bake/diagnostic.json"
	var file := FileAccess.open(destination, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "results": results,
		"detail_range_enabled": CATALOG.detail_enabled(),
		"note": "Montagem headless indicativa, caches aquecidos, concorrência de outras sessões; não mede FPS nem frame time."}, "\t"))
	file.close()
	print("P6_CONTRATO verificações=", checks, " falhas=", failures.size())
	quit(0 if failures.is_empty() else 1)
