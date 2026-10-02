extends SceneTree
## Inventário finito dos caches reais; preserva os templates após observar seus donos.
const ARSENAL = preload("res://gameplay/ArsenalWeapon3D.gd")
const AIRFRAME = preload("res://gameplay/police_response/air_k9/PoliceHelicopterArt.gd")

var _nodes: Dictionary = {}
var _meshes: Dictionary = {}
var _materials: Dictionary = {}
var _shaders: Dictionary = {}
var _shutdown_refs: Array[WeakRef] = []
var _shutdown_report: Dictionary = {}
var _shutdown_path: String = ""
var _cursor_reference: WeakRef
var _cursor_lifecycle: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var label: String = ""
	var no_save: bool = false
	var print_orphans: bool = false
	var report_directory: String = "res://evidence/teardown-owners"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--owner-label="):
			label = argument.trim_prefix("--owner-label=")
		elif argument.begins_with("--evidence-dir=res://evidence/"):
			report_directory = argument.trim_prefix("--evidence-dir=")
		elif argument == "--no-save":
			no_save = true
		elif argument == "--print-orphans":
			print_orphans = true
	if not no_save or label not in ["before", "after"]:
		push_error("Exige --no-save --owner-label=<before|after>.")
		quit(1)
		return
	_cursor_lifecycle = await _exercise_cursor_lifecycle()
	var baseline: Dictionary = _counts()
	var initially_empty: bool = ARSENAL._templates.is_empty() and AIRFRAME._template == null
	var scratch: Node3D = Node3D.new()
	var helicopter_clone: Node3D = Node3D.new()
	var clone_refs: Array[WeakRef] = []
	for weapon: String in ["pistol", "smg", "m4a1"]:
		ARSENAL.build_cached(scratch, weapon)
	AIRFRAME.warm()
	AIRFRAME.build(helicopter_clone)
	_remember_nodes(scratch, clone_refs)
	_remember_nodes(helicopter_clone, clone_refs)
	var scratch_node_count: int = clone_refs.size()
	var trees: Array[Dictionary] = []
	for weapon: String in ["pistol", "smg", "m4a1"]:
		var template: Node3D = ARSENAL._templates[weapon].node as Node3D
		trees.append(_tree(template, "ArsenalWeapon3D/" + weapon))
	trees.append(_tree(AIRFRAME._template, "PoliceHelicopterArt"))
	var template_refs: Array[WeakRef] = []
	for weapon: String in ["pistol", "smg", "m4a1"]:
		_remember_nodes(ARSENAL._templates[weapon].node as Node, template_refs)
	_remember_nodes(AIRFRAME._template, template_refs)
	# Reaquecer pela API real deve reutilizar os quatro donos, sem limpar mundos.
	var cached_ids: Array[int] = []
	for weapon: String in ["pistol", "smg", "m4a1"]:
		cached_ids.append((ARSENAL._templates[weapon].node as Node).get_instance_id())
	var helicopter_id: int = AIRFRAME._template.get_instance_id()
	var reused: bool = true
	var second_clone: Node3D = Node3D.new()
	for index in range(cached_ids.size()):
		var weapon: String = ["pistol", "smg", "m4a1"][index]
		ARSENAL.build_cached(second_clone, weapon)
		reused = reused and (ARSENAL._templates[weapon].node as Node).get_instance_id() == cached_ids[index]
	AIRFRAME.warm()
	reused = reused and AIRFRAME._template.get_instance_id() == helicopter_id
	_remember_nodes(second_clone, clone_refs)
	second_clone.free()
	scratch.free()
	helicopter_clone.free()
	for frame in range(3):
		await process_frame
	var after: Dictionary = _counts()
	var mesh_node_count: int = 0
	for entry: Dictionary in _nodes.values():
		if entry.class == "MeshInstance3D":
			mesh_node_count += 1
	var clones_alive: int = _alive(clone_refs)
	var templates_alive: int = _alive(template_refs)
	var delta: int = int(after.orphan_nodes) - int(baseline.orphan_nodes)
	var report: Dictionary = {
		"cursor_lifecycle": _cursor_lifecycle, "label": label, "utc": Time.get_datetime_string_from_system(true),
		"pid": OS.get_process_id(), "godot": Engine.get_version_info(),
		"no_save": no_save, "rendering_method": RenderingServer.get_current_rendering_method(),
		"initially_empty": initially_empty, "cache_reused_on_second_warm": reused, "baseline": baseline, "after_warm_free_three_frames": after,
		"orphan_delta": delta, "template_node_count": _nodes.size(),
		"template_mesh_node_count": mesh_node_count, "unique_meshes": _meshes.size(),
		"unique_materials": _materials.size(), "unique_shaders": _shaders.size(),
		"scratch_nodes_before_free": scratch_node_count, "scratch_nodes_alive": clones_alive,
		"template_nodes_alive": templates_alive, "trees": trees,
		"nodes": _nodes.values(), "meshes": _meshes.values(),
		"materials": _materials.values(), "shaders": _shaders.values(),
		"matches_main_reference_60_nodes_52_mesh_nodes": _nodes.size() == 60 and mesh_node_count == 52,
		"fresh_orphan_delta_matches_templates": initially_empty and delta == _nodes.size(),
		"source_sha256": _source_hashes(),
		"scope": "Caches reais aquecidos pelas mesmas APIs de AirK9Director.configure; sem Main, save, física ou medição de FPS. Templates preservados. Contagens iguais são evidência de atribuição, não comparação de IDs entre processos."
	}
	var directory: String = report_directory
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(directory)
	if directory_error != OK:
		push_error("Não foi possível criar diretório: %s" % directory_error)
		quit(1)
		return
	var output: FileAccess = FileAccess.open(directory + "/" + label + ".json", FileAccess.WRITE)
	if output == null:
		push_error("Não foi possível gravar inventário: %s" % FileAccess.get_open_error())
		quit(1)
		return
	output.store_string(JSON.stringify(report, "\t") + "\n")
	output.close()
	if print_orphans:
		Node.print_orphan_nodes()
	var valid: bool = reused and initially_empty and clones_alive == 0 and templates_alive == _nodes.size() and delta == _nodes.size()
	print("%s TEARDOWN_OWNERS nodes=%d mesh_nodes=%d meshes=%d materials=%d orphan_delta=%d" % ["PASS" if valid else "FAIL", _nodes.size(), mesh_node_count, _meshes.size(), _materials.size(), delta])
	if label == "after":
		_shutdown_refs = template_refs
		_shutdown_report = report
		_shutdown_path = directory + "/" + label + ".json"
		# Registrado depois dos factories: observa o fechamento real do root.
		root.tree_exiting.connect(_verify_shutdown, CONNECT_ONE_SHOT)
	quit(0 if valid else 1)

