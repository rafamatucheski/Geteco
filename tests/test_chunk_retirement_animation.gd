extends SceneTree
## Retiring chunks must suspend all actors before incremental leaf destruction.
const REGION := preload("res://world/regions/NativeRegion.gd")
const CIVILIAN := preload("res://assets/CivilianModel.gd")
class Pulse extends Node:
	var ticks := 0
	func _process(_delta: float) -> void: ticks += 1

var failures: Array[String] = []
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func run() -> void:
	# Use the production retirement owner without preparing unrelated geography.
	var region := REGION.new()
	var chunk := Node3D.new()
	root.add_child(chunk)
	var model := CIVILIAN.new()
	chunk.add_child(model)
	var pulse := Pulse.new()
	chunk.add_child(pulse)
	var cached := Node3D.new()
	cached.set_meta("record_cache_key","fixture_cached")
	chunk.add_child(cached)
	var cached_pulse := Pulse.new()
	cached.add_child(cached_pulse)
	region._record_cache["fixture_cached"] = [cached]
	for frame in 3: await process_frame
	check(pulse.ticks>0 and model.can_process(),"fixture actors process before retirement")
	region._retire_chunk(chunk)
	check(not model.can_process() and not pulse.can_process(),"all actors suspend before first teardown slice")
	check(cached.get_parent()==null,"cached group detaches before retirement disables its old owner")
	var active_chunk := Node3D.new()
	root.add_child(active_chunk)
	active_chunk.add_child(cached)
	var cached_ticks := cached_pulse.ticks
	for frame in 3: await process_frame
	check(cached_pulse.can_process() and cached_pulse.ticks>cached_ticks,"cached group resumes animation on remount")
	var ticks := pulse.ticks
	# A paused slice may leave the model alive while one of its joints is gone.
	# Reproduce the actual reported state without changing the model's policy.
	if not model.can_process():
		var limb: Node3D = model.thighs[0]
		limb.get_parent().remove_child(limb)
		limb.free()
		for frame in 3: await process_frame
		check(pulse.ticks==ticks,"retired subtree receives no subsequent process callback")
	var weak_model: WeakRef = weakref(model)
	var slices := 0
	while not region._retiring.is_empty() and slices<30:
		region._drain_retired_slice()
		slices += 1
		await process_frame
	check(region._retiring.is_empty(),"bounded retirement finishes")
	check(weak_model.get_ref()==null,"finished retirement releases the civilian model")
	active_chunk.free()
	region.free()
	for failure in failures: push_error(failure)
	print("CHUNK_RETIREMENT_ANIMATION checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
