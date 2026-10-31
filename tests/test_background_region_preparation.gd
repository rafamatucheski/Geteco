extends SceneTree
class ControllerProbe:
	extends Node
	var ready_for_play := false
	var session = null
	var travel_busy := false
	var regions := {}
	var background_loading_status := {}
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func run() -> void:
	var controller := ControllerProbe.new()
	root.add_child(controller)
	var queue := preload("res://runtime/BackgroundRegionPreparation.gd").new()
	queue.controller = controller
	controller.add_child(queue)
	queue.set_process(false)
	var folder := "user://background-loading-contract-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var paths: Array[String] = []
	for i in 3:
		var path := folder.path_join("mesh%d.tres"%i)
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE*(i+1)
		check(ResourceSaver.save(mesh,path) == OK,"isolated fixture saved")
		paths.append(path)
		queue.request(path,"harbor" if i == 0 else "mountain")
	queue.request(paths[0],"harbor")
	check(queue.pending.size() == 3,"duplicate requests coalesced")
	queue._process(.016)
	check(queue.active_path.is_empty(),"startup cannot admit background work")
	queue.take("mountain")
	check(queue.pending[0].region == "mountain" and queue.pending[2].region == "harbor","live destination promoted without losing requests")
	queue._step()
	check(not queue.active_path.is_empty() and queue.loaded == 0,"submission does not synchronously collect resource")
	for i in 600:
		queue._step()
		if queue.pending.is_empty() and queue.active_path.is_empty(): break
		await process_frame
	check(queue.loaded == 3 and queue.failed.is_empty(),"threaded loads finish without fallback")
	check(queue.held.size() == 3,"resources retained for later use")
	check(queue.held[paths[1]].size == Vector3.ONE*2,"loaded content preserved")
	check(queue.get_child_count() == 0,"preparation never instantiates gameplay or physics nodes")
	queue.enqueue("harbor")
	var count := queue.pending.size()
	queue.enqueue("harbor")
	check(queue.pending.size() == count,"manifest submissions deduplicate")
	check(not queue.pending.is_empty(),"generated manifest schedules real resources")
	# Cancela enquanto um pedido real do loader pertence ao nó que logo será liberado.
	var cancelled := preload("res://runtime/BackgroundRegionPreparation.gd").new()
	controller.add_child(cancelled)
	cancelled.set_process(false)
	var cancel_path := folder.path_join("cancel.tres")
	ResourceSaver.save(BoxMesh.new(),cancel_path)
	cancelled.request(cancel_path,"desert")
	cancelled._step()
	check(cancelled.active_path == cancel_path,"cancellation fixture submitted")
	cancelled.free()
	for i in 600:
		if ResourceLoader.load_threaded_get_status(cancel_path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE: break
		await process_frame
	check(ResourceLoader.load_threaded_get_status(cancel_path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,"teardown drains request without retaining controller")
	controller.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cancel_path))
	for path in paths: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))
	print("BACKGROUND_PREPARATION checks=%d failures=%d"%[checks,failures])
	quit(0 if failures == 0 else 1)