func _tree(node: Node, path: String) -> Dictionary:
	var id: int = node.get_instance_id()
	var script: Script = node.get_script() as Script
	var entry: Dictionary = {"id": id, "class": node.get_class(), "name": str(node.name), "inventory_path": path, "parent_id": node.get_parent().get_instance_id() if node.get_parent() != null else 0, "script": script.resource_path if script != null else ""}
	if node is MeshInstance3D:
		var instance: MeshInstance3D = node as MeshInstance3D
		entry["mesh"] = _resource(instance.mesh, _meshes)
		entry["material_override"] = _material(instance.material_override)
		entry["material_overlay"] = _material(instance.material_overlay)
		var surfaces: Array[Dictionary] = []
		if instance.mesh != null:
			for surface in range(instance.mesh.get_surface_count()):
				surfaces.append({"surface": surface, "mesh_material": _material(instance.mesh.surface_get_material(surface)), "override": _material(instance.get_surface_override_material(surface)), "active": _material(instance.get_active_material(surface))})
		entry["surfaces"] = surfaces
	_nodes[id] = entry
	var children: Array[Dictionary] = []
	for child: Node in node.get_children():
		children.append(_tree(child, path + "/" + str(child.name)))
	return {"id": id, "children": children}

func _resource(resource: Resource, inventory: Dictionary) -> Dictionary:
	if resource == null:
		return {}
	var id: int = resource.get_instance_id()
	var rid: RID = resource.get_rid()
	var entry: Dictionary = {"id": id, "class": resource.get_class(), "path": resource.resource_path, "rid": rid.get_id()}
	inventory[id] = entry
	return entry

func _material(material: Material) -> Dictionary:
	var entry: Dictionary = _resource(material, _materials)
	if material is ShaderMaterial:
		entry["shader"] = _resource((material as ShaderMaterial).shader, _shaders)
	return entry

func _remember_nodes(node: Node, references: Array[WeakRef]) -> void:
	var reference: WeakRef = weakref(node)
	references.append(reference)
	for child: Node in node.get_children():
		_remember_nodes(child, references)

func _alive(references: Array[WeakRef]) -> int:
	var count: int = 0
	for reference: WeakRef in references:
		if reference.get_ref() != null:
			count += 1
	return count

