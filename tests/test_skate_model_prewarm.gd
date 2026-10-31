extends SceneTree
## Contrato só do candidato, separado da fixture inalterada de antes/depois.
## A identidade do recurso prova a construção aquecida; os tempos são diagnóstico, não FPS.
const MODEL := preload("res://activities/skate/SkateModel.gd")
const PALETTE := [Color("d36c3e"), Color("487d9b"), Color("c3a842"), Color("79559b"), Color("44866a")]
const MATERIAL_FIELDS := ["vertex_color_use_as_albedo", "vertex_color_is_srgb", "albedo_color", "metallic",
	"roughness", "cull_mode", "transparency", "shading_mode", "depth_draw_mode", "texture_filter",
	"no_depth_test", "disable_receive_shadows"]
var host: Node3D
var checks := 0
var failures: Array[String] = []
var collecting := false
var models_added := 0
var collisions_added := 0
var grouped_nodes_added := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func observe_node(node: Node) -> void:
	if not collecting: return
	if node.get_script() == MODEL: models_added += 1
	if node is CollisionObject3D or node is CollisionShape3D: collisions_added += 1
	if not node.get_groups().is_empty(): grouped_nodes_added += 1

func create_model(tint: Color) -> Node3D:
	var model := MODEL.new()
	model.color = tint
	host.add_child(model)
	return model

func material_state(material: Material) -> Dictionary:
	var state := {"class":material.get_class()}
	for field in MATERIAL_FIELDS: state[field] = material.get(field)
	var texture: Texture2D = material.get("albedo_texture")
	if texture != null:
		var image := texture.get_image()
		state["texture_size"] = image.get_size()
		state["texture_data"] = image.get_data()
	else:
		state["texture_size"] = Vector2i.ZERO
		state["texture_data"] = PackedByteArray()
	return state

func describe_part(root_model: Node3D, part: Node3D, result: Array[Dictionary]) -> void:
	var entry := {"path":str(root_model.get_path_to(part)), "class":part.get_class(), "transform":part.transform}
	if part is MeshInstance3D:
		entry["aabb"] = part.mesh.get_aabb()
		entry["material"] = material_state(part.material_override)
		entry["shadow"] = part.cast_shadow
		entry["layers"] = part.layers
		var surfaces: Array[Dictionary] = []
		for index in part.mesh.get_surface_count():
			surfaces.append({"primitive":part.mesh.surface_get_primitive_type(index), "arrays":part.mesh.surface_get_arrays(index)})
		entry["surfaces"] = surfaces
	result.append(entry)
	for child: Node3D in part.get_children(): describe_part(root_model, child, result)

