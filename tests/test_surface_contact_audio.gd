extends SceneTree

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var actor := Node2D.new()
	scene.add_child(actor)
	var ground := Polygon2D.new()
	ground.polygon = PackedVector2Array([Vector2(-50,-50), Vector2(50,-50), Vector2(50,50), Vector2(-50,50)])
	ground.set_meta("mountain_surface", "earth")
	ground.add_to_group("audio_ground")
	scene.add_child(ground)
	var resolver := preload("res://audio/footsteps/FootstepSurfaceResolver.gd")
	assert(resolver.resolve(actor, false) == "dirt")
	assert(resolver.resolve(actor, true) == "dirt_wet")
	ground.position.x = 200
	assert(resolver.resolve(actor, false) == "concrete")
	var bank := preload("res://audio/SurfaceContactAudio.gd")
	var previous := PackedByteArray()
	for material in bank.PROFILES:
		var step := bank.sound(material, false)
		var road := bank.sound(material, true)
		assert(step.data.size() > 0 and step.data != road.data)
		assert(road.loop_mode == AudioStreamWAV.LOOP_FORWARD)
		assert(road.data != previous)
		assert(bank.sound(material, true) == road)
		assert(bank.sound(material + "_wet", true).data != road.data)
		previous = road.data
	var engine := preload("res://audio/VehicleEngineSound.gd").new()
	var audio := AudioStreamPlayer2D.new()
	actor.add_child(audio)
	ground.position.x = 0
	engine._update_road(audio, 0.5)
	assert(engine._road_player.stream == bank.sound("dirt", true))
	engine._update_road(audio, 0.0)
	assert(not engine._road_player.playing)
	print("PASS: material bounds, wet variants, distinct steps/tires, cached loops and stationary silence")
	quit()
