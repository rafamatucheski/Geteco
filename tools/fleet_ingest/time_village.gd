extends SceneTree
const F := preload("res://world/mountain_detail/MountainDetailFactory.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var pos := Vector3(0, 0, 0)
	var t := Time.get_ticks_usec()
	var v = F.build_village(pos)
	var build_ms := float(Time.get_ticks_usec()-t)/1000.0
	t = Time.get_ticks_usec()
	var holder := Node3D.new(); root.add_child(holder); holder.add_child(v)
	var add_ms := float(Time.get_ticks_usec()-t)/1000.0
	t = Time.get_ticks_usec()
	F.finalize_mountain_detail(v)
	var fin_ms := float(Time.get_ticks_usec()-t)/1000.0
	var n := v.find_children("*", "", true, false).size()
	print("VILLAGE cold build=", build_ms, " add=", add_ms, " finalize=", fin_ms, " nodes=", n)
	holder.queue_free(); await process_frame
	t = Time.get_ticks_usec()
	var v2 = F.build_village(pos)
	print("VILLAGE warm build=", float(Time.get_ticks_usec()-t)/1000.0)
	v2.free()
	# thread
	var result := {}
	var id := WorkerThreadPool.add_task(func(): result.node = F.build_village(pos))
	var tt := Time.get_ticks_usec()
	while not WorkerThreadPool.is_task_completed(id): await process_frame
	WorkerThreadPool.wait_for_task_completion(id)
	var thr_nodes := (result.node as Node).find_children("*", "", true, false).size() if result.has("node") else -1
	print("VILLAGE thread ok nodes=", thr_nodes, " wall_ms=", float(Time.get_ticks_usec()-tt)/1000.0)
	quit()