func describe(model: Node3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for child: Node3D in model.get_children(): describe_part(model, child, result)
	return result

func has_cached_node(value: Variant) -> bool:
	if value is Node: return true
	if value is Dictionary:
		for key: Variant in value:
			if has_cached_node(key) or has_cached_node(value[key]): return true
	elif value is Array:
		for child: Variant in value:
			if has_cached_node(child): return true
	return false

func check_cache(label: String) -> void:
	check(MODEL._geometry_cache.size() <= 8, label + " retains at most eight exact colors")
	check(MODEL._cache_order.size() == MODEL._geometry_cache.size(), label + " eviction metadata matches resource entries")
	check(not has_cached_node(MODEL._geometry_cache), label + " cache retains no live nodes")

func check_resources(part: Node3D, entry: Dictionary) -> void:
	if part is MeshInstance3D:
		check(part.mesh == entry.mesh and part.material_override == entry.material, "warm instance reuses cached mesh and material")
	check(part.get_child_count() == entry.children.size(), "warm subtree matches resource descriptors")
	for index in mini(part.get_child_count(), entry.children.size()):
		check_resources(part.get_child(index) as Node3D, entry.children[index])

func collect_scene_nodes(node: Node, inventory: Dictionary) -> void:
	var source: Script = node.get_script()
	inventory[node.get_instance_id()] = {"id":node.get_instance_id(), "path":str(node.get_path()),
		"class":node.get_class(), "script":source.resource_path if source != null else "",
		"groups":node.get_groups(), "queued":node.is_queued_for_deletion()}
	for child: Node in node.get_children(true): collect_scene_nodes(child, inventory)

func scene_inventory() -> Dictionary:
	var inventory := {}
	collect_scene_nodes(root, inventory)
	return inventory

func print_scene_delta(label: String, before: Dictionary, reported_before: int) -> void:
	var after := scene_inventory()
	var added: Array[Dictionary] = []
	var removed: Array[Dictionary] = []
	var changed: Array[Dictionary] = []
	for identity: int in after:
		if not before.has(identity): added.append(after[identity])
		elif after[identity] != before[identity]: changed.append({"before":before[identity], "after":after[identity]})
	for identity: int in before:
		if not after.has(identity): removed.append(before[identity])
	print("SKATE_PREWARM_SCENE ", JSON.stringify({"stage":label, "reported_before":reported_before,
		"reported_after":get_node_count(), "enumerated_before":before.size(), "enumerated_after":after.size(),
		"host_children":host.get_child_count(), "added":added, "removed":removed, "changed":changed}))

func run() -> void:
	# O StallLog enfileira a própria remoção durante o _ready do autoload quando o log está desligado.
	# A transição confirmada de 10 -> 9 nós de cena pertence ao início, então termina a
	# limpeza adiada do autoload antes de criar a fixture e a linha de base estrita dela.
	await process_frame
	await process_frame
	host = Node3D.new()
	root.add_child(host)
	node_added.connect(observe_node)
	var reference := {}
	for tint: Color in PALETTE:
		var model := create_model(tint)
		reference[tint] = describe(model)
		model.free()
	# Força falhas genuínas antes do pré-aquecimento e impõe o limite a cada inserção.
	for index in 12:
		var custom := create_model(Color(float(index + 1) / 19.0, .231, .517, 1.0))
		custom.free()
		check_cache("custom color %d" % index)
	var missing := 0
	for tint: Color in PALETTE:
		if not MODEL._geometry_cache.has(tint): missing += 1
	check(missing == 5, "fixture reaches a cold palette after color churn")
	var nodes_before := get_node_count()
	var inventory_before := scene_inventory()
	collecting = true
	var began := Time.get_ticks_usec()
	await MODEL.prewarm_colors(host)
	var prewarm_usec := Time.get_ticks_usec() - began
	collecting = false
	check(models_added == missing, "prewarm constructs each missing palette color once")
	check(collisions_added == 0 and grouped_nodes_added == 0, "prewarm creates no colliders or grouped gameplay nodes")
	print_scene_delta("after_prewarm", inventory_before, nodes_before)
	check(host.get_child_count() == 0 and get_node_count() == nodes_before, "prewarm leaves no residual scene nodes")
	check_cache("after prewarm")
	var timings: Array[Dictionary] = []
	for tint: Color in PALETTE:
		check(MODEL._geometry_cache.has(tint), "prewarm retains palette color " + tint.to_html())
		began = Time.get_ticks_usec()
		var model := create_model(tint)
		var creation_usec := Time.get_ticks_usec() - began
		check(describe(model) == reference[tint], "post-prewarm exact geometry/material " + tint.to_html())
		var entries: Array = MODEL._geometry_cache[tint]
		check(model.get_child_count() == entries.size(), "post-prewarm top-level hierarchy")
		for index in mini(model.get_child_count(), entries.size()):
			check_resources(model.get_child(index) as Node3D, entries[index])
		timings.append({"color":tint.to_html(), "creation_usec":creation_usec})
		model.free()
	var models_before_reentry := models_added
	collecting = true
	began = Time.get_ticks_usec()
	await MODEL.prewarm_colors(host)
	var reentry_usec := Time.get_ticks_usec() - began
	collecting = false
	check(models_added == models_before_reentry, "prewarm reentry creates no new models")
	check(collisions_added == 0 and grouped_nodes_added == 0, "reentry creates no colliders or grouped gameplay nodes")
	print_scene_delta("after_reentry", inventory_before, nodes_before)
	check(host.get_child_count() == 0 and get_node_count() == nodes_before, "reentry leaves no residual scene nodes")
	check_cache("after reentry")
	print("SKATE_PREWARM_CPU ", JSON.stringify({"prewarm_wall_usec":prewarm_usec, "reentry_usec":reentry_usec, "post_prewarm":timings, "scope":"Prewarm includes five awaited process frames; construction times measure CPU only, not gameplay FPS or GPU completion."}))
	host.free()
	print("SKATE_PREWARM checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
