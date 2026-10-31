extends SceneTree
## Identidade/estado em runtime e posse limitada das células do deserto recém-carregadas em streaming.
const CACHE := preload("res://world/desert/DesertChunkCache.gd")
const TERRAIN := preload("res://world/desert/DesertTerrainMesh.gd")
const HORIZON := preload("res://world/desert/DesertHorizon.gd")
const LIFETIME := preload("res://world/desert/DesertPreparationLifetime.gd")
class SurfaceProbe:
	extends "res://world/desert/DesertRegion.gd"
	func _ready() -> void:
		prepare_data()
		prepared=true
		set_process(false)
var failures := 0
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("DESERT_REUSE FAIL " + label)
	else: print("DESERT_REUSE PASS " + label)

func run() -> void:
	if "--cancel-only" in OS.get_cmdline_user_args():
		await _cancellation_contract()
		print("DESERT_REUSE_DONE checks=%d failures=%d" % [checks, failures])
		quit(0 if failures==0 else 1)
		return
	var cache := CACHE.new()
	var cell := Node3D.new()
	cell.set_meta("mutable_state", 7)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	cell.add_child(body)
	root.add_child(cell)
	var original_id := cell.get_instance_id()
	root.remove_child(cell)
	check(cache.put(Vector2i.ZERO, {"chunk":cell}).is_empty(), "First completed cell retained")
	check(not cell.is_inside_tree() and body.get_parent()==cell, "Retained cell is detached with its collision intact")
	var restored: Dictionary = cache.take(Vector2i.ZERO)
	check(restored.chunk.get_instance_id()==original_id and restored.chunk.get_meta("mutable_state")==7, "Return reuses exact nodes and mutable state")
	root.add_child(restored.chunk)
	check(shape.get_parent()==body and body.is_inside_tree(), "Reattachment restores same physical subtree")
	cell.free()
	check(cache.take(Vector2i.ZERO).is_empty(), "Checked-out cell cannot be mounted twice")
	for index in CACHE.MAX_CELLS+1:
		var piece := Node3D.new()
		piece.name = "Cell_%d" % index
		for retired in cache.put(Vector2i(index, 1), {"chunk":piece}):
			check(retired.name=="Cell_0", "Only least-recently-used cell is evicted")
			retired.free()
	check(cache.entries.size()==CACHE.MAX_CELLS and cache.order.size()==CACHE.MAX_CELLS, "Cache stays bounded")
	for retired in cache.clear(): retired.free()
	check(cache.entries.is_empty() and cache.order.is_empty(), "Teardown releases every detached owner")
	await _surface_contract()
	await _terrain_slice_contract()
	await _cancellation_contract()
	print("DESERT_REUSE_DONE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures==0 else 1)

func _floor(at: Vector3) -> Dictionary:
	return root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3.UP*20,at-Vector3.UP*20,1))

func _surface_contract() -> void:
	var region := SurfaceProbe.new()
	root.add_child(region)
	var point := Vector3(342.5,0,-750)
	var key: Vector2i=region._cell(point)
	region._begin_surface_job(key)
	region._advance_surface_job(key)
	region._advance_surface_job(key)
	check(not region.chunks.has(key) and not region.surfaces_idle(), "Partial neighbouring surface is not reported ready")
	var preparing: Node3D=region._surface_jobs[key].chunk
	check(not preparing.visible and preparing.process_mode==Node.PROCESS_MODE_DISABLED, "Partial cell remains hidden and disabled")
	await physics_frame
	await physics_frame
	check(_floor(point).is_empty(), "Partial terrain is absent from physical space")
	check(region.prepare_collision_at(point), "Urgent actor support completes remaining physical stages")
	check(region._surface_jobs.is_empty() and region.chunks.has(key), "Completed surface enters resident cell table once")
	var chunk: Node3D=region.chunks[key]
	var identity:=chunk.get_instance_id()
	await physics_frame
	await physics_frame
	check(not _floor(point).is_empty(), "Completed weathered highway has physical support")
	region._complete_focus_chunk(key)
	for frame in 1200:
		if chunk.has_meta("desert_reuse_ready"): break
		await process_frame
	check(chunk.has_meta("desert_reuse_ready"), "Cell is reusable only after deferred mesh work ends")
	chunk.set_meta("return_state",19)
	region._retire_or_cache_chunk(key,chunk)
	region.chunks.erase(key)
	check(not chunk.is_inside_tree() and region.streaming_reuse_diagnostics().cells==1, "Completed cell detaches into bounded cache")
	await physics_frame
	await physics_frame
	check(_floor(point).is_empty(), "Cached cell leaves no phantom solid")
	region._ensure_chunk_surfaces(key)
	check(region.chunks[key].get_instance_id()==identity and chunk.get_meta("return_state")==19, "Returning surface reuses exact hierarchy and state")
	check(region.build_jobs.is_empty(), "Return does not rebuild decoration or terrain")
	await physics_frame
	await physics_frame
	check(not _floor(point).is_empty(), "Same highway collision returns after reuse")
	var admission_gate := Node3D.new()
	admission_gate.add_to_group("digo_vehicle_gate")
	chunk.add_child(admission_gate)
	region._retire_or_cache_chunk(key,chunk)
	region.chunks.erase(key)
	check(region.streaming_reuse_diagnostics().cells==0, "Admission mechanisms keep their existing teardown lifecycle")
	region.free()
	await process_frame

