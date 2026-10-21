extends SceneTree
## Exercise the actual root shutdown signal with pending, detached GPU owners.
const RELEASE := preload("res://runtime/GpuReleaseQueue.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var leaf := MeshInstance3D.new()
	leaf.mesh=BoxMesh.new()
	if not RELEASE.adopt_detached_leaf(leaf):
		leaf.free()
		push_error("GPU_SHUTDOWN could not create pending leaf")
		quit(1)
		return
	var branch := Node3D.new()
	root.add_child(branch)
	var child := MeshInstance3D.new()
	child.mesh=SphereMesh.new()
	branch.add_child(child)
	RELEASE.retire(branch)
	var leaf_id := leaf.get_instance_id()
	# Cache evictions are detached whole subtrees, not merely detached GPU
	# leaves. Shutdown may happen before even their first disposal slice.
	var detached := Node3D.new()
	var detached_child := MeshInstance3D.new()
	detached_child.mesh=BoxMesh.new()
	detached.add_child(detached_child)
	var detached_id := detached.get_instance_id()
	var detached_child_id := detached_child.get_instance_id()
	RELEASE.retire_detached_subtree(detached)
	assert(not detached.is_queued_for_deletion(),"detached subtree must remain queue-owned until shutdown")
	assert(RELEASE.debug_snapshot().roots==2,"both in-tree and detached roots must be pending at shutdown")
	root.tree_exiting.connect(func():
		assert(RELEASE.pending()==0,"deferred resources must drain before renderer teardown")
		assert(not is_instance_id_valid(leaf_id),"detached GPU owner must be freed")
		assert(not is_instance_id_valid(detached_id),"pending detached subtree must be freed before renderer teardown")
		assert(not is_instance_id_valid(detached_child_id),"pending detached subtree's GPU owner must be freed")
		# Another owner's shutdown callback can hand work over after the queue's
		# own shutdown callback has already run. There will be no next tick.
		var late := Node3D.new()
		var late_child := MeshInstance3D.new()
		late_child.mesh=SphereMesh.new()
		late.add_child(late_child)
		var late_id := late.get_instance_id()
		var late_child_id := late_child.get_instance_id()
		RELEASE.retire_detached_subtree(late)
		assert(RELEASE.pending()==0,"a late shutdown handoff cannot reopen the disposal queue")
		assert(not is_instance_id_valid(late_id),"late detached root must be freed synchronously during shutdown")
		assert(not is_instance_id_valid(late_child_id),"late detached root cannot leak its GPU owner")
		print("GPU_SHUTDOWN PASS pending=",RELEASE.pending()))
	quit(0)
