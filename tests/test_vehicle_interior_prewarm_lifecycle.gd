extends SceneTree
## Contrato funcional de ciclo de vida com veículos reais num processo novo.
## Nunca limpa _warmed, _specs, _meshes nem os caches de material. Não é teste de FPS.
const VEHICLE := preload("res://scripts/Vehicle.gd")
const INTERIOR := preload("res://gameplay/VehicleInterior.gd")
var host: Node3D
var checks := 0
var failures: Array[String] = []
var invalid: Array[String] = []
var attempts: Dictionary = {}
var warm_added: Dictionary = {}
var cancellation_id := 0
var cancellation_scheduled := false
var cancellation_observed := false
var output := "user://vehicle-interior-prewarm-lifecycle.json"

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
	print(("PASS " if ok else "FAIL ") + message)

func frames(count := 4) -> void:
	for index in count: await process_frame

func shared_material_contract() -> void:
	# A preparação de shaders não pode afirmar a conclusão do trabalho preparado de nenhuma família.
	var caches_before := [INTERIOR._warmed.duplicate(), INTERIOR._warming.duplicate(), INTERIOR._specs.duplicate(), INTERIOR._meshes.duplicate()]
	var original_enabled: bool = INTERIOR.enabled
	var original_material: StandardMaterial3D = INTERIOR._material
	var original_alpha: StandardMaterial3D = INTERIOR._alpha_material
	INTERIOR.enabled = false
	INTERIOR.prepare_shared_materials()
	check(not INTERIOR.enabled and INTERIOR._material == original_material and INTERIOR._alpha_material == original_alpha, "disabled material preparation creates no resources and preserves the feature flag")
	INTERIOR.enabled = original_enabled
	check(original_enabled, "fixture runs with seated interiors enabled")
	if not original_enabled: return
	INTERIOR.prepare_shared_materials()
	var opaque: StandardMaterial3D = INTERIOR._material
	var alpha: StandardMaterial3D = INTERIOR._alpha_material
	INTERIOR.prepare_shared_materials()
	check(opaque != null and alpha != null and opaque != alpha and INTERIOR._material == opaque and INTERIOR._alpha_material == alpha, "repeated preparation reuses two distinct shared material identities")
	if opaque != null and alpha != null:
		check(opaque.get_rid().is_valid() and alpha.get_rid().is_valid(), "both shared materials have rendering resources")
		check(opaque.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and alpha.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "opaque cabin and translucent roof retain their distinct transparency")
		check(opaque.vertex_color_use_as_albedo and alpha.vertex_color_use_as_albedo and opaque.vertex_color_is_srgb and alpha.vertex_color_is_srgb, "both materials preserve the authored vertex colors")
	check(caches_before == [INTERIOR._warmed, INTERIOR._warming, INTERIOR._specs, INTERIOR._meshes], "shared shader preparation neither builds nor prematurely marks a vehicle family")
	check(INTERIOR.enabled == original_enabled and host.get_child_count() == 0, "material preparation preserves the feature flag and creates no scene nodes")

func shared_material_consumers() -> void:
	var opaque_matches := true
	var alpha_matches := true
	var alpha_surfaces := 0
	for value: Variant in INTERIOR._meshes.values():
		var mesh := value as ArrayMesh
		opaque_matches = opaque_matches and mesh != null and mesh.get_surface_count() > 0 and mesh.surface_get_material(0) == INTERIOR._material
		if mesh != null and mesh.get_surface_count() > 1:
			alpha_surfaces += 1
			alpha_matches = alpha_matches and mesh.surface_get_material(1) == INTERIOR._alpha_material
	check(not INTERIOR._meshes.is_empty() and opaque_matches, "actual prepared vehicle meshes consume the shared opaque material")
	check(alpha_surfaces > 0 and alpha_matches, "actual prepared translucent roofs consume the shared alpha material")

func new_vehicle(id: String, title: String) -> Node3D:
	var car := VEHICLE.new()
	car.archetype = id
	car.name = title
	host.add_child(car)
	car.set_physics_process(false)
	return car

