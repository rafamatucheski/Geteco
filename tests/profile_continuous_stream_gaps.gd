extends SceneTree
## Read-only workload probe: no save writes, no replacement gameplay callbacks.
var frames: Array[Dictionary] = []
var markers: Array[Dictionary] = []
var phase := "idle"
var started := 0
var previous := 0
var stream: Node
var tree_count := 0
var marker_names := ["MountainInteriorManager","MountainAltitudeParallax","MountainPassRoad","Setpieces","MountainSceneryDetailed","MountainBaseTerrain","BackcountryDirtRoads","CliffFacesAndRidges","WaterSystemDetailed","SecretMountainLake","MountainChalets","MountainAmmuNation","DensePineForest","RoadSignage","IceStormManager","ColdSurvivalController","MountainExpedition","MountainSettlement","MountainTraffic"]
func _init() -> void: _run.call_deferred()
func _frame() -> void:
	var now := Time.get_ticks_usec()
	if previous>0: frames.append({"phase":phase,"ms":float(now-previous)/1000.0,"at_ms":float(now-started)/1000.0})
	previous = now
func _node_added(node: Node) -> void:
	var named := String(node.name) in marker_names
	var parent := node.get_parent()
	if parent != null and parent.name == &"MountainSettlement": named = true
	if parent != null and parent.name == &"DensePineForest":
		tree_count += 1
		if tree_count % 100 == 0 or tree_count == 1:
			markers.append({"name":"forest_tree_%d"%tree_count,"at_ms":float(Time.get_ticks_usec()-started)/1000.0})
	if named:
		markers.append({"name":str(node.get_path()),"at_ms":float(Time.get_ticks_usec()-started)/1000.0})
func _memory() -> Dictionary:
	return {"godot_static_mib":OS.get_static_memory_usage()/1048576.0,"video_mib":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0,"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"objects":Performance.get_monitor(Performance.OBJECT_COUNT)}
func _stats(label: String) -> Dictionary:
	var values: Array[float] = []
	var total := 0.0
	for frame in frames:
		if frame.phase == label:
			values.append(frame.ms)
			total += frame.ms
	values.sort()
	if values.is_empty(): return {}
	return {"frames":values.size(),"mean_ms":total/values.size(),"p95_ms":values[mini(values.size()-1,int(values.size()*0.95))],"max_ms":values[-1]}
func _run() -> void:
	create_timer(100).timeout.connect(func(): printerr("STREAM PROFILE TIMEOUT"); quit(2))
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.get_node("SaveManager").clear_pending_save()
	var campaign := root.get_node("CampaignState")
	for flag in ["harbor_arrival_seen","harbor_arrival_call_complete","harbor_maciota_met","harbor_delivery_complete"]:
		campaign.set_campaign_flag(StringName(flag),true)
	var world = load("res://district/harbor_preview/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.has_node("ContinuousWorld"): await process_frame
	stream = world.get_node("ContinuousWorld")
	# Keep automatic trigger away until the measured explicit request, then restore it.
	stream.set_process(false)
	var player: Node2D = world.get_node("Player")
	player.global_position = Vector2(7050,-4560)
	player.set_physics_process(false)
	var camera := get_root().get_camera_2d()
	if camera: camera.reset_smoothing()
	for i in 30: await process_frame
	var before := _memory()
	started = Time.get_ticks_usec()
	previous = started
	phase = "baseline"
	process_frame.connect(_frame)
	for i in 50: await process_frame
	phase = "loading"
	node_added.connect(_node_added)
	var begin := Time.get_ticks_usec()
	stream.ensure_mountain()
	while not stream.ready_for_crossing: await process_frame
	var ensure_ms := float(Time.get_ticks_usec()-begin)/1000.0
	phase = "after"
	stream.set_process(true)
	for i in 100: await process_frame
	process_frame.disconnect(_frame)
	node_added.disconnect(_node_added)
	var after := _memory()
	# Full process RSS/private bytes sampled after timing so PowerShell cannot contaminate gaps.
	var output: Array = []
	var command := "Get-Process -Id %d | Select-Object WorkingSet64,PrivateMemorySize64,PeakWorkingSet64 | ConvertTo-Json -Compress" % OS.get_process_id()
	OS.execute("powershell.exe",PackedStringArray(["-NoProfile","-Command",command]),output)
	var report := {"resolution":"1280x720","pid":OS.get_process_id(),"ensure_ms":ensure_ms,"before":before,"after":after,"process_memory":output,"baseline":_stats("baseline"),"loading":_stats("loading"),"after_stats":_stats("after"),"markers":markers,"frames":frames}
	var file := FileAccess.open("D:/geteco/continuous-stream-profile-final.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("CONTINUOUS_STREAM_PROFILE ",JSON.stringify({"ensure_ms":ensure_ms,"before":before,"after":after,"baseline":_stats("baseline"),"loading":_stats("loading"),"after_stats":_stats("after"),"process_memory":output}))
	for marker in markers: print("STAGE ",JSON.stringify(marker))
	for frame in frames:
		if frame.phase == "loading" or frame.ms>80: print("FRAME ",JSON.stringify(frame))
	world.queue_free()
	for i in 4: await process_frame
	quit()
