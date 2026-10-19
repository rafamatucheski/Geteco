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
	root.tree_exiting.connect(func():
		assert(RELEASE.pending()==0,"deferred resources must drain before renderer teardown")
		assert(not is_instance_id_valid(leaf_id),"detached GPU owner must be freed")
		print("GPU_SHUTDOWN PASS pending=",RELEASE.pending()))
	quit(0)