func fresh_family(id: String) -> bool:
	var cold := not INTERIOR._warmed.has(id) and not INTERIOR._specs.has(id) and not INTERIOR._meshes.has(id)
	if not cold: invalid.append("family_not_naturally_cold:" + id)
	check(cold, "fresh process provides naturally cold family " + id)
	return cold

func attempt(car: Node3D, title: String) -> void:
	var id := str(car.get("archetype"))
	var started := Time.get_ticks_usec()
	attempts[title] = {"id": id, "vehicle_id": str(car.get_instance_id()), "done": false, "started_usec": started}
	await INTERIOR.prewarm(car)
	attempts[title]["done"] = true
	attempts[title]["ended_usec"] = Time.get_ticks_usec()
	attempts[title]["mesh_cached"] = INTERIOR._meshes.has(id)
	attempts[title]["completed_marker"] = INTERIOR._warmed.has(id)

func remove_vehicle(car: Node3D) -> void:
	if not is_instance_valid(car): return
	if car.get_parent() != null: car.get_parent().remove_child(car)
	car.queue_free()

func on_node_added(node: Node) -> void:
	if not node is MeshInstance3D or node.name != "WarmUp": return
	var visual := node.get_parent()
	var car := visual.get_parent() if visual != null else null
	if car == null or not car.has_method("finish_doors"): return
	var id := car.get_instance_id()
	warm_added[id] = int(warm_added.get(id, 0)) + 1
	if id == cancellation_id and not cancellation_scheduled:
		cancellation_scheduled = true
		# Adia a remoção até add_child terminar. Isto ainda é antes do próximo
		# process_frame, enquanto o pré-aquecimento real de material está suspenso.
		cancel_during_materials.call_deferred(car)

func cancel_during_materials(car: Node3D) -> void:
	cancellation_observed = true
	remove_vehicle(car)

func verify_retry(car: Node3D, title: String) -> void:
	var id := str(car.get("archetype"))
	await attempt(car, title)
	await frames()
	check(INTERIOR._warmed.has(id), title + ": completed marker exists after successful retry")
	check(INTERIOR._meshes.has(id), title + ": interior mesh is actually prepared")
	check(int(warm_added.get(car.get_instance_id(), 0)) > 0, title + ": retry really mounted its glass warmup meshes")
	check(car.find_children("WarmUp", "MeshInstance3D", true, false).is_empty(), title + ": temporary meshes leave no residue")

func cancellation_before_first_frame() -> void:
	const ID := "sport_coupe"
	if not fresh_family(ID): return
	var owner := new_vehicle(ID, "CancelledBeforeFirstFrame")
	attempt(owner, "before_first_owner")
	check(not bool(attempts.before_first_owner.done), "owner is suspended in its real first await")
	check(INTERIOR._specs.has(ID) and not INTERIOR._meshes.has(ID), "first stage has spec but has not built the interior mesh")
	var dead_id := owner.get_instance_id()
	remove_vehicle(owner)
	await frames()
	check(not is_instance_id_valid(dead_id), "cancelled owner really left the tree and was freed")
	check(not INTERIOR._warmed.has(ID), "cancelled work is not falsely marked complete")
	check(INTERIOR._specs.has(ID), "valid partial spec survives cancellation")
	var retry := new_vehicle(ID, "LaterRetry")
	await verify_retry(retry, "later_retry")
	remove_vehicle(retry)
	await frames()

func takeover_before_old_continuation() -> void:
	const ID := "union_sedan"
	if not fresh_family(ID): return
	var owner := new_vehicle(ID, "OldToken")
	var retry := new_vehicle(ID, "NewToken")
	attempt(owner, "old_token_owner")
	remove_vehicle(owner)
	# A corrotina antiga não retomou. Um pedido novo pode tomar posse, e
	# a continuação antiga não pode apagar a conclusão desse pedido mais novo.
	attempt(retry, "new_token_retry")
	await frames(12)
	check(bool(attempts.new_token_retry.done), "takeover finishes within a finite frame window")
	check(INTERIOR._warmed.has(ID) and INTERIOR._meshes.has(ID), "old continuation cannot poison the successful takeover")
	check(int(warm_added.get(retry.get_instance_id(), 0)) > 0, "takeover actually prepares glass on the replacement")
	check(retry.find_children("WarmUp", "MeshInstance3D", true, false).is_empty(), "takeover temporary meshes are cleaned")
	remove_vehicle(retry)
	await frames()