func _counts() -> Dictionary:
	return {"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)), "nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), "orphan_nodes": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), "static_memory_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC))}

func _source_hashes() -> Dictionary:
	var hashes: Dictionary = {}
	for path: String in ["res://runtime/GameInput.gd", "res://gameplay/ArsenalWeapon3D.gd", "res://gameplay/police_response/air_k9/PoliceHelicopterArt.gd", "res://gameplay/police_response/air_k9/PoliceAirK9Director.gd", "res://tests/measure/measure_teardown_owners.gd"]:
		hashes[path] = FileAccess.get_sha256(path)
	return hashes

func _verify_shutdown() -> void:
	# Contraprova opcional: altera somente o diagnóstico no encerramento.
	var clear_cursor: bool = "--clear-cursor-on-shutdown" in OS.get_cmdline_user_args()
	if clear_cursor:
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
		Input.set_custom_mouse_cursor(null, Input.CURSOR_POINTING_HAND)
	var remaining: int = _alive(_shutdown_refs)
	var caches_empty: bool = ARSENAL._templates.is_empty() and AIRFRAME._template == null
	var cursor_alive: bool = _cursor_reference != null and _cursor_reference.get_ref() != null
	var cursor_passed: bool = bool(_cursor_lifecycle.get("passed", false)) and not cursor_alive
	var passed: bool = remaining == 0 and caches_empty and cursor_passed
	_shutdown_report["actual_root_shutdown"] = {"templates_alive": remaining, "cache_entries_cleared": caches_empty, "passed": passed, "diagnostic_only_cursor_reset": clear_cursor, "cursor_resource_alive": cursor_alive, "cursor_lifecycle_passed": cursor_passed}
	var output: FileAccess = FileAccess.open(_shutdown_path, FileAccess.WRITE)
	if output == null:
		push_error("Nao foi possivel gravar verificacao de shutdown.")
		return
	output.store_string(JSON.stringify(_shutdown_report, "\t") + "\n")
	output.close()
	if not passed: push_error("Contrato de descarte de templates/cursor falhou no encerramento real.")
	print("%s TEMPLATE_CACHE_SHUTDOWN alive=%d empty=%s" % ["PASS" if remaining == 0 and caches_empty else "FAIL", remaining, caches_empty])
	print("%s CURSOR_LIFECYCLE_SHUTDOWN alive=%s" % ["PASS" if cursor_passed else "FAIL", cursor_alive])


func _exercise_cursor_lifecycle() -> Dictionary:
	var input_node: Node = root.get_node("GameInput")
	var input_id: int = input_node.get_instance_id()
	var tracking_available: bool = false
	for property: Dictionary in input_node.get_property_list():
		if property.name == "_menu_cursor": tracking_available = true
	if tracking_available:
		var texture: ImageTexture = input_node.get("_menu_cursor") as ImageTexture
		_cursor_reference = weakref(texture) if texture != null else null
	var mouse_mode: int = Input.mouse_mode
	var bindings: Dictionary = _binding_snapshot()
	var phases: Array[Dictionary] = []
	var valid: bool = tracking_available and _cursor_reference != null
	# Exercita o contrato real de troca de cena; não simula mapas/gameplay/FPS.
	for phase: String in ["menu", "world", "menu_return"]:
		var scene: Node = Control.new() if phase != "world" else Node3D.new()
		scene.name = "CursorLifecycle_" + phase
		var packed: PackedScene = PackedScene.new()
		var packed_error: Error = packed.pack(scene)
		scene.free()
		var change_error: Error = change_scene_to_packed(packed) if packed_error == OK else packed_error
		await process_frame
		await process_frame
		var alive: bool = _cursor_reference != null and _cursor_reference.get_ref() != null
		var same_autoload: bool = root.get_node("GameInput").get_instance_id() == input_id
		var input_preserved: bool = Input.mouse_mode == mouse_mode and _binding_snapshot() == bindings
		valid = valid and change_error == OK and alive and same_autoload and input_preserved
		phases.append({"phase": phase, "scene_change_error": change_error, "cursor_resource_alive": alive, "same_autoload": same_autoload, "input_preserved": input_preserved})
	return {"tracking_available": tracking_available, "phases": phases, "passed": valid, "scope": "Real SceneTree menu/world/menu scene swaps with actual GameInput; lightweight scenes, not full production regions."}

func _binding_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for action: String in ["move_up", "fire", "ui_accept"]:
		var events: Array[String] = []
		for event: InputEvent in InputMap.action_get_events(action): events.append(event.as_text())
		snapshot[action] = events
	return snapshot
