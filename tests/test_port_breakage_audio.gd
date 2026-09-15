extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var crate := preload("res://world/harbor/ForkliftCrate.gd").new()
	world.add_child(crate)
	crate.receive_vehicle_impact(20,Vector2.RIGHT)
	check(not crate.broken and crate.velocity.x>0,"Gentle contact pushes intact cargo")
	crate.receive_vehicle_impact(160,Vector2.RIGHT)
	check(crate.broken and crate.collision_layer == 0 and not crate.is_in_group("forklift_cargo"),"Broken cargo stops blocking and cannot be lifted")
	var count := world.get_child_count()
	crate.receive_vehicle_impact(200,Vector2.RIGHT)
	check(world.get_child_count() == count,"Repeated contact does not duplicate debris")
	var bin := preload("res://world/shared/BreakableProp.gd").new()
	bin.debris_material = "trash"
	world.add_child(bin)
	bin.receive_vehicle_impact(90,Vector2.DOWN)
	check(bin.broken and bin.collision_layer == 0,"Bin releases contents and clears collision")
	var sound := preload("res://world/harbor/HarborSoundscape.gd")
	check(sound.port_weight(Vector2(4700,4700)) == 1,"Port replaces city bed inside yard")
	check(sound.port_weight(Vector2(1700,1130)) == 0,"City retains its own ambience")
	check(preload("res://audio/WaterSoundscape.gd").coast_weight(Vector2(6050,4700))>.9,"East quay has water ambience")
	check(preload("res://world/harbor/HarborAudioBank.gd").sound("port").loop_mode == AudioStreamWAV.LOOP_FORWARD,"Work ambience loops")
	for i in 120: await process_frame
	print("PORT BREAKAGE AUDIO failures=",failures)
	world.queue_free()
	await process_frame
	await process_frame
	quit(failures)