func cancellation_during_material_frames() -> void:
	const ID := "taxi_yellow"
	if not fresh_family(ID): return
	var owner := new_vehicle(ID, "CancelledDuringMaterials")
	cancellation_id = owner.get_instance_id()
	attempt(owner, "material_owner")
	await frames(8)
	check(cancellation_observed and int(warm_added.get(cancellation_id, 0)) > 0, "owner is cancelled after real WarmUp construction")
	check(not is_instance_id_valid(cancellation_id), "material-stage owner was actually freed")
	check(INTERIOR._meshes.has(ID), "valid partial interior mesh survives material-stage cancellation")
	check(not INTERIOR._warmed.has(ID), "unfinished material frames are not marked complete")
	var retry := new_vehicle(ID, "MaterialRetry")
	await verify_retry(retry, "material_retry")
	remove_vehicle(retry)
	cancellation_id = 0
	await frames()

func duplicate_active_request() -> void:
	const ID := "metro_hatch"
	if not fresh_family(ID): return
	var owner := new_vehicle(ID, "ActiveOwner")
	var duplicate := new_vehicle(ID, "EarlyDuplicate")
	attempt(owner, "active_owner")
	attempt(duplicate, "active_duplicate")
	check(bool(attempts.active_duplicate.done), "duplicate request returns immediately while owner is active")
	await frames(12)
	check(bool(attempts.active_owner.done) and INTERIOR._warmed.has(ID) and INTERIOR._meshes.has(ID), "normal owner completes its existing staged work")
	check(int(warm_added.get(owner.get_instance_id(), 0)) > 0, "active owner really prepared its glass")
	check(int(warm_added.get(duplicate.get_instance_id(), 0)) == 0, "duplicate does not queue or create another warmup")
	check(host.find_children("WarmUp", "MeshInstance3D", true, false).is_empty(), "successful prewarm leaves no temporary nodes")
	remove_vehicle(owner)
	remove_vehicle(duplicate)
	await frames()

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	if "--no-save" not in OS.get_cmdline_user_args() or not ClassDB.class_exists(&"CSharpScript") or not OS.get_environment("HARBOR_NO_CSHARP").is_empty():
		push_error("Lifecycle fixture requires --no-save and the compiled .NET project")
		quit(2)
		return
	if FileAccess.file_exists(output):
		push_error("Lifecycle fixture refuses to overwrite evidence")
		quit(2)
		return
	create_timer(30.0).timeout.connect(func(): push_error("INTERIOR_LIFECYCLE_TIMEOUT"); quit(2))
	host = Node3D.new()
	host.name = "InteriorLifecycleFixture"
	root.add_child(host)
	node_added.connect(on_node_added)
	shared_material_contract()
	await cancellation_before_first_frame()
	await takeover_before_old_continuation()
	await cancellation_during_material_frames()
	await duplicate_active_request()
	shared_material_consumers()
	check(host.get_child_count() == 0, "all fixture vehicles were removed without residual host children")
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Could not write lifecycle evidence")
		quit(2)
		return
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "invalid": invalid, "attempts": attempts,
		"warmup_nodes_by_vehicle": warm_added, "scope": "Actual Vehicle nodes and normal process_frame awaits in a fresh no-save .NET process. No cache or completed flag is cleared. First-frame, material-frame and old-token cancellation plus duplicate-active coverage. No FPS claim."}, "\t"))
	print("INTERIOR_LIFECYCLE checks=", checks, " failures=", failures.size(), " invalid=", invalid)
	quit(0 if failures.is_empty() and invalid.is_empty() else 1)
