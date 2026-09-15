extends SceneTree
const BANK := preload("res://audio/combat/CombatAudioBank.gd")
const BULLET := preload("res://Bullet.tscn")
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures.append(message)

func run() -> void:
	create_timer(40).timeout.connect(func(): quit(2))
	var city := root.get_node_or_null("CityAudioManager")
	if city:
		city.set_process(false)
		for child in city.get_children():
			if child is AudioStreamPlayer: child.stop()
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var listener := AudioListener2D.new()
	world.add_child(listener)
	listener.position = Vector2(600,350)
	listener.make_current()
	var capture := "record" in OS.get_cmdline_user_args()
	var recorder := AudioEffectRecord.new()
	var bus := AudioServer.get_bus_index("SFX")
	var slot := AudioServer.get_bus_effect_count(bus)
	if capture:
		AudioServer.set_bus_mute(bus,false)
		AudioServer.set_bus_volume_db(bus,0)
		AudioServer.add_bus_effect(bus,recorder)
		recorder.set_recording_active(true)
		await create_timer(0.25).timeout
	var pool: Node
	var actors: Array[Node2D] = []
	for path in ["Player", "AnimatedPedestrian3D", "PoliceOfficer", "CarjackedDriver", "Paramedic", "Firefighter", "Mortician"]:
		var actor: Node2D = load("res://"+path+".gd").new()
		actor.position = Vector2(600,350)
		if path == "Player":
			var camera := Camera2D.new()
			camera.name = "Camera"
			actor.add_child(camera)
		world.add_child(actor)
		actor.set_physics_process(false)
		actor.set_process(false)
		actors.append(actor)
		# Fear has its own separate voice; isolate the injury feedback here.
		if path == "AnimatedPedestrian3D": actor.is_scared = true
		var hp: int = actor.health
		if pool: pool._recent.clear()
		var count: int = pool.events_played if pool else 0
		actor.take_damage(5)
		pool = world.get_node_or_null("CombatImpactAudio")
		check(pool != null and pool.events_played == count+1 and actor.health == hp-5,path+" direct injury plays one hurt sound")
		var playing := false
		for voice in pool.voices:
			if voice.stream == BANK.sound("flesh") and voice.playing:
				playing = voice.bus == &"SFX" and voice.global_position == actor.global_position
		check(playing,path+" hurt voice plays on SFX at the person")
		if capture: await create_timer(0.65).timeout
		pool._recent.clear()
		count = pool.events_played
		var bullet := BULLET.instantiate()
		bullet.damage = 7
		world.add_child(bullet)
		bullet._hit(actor,actor.global_position+Vector2(8,0),Vector2.LEFT)
		check(pool.events_played == count+1 and actor.health == hp-12,path+" bullet and damage callback do not double the splash")
		if capture: await create_timer(0.65).timeout
		pool._recent.clear()
		count = pool.events_played
		actor.take_damage(0)
		actor.take_damage(-1)
		check(pool.events_played == count and actor.health == hp-12,path+" no injury sound or health change for invalid damage")
	pool._recent.clear()
	var count: int = pool.events_played
	actors[0].take_damage(1)
	actors[1].take_damage(1)
	check(pool.events_played == count+2,"two nearby people both react")
	pool._recent.clear()
	count = pool.events_played
	for i in 8:
		var bullet := BULLET.instantiate()
		bullet.damage = 1
		world.add_child(bullet)
		bullet._hit(actors[0],actors[0].global_position,Vector2.LEFT)
	check(pool.events_played == count+1,"shotgun pellets share one injury voice")
	check(pool.voices.size() == 10,"injury sounds retain bounded voice pool")
	actors[0]._respawn_grace_active = true
	pool._recent.clear()
	count = pool.events_played
	actors[0].take_damage(5)
	check(pool.events_played == count,"respawn protection does not cry out")
	if capture:
		await create_timer(0.5).timeout
		recorder.set_recording_active(false)
		var wav := recorder.get_recording()
		check(wav.save_to_wav("D:/geteco/artifacts/hurt-audio-0910/hurt-preview.wav") == OK,"real mixer capture saved")
		AudioServer.remove_bus_effect(bus,slot)
	print("HURT_AUDIO failures=",failures)
	world.queue_free()
	await create_timer(0.3).timeout
	quit(0 if failures.is_empty() else 1)