## Células dentro do campo de relevo do mapa compacto (21/10); as antigas (-10,-18)/(-11,-18) ficaram
## fora e o terreno saía sem faces. Duas células distintas: o contrato de cancelamento exige uma que o
## de fatiamento não deixou em cache.
static func _relief_cell(offset_cells: int) -> Vector2i:
	var center: Vector2 = TERRAIN.FIELD.BOUNDS.get_center()
	return Vector2i(floori(center.x/TERRAIN.CELL)+offset_cells,floori(center.y/TERRAIN.CELL))

func _terrain_slice_contract() -> void:
	var key:=_relief_cell(0)
	var original: ArrayMesh=TERRAIN.mesh_for(key)
	var expected: Array=original.surface_get_arrays(0)
	var expected_faces: PackedVector3Array=TERRAIN._faces[key]
	TERRAIN._meshes.erase(key)
	TERRAIN._faces.erase(key)
	var start_frame:=Engine.get_process_frames()
	var sliced: ArrayMesh=await TERRAIN.mesh_for_sliced(key,self,500)
	var actual: Array=sliced.surface_get_arrays(0)
	check(actual[Mesh.ARRAY_VERTEX]==expected[Mesh.ARRAY_VERTEX], "Sliced terrain preserves every vertex and triangle order")
	check(actual[Mesh.ARRAY_NORMAL]==expected[Mesh.ARRAY_NORMAL], "Sliced terrain preserves normals")
	check(TERRAIN._faces[key]==expected_faces, "Sliced terrain preserves physical faces")
	check(Engine.get_process_frames()>start_frame, "Terrain yields within a cell instead of waiting for the whole mesh")

func _cancellation_contract() -> void:
	var token := {"cancelled":false,"roots":[]}
	var result := {"done":false,"value":null}
	var build := func() -> void:
		result.value=await HORIZON.build_sliced(self,token)
		result.done=true
	build.call()
	check(token.roots.size()==1, "Suspended horizon has an explicit temporary owner")
	var reference: WeakRef=token.roots[0]
	LIFETIME.cancel(token)
	check(not is_instance_valid(reference.get_ref()) and token.roots.is_empty(), "Cancellation releases detached roots immediately without another frame")
	await process_frame
	await process_frame
	check(result.done and result.value==null, "Cancelled horizon resumes without publishing a partial world")
	var terrain_token := {"cancelled":false,"roots":[]}
	var terrain_result := {"done":false,"value":null}
	var key := _relief_cell(1)
	var build_mesh := func() -> void:
		terrain_result.value=await TERRAIN.mesh_for_sliced(key,self,1,terrain_token)
		terrain_result.done=true
	build_mesh.call()
	LIFETIME.cancel(terrain_token)
	await process_frame
	await process_frame
	check(terrain_result.done and terrain_result.value==null and not TERRAIN._meshes.has(key) and not TERRAIN._faces.has(key), "Cancelled cell never enters complete mesh or collision caches")
	var guard := Node3D.new()
	root.add_child(guard)
	var candidate := SurfaceProbe.new()
	var region_result := {"done":false}
	var prepare := func() -> void:
		await candidate.prepare_presentation_incremental(self,guard)
		region_result.done=true
	prepare.call()
	var presentation_token: Dictionary=candidate._presentation_lifetime
	guard.free()
	check(presentation_token.cancelled and presentation_token.roots.is_empty(), "World exit cancels detached presentation synchronously")
	await process_frame
	await process_frame
	check(region_result.done and candidate._horizon==null, "Cancelled preparation publishes no horizon on the retained candidate")
	candidate.free()
	var completed_candidate := SurfaceProbe.new()
	completed_candidate._horizon=Node3D.new()
	var completed_root: WeakRef = weakref(completed_candidate._horizon)
	completed_candidate.free()
	check(not is_instance_valid(completed_root.get_ref()), "Unused completed horizon is released with its unmounted candidate")
