extends SceneTree
## Deterministic partial drain -> unmount -> remount -> new drain contract.
## Slow exit is a fixture budget boundary, not a measurement of gameplay FPS.
class RegionFixture extends "res://world/regions/NativeRegion.gd":
	# Own the fixture geometry without starting unrelated world generation.
	# Disposal/exit/notifications remain the real production implementation.
	func _ready() -> void: pass
class BudgetBoundary extends Node3D:
	func _exit_tree() -> void:
		var until := Time.get_ticks_usec()+2500
		while Time.get_ticks_usec()<until: pass
var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("RETIRE_STACK ","PASS " if ok else "FAIL ",label)
	if not ok: failures += 1;push_error(label)
func chunk_fixture(owner: Node3D) -> Node3D:
	var chunk := Node3D.new()
	chunk.name="RestoreRetireFixture"
	owner.add_child(chunk)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new();box.size=Vector3(3,.2,3)
	shape.shape=box;body.add_child(shape);chunk.add_child(body)
	var stopper := BudgetBoundary.new()
	chunk.add_child(stopper) # Last child exits first and consumes one real budget.
	return chunk
func hit(owner: Node3D) -> Dictionary:
	return owner.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3.UP,Vector3.DOWN,1))
func _run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():quit(2);return
	var scene := Node3D.new();root.add_child(scene)
	var owner := RegionFixture.new()
	scene.add_child(owner);owner.set_process(false)
	var original := chunk_fixture(owner)
	var original_ref: WeakRef = weakref(original)
	for i in 3:await physics_frame
	check(not hit(owner).is_empty(),"real fixture support exists before retirement")
	owner._retire_chunk(original);owner._drain_retired()
	check(owner._retiring.size()==1 and not owner._retire_stack.is_empty(),"first drain is genuinely partial")
	check(is_instance_valid(original) and not original.is_queued_for_deletion(),"partial first chunk remains owned")
	scene.remove_child(owner)
	check(original_ref.get_ref()==null and owner._retiring.is_empty(),"unmount frees first pending chunk")
	check(owner._retire_stack.is_empty(),"unmount also resets traversal state")
	scene.add_child(owner);owner.set_process(false)
	for i in 3:await physics_frame
	check(hit(owner).is_empty(),"old support stays absent after owner remount")
	var next := chunk_fixture(owner);var next_ref: WeakRef = weakref(next)
	for i in 3:await physics_frame
	check(not hit(owner).is_empty(),"new support registers on remount")
	var next_boundary: WeakRef = weakref(next.get_child(1))
	owner._retire_chunk(next);owner._drain_retired()
	check(next_boundary.get_ref()==null and is_instance_valid(next) and not next.is_queued_for_deletion(),"new drain makes progress and preserves remaining budgeted subtree")
	for i in 20:
		# A failing entry must not generate twenty equivalent freed-instance errors.
		if next_boundary.get_ref()!=null:break
		if owner._retiring.is_empty():break
		owner._drain_retired()
		await process_frame
	for i in 3:await physics_frame
	check(next_ref.get_ref()==null and owner._retiring.is_empty() and owner._retire_stack.is_empty(),"second retirement eventually drains all ownership")
	check(hit(owner).is_empty(),"second support is absent after final drain")
	var returned := chunk_fixture(owner);var returned_ref: WeakRef = weakref(returned)
	for i in 3:await physics_frame
	check(not hit(owner).is_empty(),"return installs real support again")
	owner.free()
	for i in 3:await physics_frame
	check(returned_ref.get_ref()==null,"definitive owner destruction frees returned support")
	scene.free()
	print("RETIRE_STACK checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
