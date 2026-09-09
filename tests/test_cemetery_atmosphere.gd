extends SceneTree
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var lot := Node2D.new()
	root.add_child(lot)
	var player := Node2D.new()
	player.add_to_group("player")
	lot.add_child(player)
	var teller := preload("res://world/harbor/events/CemeteryStoryteller.gd").new()
	lot.add_child(teller)
	teller.set_physics_process(false)
	teller.set_route(PackedVector2Array())
	player.position = teller.position
	teller._physics_process(0.1)
	assert(not teller.speech.text.is_empty(), "Story plays beside a grave")
	teller._physics_process(19)
	assert(teller.stop_index == 1 and not teller.finished, "Moves to next grave")
	var atmosphere := preload("res://world/harbor/events/CemeteryAtmosphere.gd").new()
	lot.add_child(atmosphere)
	atmosphere.set_process(false)
	await process_frame
	assert(atmosphere.wind.playing)
	assert(atmosphere.wind.stream.data.decode_s16(0) == 0)
	atmosphere.start_visit()
	var first = atmosphere.keeper
	atmosphere.start_visit()
	assert(atmosphere.keeper == first, "Only one visiting keeper")
	atmosphere.keeper.finished = true
	atmosphere._process(23)
	assert(atmosphere.leaving)
	atmosphere.keeper.finished = true
	atmosphere._process(1)
	await process_frame
	assert(not is_instance_valid(atmosphere.keeper))
	print("CEMETERY_ATMOSPHERE PASS")
	lot.queue_free()
	await process_frame
	quit()
