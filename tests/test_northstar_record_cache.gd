extends SceneTree
## Real Northstar builder, physical gangway, cache detach/reparent and destruction.
## Does not prove FPS, all ship routes, occlusion or exported resources.
const REGION := preload("res://world/regions/NativeRegion.gd")
const HOIST := preload("res://world/regions/NorthstarCargoHoist3D.gd")
var failures := 0
var checks := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("NORTHSTAR_CACHE ", "PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1
		push_error(label)

func gangway_hit(owner: Node3D) -> Dictionary:
	var point := Vector3(204.625, 0.0, 110.125)
	var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP, point - Vector3.UP, 1)
	return owner.get_world_3d().direct_space_state.intersect_ray(ray)

func hoist_parts(nodes: Array) -> int:
	var result := 0
	for node in nodes:
		if node is Node3D and node.get_script() == HOIST: result += node.get_child_count()
	return result

func _run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("NORTHSTAR_CACHE requires --no-save")
		quit(2)
		return
	var scene := Node3D.new()
	root.add_child(scene)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(230,25,140)
	camera.look_at(Vector3(220,2,105))
	camera.current = true
	var light := DirectionalLight3D.new()
	scene.add_child(light)
	light.rotation_degrees = Vector3(-50,-25,0)
	var owner := REGION.new()
	owner.region_id = "harbor"
	owner.initial_prewarm_only = true
	# Prepare only this actual source payload; avoid building unrelated world records.
	owner.source_data = JSON.parse_string(FileAccess.get_file_as_string(REGION.DATA_PATH))
	owner.data_prepared = true
	scene.add_child(owner)
	owner.set_process(false)
	var chunk := Node3D.new()
	owner.add_child(chunk)
	var record := {"kind":"ship","position":Vector3.ZERO}
	owner._build_record_cached(chunk, record)
	var key: String = owner._record_cache_key(record)
	check(owner._record_cache.has(key), "real ship record participates in existing region cache")
	if not owner._record_cache.has(key):
		scene.free()
		quit(1)
		return
	var originals: Array = owner._record_cache[key].duplicate()
	var witnesses: Array[WeakRef] = []
	for node in originals: witnesses.append(weakref(node))
	check(not originals.is_empty(), "cache contains built ship roots")
	for _frame in 3: await physics_frame
	check(not gangway_hit(owner).is_empty(), "real gangway has collision before retirement")
	var initial_hoist_parts := hoist_parts(originals)
	check(initial_hoist_parts == 12, "three real hoists each build four visual children")
	var hoists: Array = []
	for node in originals:
		if node.get_script() == HOIST: hoists.append(node)
	var first_clocks: Array = []
	for hoist in hoists: first_clocks.append(hoist.clock)
	await create_timer(1.0).timeout
	var advancing := hoists.size() == 3
	for index in hoists.size(): advancing = advancing and hoists[index].clock > first_clocks[index] + .5
	check(advancing, "live rendered hoists advance their existing clocks")
	for cycle in 3:
		owner._retire_chunk(chunk)
		var paused_clocks: Array = []
		var paused_poses: Array = []
		for hoist in hoists:
			paused_clocks.append(hoist.clock)
			paused_poses.append(hoist.load_mesh.transform)
		var detached := true
		for node in originals: detached = detached and is_instance_valid(node) and node.get_parent() == null
		check(detached, "retirement detaches every cached ship root/%d" % cycle)
		for _frame in 3: await physics_frame
		await create_timer(.2).timeout
		var paused := true
		for index in hoists.size(): paused = paused and hoists[index].clock == paused_clocks[index]
		check(paused, "off-tree hoists consume no animation ticks/%d" % cycle)
		check(gangway_hit(owner).is_empty(), "retired ship no longer supplies a collider/%d" % cycle)
		owner._drain_retired()
		scene.remove_child(owner)
		check(owner._record_cache.size() == 1, "unmount preserves one owned record/%d" % cycle)
		scene.add_child(owner)
		owner.set_process(false)
		chunk = Node3D.new()
		owner.add_child(chunk)
		owner._build_record_cached(chunk, record)
		var continuous := true
		for index in hoists.size(): continuous = continuous and hoists[index].clock == paused_clocks[index] and hoists[index].load_mesh.transform == paused_poses[index]
		check(continuous, "reattach preserves clock and cargo pose/%d" % cycle)
		var same_roots := chunk.get_child_count() == originals.size()
		for index in originals.size(): same_roots = same_roots and is_same(chunk.get_child(index), originals[index])
		check(same_roots, "remount reuses every root without rebuilding/%d" % cycle)
		for _frame in 3: await physics_frame
		check(not gangway_hit(owner).is_empty(), "reused real gangway restores collision/%d" % cycle)
		check(hoist_parts(originals) == initial_hoist_parts, "reentry does not duplicate hoist visuals/%d" % cycle)
		await create_timer(.2).timeout
		var resumed := true
		for index in hoists.size(): resumed = resumed and hoists[index].clock > paused_clocks[index] + .1
		check(resumed, "reattached hoists resume animation/%d" % cycle)
	owner._detach_cached_records(chunk)
	owner.free()
	var all_freed := true
	for witness in witnesses: all_freed = all_freed and witness.get_ref() == null
	check(all_freed, "definitive owner deletion frees all detached roots")
	scene.free()
	print("NORTHSTAR_CACHE checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
