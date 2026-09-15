extends SceneTree
## Exercise the actual death callbacks and optionally record the SFX mixer.
const REACTIONS := preload("res://audio/reactions/CharacterReactionBank.gd")
const IMPACT := preload("res://audio/combat/CombatImpactAudio.gd")
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func run() -> void:
	create_timer(25).timeout.connect(func(): quit(2))
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
	listener.make_current()
	check(ProceduralAudio.get_scream_stream() == REACTIONS.sound("hurt"), "injury uses recorded voice")
	check(ProceduralAudio.get_pedestrian_scream_stream() == REACTIONS.sound("panic"), "panic uses recorded voice")
	check(ProceduralAudio.get_death_reaction_stream() == REACTIONS.sound("death"), "death has a separate recorded palette")
	for kind in ["hurt", "panic", "death"]:
		var bank := REACTIONS.sound(kind) as AudioStreamRandomizer
		check(bank.streams_count == 5, kind + " has five takes")
		for i in 5:
			var sample := bank.get_stream(i) as AudioStreamWAV
			check(sample != null and sample.get_length() > .1 and not sample.stereo, kind + " loads positional PCM take " + str(i))
	var capture := "record" in OS.get_cmdline_user_args()
	var recorder := AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	var bus := AudioServer.get_bus_index("SFX")
	var slot := AudioServer.get_bus_effect_count(bus)
	if capture:
		AudioServer.set_bus_mute(bus, false)
		AudioServer.set_bus_volume_db(bus, 0)
		AudioServer.add_bus_effect(bus, recorder)
		recorder.set_recording_active(true)
		await create_timer(.25).timeout
		# First: three dry contacts. Then four actual lethal-damage callbacks.
		for i in 3:
			IMPACT.play_hit(world, Vector2.ZERO, &"flesh", 15)
			await create_timer(.8).timeout
	for path in ["AnimatedPedestrian3D", "PoliceOfficer", "Paramedic", "Firefighter"]:
		var actor: Node2D = load("res://" + path + ".gd").new()
		world.add_child(actor)
		actor.set_physics_process(false)
		actor.set_process(false)
		actor.take_damage(10000)
		var deaths := 0
		var panics := 0
		for child in actor.get_children():
			if child is AudioStreamPlayer2D and child.playing:
				if child.stream == REACTIONS.sound("death") and child.bus == &"SFX": deaths += 1
				if child.stream == REACTIONS.sound("panic"): panics += 1
		check(actor.is_dead and deaths == 1, path + " death callback plays one recorded death voice")
		check(panics == 0, path + " lethal hit does not stack a panic voice")
		if capture: await create_timer(1.2).timeout
	if capture:
		await create_timer(.4).timeout
		recorder.set_recording_active(false)
		check(recorder.get_recording().save_to_wav("D:/geteco/artifacts/character-sounds-0910/preview.wav") == OK, "mixer preview saved")
		AudioServer.remove_bus_effect(bus, slot)
	world.queue_free()
	await create_timer(.2).timeout
	print("CHARACTER_REACTION_AUDIO failures=", failures)
	quit(0 if failures.is_empty() else 1)
