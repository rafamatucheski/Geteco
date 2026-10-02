extends SceneTree
## A narrow wrapper may own a wide/expensive subtree. A retirement slice must
## stop at its budget instead of recursively deleting that entire hierarchy.
## The delay creates a deterministic budget boundary; it does not measure FPS.
class RegionFixture extends "res://world/regions/NativeRegion.gd":
	func _ready() -> void: pass
class BudgetLeaf extends Node3D:
	static var deleted := 0
	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			deleted += 1
			var until := Time.get_ticks_usec() + 2000
			while Time.get_ticks_usec() < until: pass
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var region := RegionFixture.new()
	root.add_child(region)
	region.set_process(false)
	var chunk := Node3D.new()
	region.add_child(chunk)
	var wrapper := Node3D.new()
	chunk.add_child(wrapper)
	var wide := Node3D.new()
	wrapper.add_child(wide)
	for i in 24: wide.add_child(BudgetLeaf.new())
	var chunk_ref: WeakRef = weakref(chunk)
	var wrapper_ref: WeakRef = weakref(wrapper)
	var wide_ref: WeakRef = weakref(wide)
	BudgetLeaf.deleted = 0
	region._retire_chunk(chunk)
	var began := Time.get_ticks_usec()
	region._drain_retired()
	var first_ms := float(Time.get_ticks_usec() - began) / 1000.0
	var deleted_first := BudgetLeaf.deleted
	check(deleted_first > 0 and deleted_first < 24, "first slice makes partial progress within narrow wrapper")
	check(region._retiring.size() == 1 and is_instance_valid(chunk_ref.get_ref()), "pending hierarchy remains owned after budget exhaustion")
	check(is_instance_valid(wrapper_ref.get_ref()) and is_instance_valid(wide_ref.get_ref()), "ancestors remain until descendant retirement completes")
	for i in 30:
		if region._retiring.is_empty(): break
		region._drain_retired()
		await process_frame
	for i in 2: await process_frame
	check(BudgetLeaf.deleted == 24, "all descendant destructors eventually execute exactly once")
	check(chunk_ref.get_ref() == null and wrapper_ref.get_ref() == null and wide_ref.get_ref() == null, "completed retirement releases hierarchy")
	check(region._retiring.is_empty() and region._retire_stack.is_empty(), "completed retirement clears ownership and traversal")
	region.free()
	print("RETIRE_LEAF_BUDGET checks=", checks, " failures=", failures, " first_ms=", first_ms, " deleted_first=", deleted_first)
	quit(0 if failures == 0 else 1)
