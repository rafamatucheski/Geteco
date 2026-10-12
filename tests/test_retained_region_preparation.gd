extends SceneTree
class RegionProbe:
	extends "res://world/regions/NativeRegion.gd"
	var built: Array[String] = []
	func prepare_data() -> void: data_prepared = true
	func _build_record(chunk: Node3D, record: Dictionary) -> void:
		built.append(record.kind)
		chunk.add_child(Node3D.new())
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func run() -> void:
	var region := RegionProbe.new()
	region.initial_prewarm_only = true
	region.records[Vector2i.ZERO] = [{"kind":"ship"},{"kind":"test_disposable"}]
	region.records[Vector2i.ONE] = [{"kind":"mountain_village"}]
	root.add_child(region)
	region.set_process(false)
	var live_chunk := Node3D.new()
	region.add_child(live_chunk)
	region.chunks[Vector2i.ONE] = live_chunk
	await preload("res://runtime/RetainedRegionPreparation.gd").run(region)
	check(region.built == ["ship"],"only retained offscreen records built")
	check(region.chunks.size() == 1 and region.chunks[Vector2i.ONE] == live_chunk,"live residency unchanged")
	check(region.get_child_count() == 1,"temporary geometry removed")
	var cached: Node3D = region._record_cache.values()[0][0]
	check(is_instance_valid(cached) and cached.get_parent() == null,"constructed model survives detached")
	await preload("res://runtime/RetainedRegionPreparation.gd").run(region)
	check(region.built == ["ship"],"repeated preparation reuses model")
	region._build_record_cached(live_chunk,region.records[Vector2i.ZERO][0])
	check(cached.get_parent() == live_chunk and region.built == ["ship"],"first real visit consumes retained model without reconstruction")
	check(region.records[Vector2i.ZERO].size() == 2,"authored disposable records remain for live streaming")
	region.free()
	print("RETAINED_PREPARATION checks=%d failures=%d"%[checks,failures])
	quit(0 if failures == 0 else 1)
