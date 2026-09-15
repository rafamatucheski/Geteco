extends SceneTree
const PAIN := preload("res://audio/reactions/PainReaction.gd")
var failures := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func run() -> void:
	create_timer(25).timeout.connect(func(): quit(2))
	seed(190913)
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
	var player = load("res://Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	world.add_child(player)
	player.set_physics_process(false)
	player._respawn_grace_active = true
	player.take_damage(15)
	check(not player.has_node("PainReaction"), "Invulnerability does not play hurt vocals")
	player._respawn_grace_active = false
	player.armor = 100
	player.take_damage(15)
	check(not player.has_node("PainReaction"), "Fully absorbed armor hit does not play pain")
	player.armor = 0
	player.health = 1000
	var bullet = load("res://Bullet.tscn").instantiate()
	world.add_child(bullet)
	bullet._hit(player, player.position, Vector2.ZERO)
	var voice: Node = player.get_node_or_null("PainReaction")
	check(voice != null, "Actual bullet reaches Dante's pain reaction")
	if voice == null:
		quit(1)
		return
	voice.stop()
	voice.next_voice_ms = 0
	voice.next_attempt_ms = 0
	check(not PAIN.react(player, 12, .99), "Ordinary hit can remain vocally silent")
	voice.next_attempt_ms = 0
	var record := OS.get_cmdline_user_args().has("--record")
	var recorder := AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	var bus := AudioServer.get_bus_index("SFX")
	var slot := AudioServer.get_bus_effect_count(bus)
	check(PAIN.react(player, 12, 0), "Selected hit plays a real recorded hurt take")
	check(voice.playing and voice.bus == &"SFX" and voice.stream.streams_count == 5, "Five human takes play through positional SFX")
	var count: int = voice.reactions_played
	for i in 12: player.take_damage(1)
	check(voice.reactions_played == count, "Burst cannot layer repeated pain voices")
	voice.stop()
	check(not PAIN.react(player, 12, 0), "Cooldown remains after voice finishes")
	await create_timer(2).timeout
	check(PAIN.react(player, 30, 0), "Later heavy hit can trigger another reaction")
	player.is_dead = true
	await process_frame
	await process_frame
	check(not voice.playing and not PAIN.react(player, 15, 0), "Death stops hurt voice and prevents another")
	var npc = load("res://AnimatedPedestrian3D.gd").new()
	world.add_child(npc)
	npc.set_physics_process(false)
	npc.health = 1000
	var npc_bullet = load("res://Bullet.tscn").instantiate()
	world.add_child(npc_bullet)
	npc_bullet._hit(npc, npc.position, Vector2.ZERO)
	check(npc.has_node("PainReaction"), "Actual NPC bullet damage reaches the same occasional pain policy")
	await create_timer(2.1).timeout
	if record:
		# Audition the voice alone; the artificial same-frame burst above is
		# a concurrency test and is not a representative listening preview.
		AudioServer.set_bus_mute(bus, false)
		AudioServer.set_bus_volume_db(bus, 0)
		AudioServer.add_bus_effect(bus, recorder)
		recorder.set_recording_active(true)
		player.is_dead = false
		for i in 3:
			voice.next_voice_ms = 0
			voice.next_attempt_ms = 0
			PAIN.react(player, 15, 0)
			await create_timer(1.9).timeout
		recorder.set_recording_active(false)
		check(recorder.get_recording().save_to_wav("D:/geteco/artifacts/remains-pain-revision/pain-preview.wav") == OK, "Audible SFX mixer preview saved")
		AudioServer.remove_bus_effect(bus, slot)
	world.queue_free()
	await process_frame
	await process_frame
	check(get_nodes_in_group("pain_reaction_voices").is_empty(), "Scene teardown removes voices")
	print("PAIN_REACTIONS failures=", failures)
	quit(0 if failures == 0 else 1)
