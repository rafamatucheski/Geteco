extends SceneTree
class RegionProbe extends "res://world/regions/NativeRegion.gd":
	var surface_builds := 0
	func _build_surfaces(_chunk: Node3D, _rect: Rect2, _key: Vector2i) -> void:
		surface_builds += 1

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func run() -> void:
	var region := RegionProbe.new()
	region.region_id = "mountain"
	region.prepared = true
	region.set_focus(Vector3(10.0, 0.0, 10.0))
	var key := Vector2i.ZERO
	check(region.chunks.has(key), "focused chunk exists before actor admission")
	check(region.surface_builds == 1, "focused chunk builds collision surfaces synchronously")
	check(region.build_jobs.size() == 1 and int(region.build_jobs[0].stage) == 1,
		"focused chunk leaves records and dressing in the streaming queue")
	check(region.pending.size() == 8, "neighbor chunks remain queued")
	check(not region.is_streaming_idle(), "residency reports unfinished streaming work")
	var queued_key := Vector2i(1, 0)
	var queued_chunk := Node3D.new()
	region.add_child(queued_chunk)
	region.chunks[queued_key] = queued_chunk
	region.build_jobs.append({"key": queued_key, "chunk": queued_chunk,
		"rect": Rect2(64.0, 0.0, 64.0, 64.0), "stage": 0, "index": 0, "warming": false})
	region._ensure_chunk_surfaces(queued_key)
	check(region.surface_builds == 2 and int(region.build_jobs[0].stage) == 1,
		"an already queued focus neighbor gets collision before the job queue resumes")
	region.free()
	print("NATIVE_REGION_FOCUS_BUDGET checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
