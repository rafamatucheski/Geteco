extends SceneTree
const BANK := preload("res://audio/combat/CombatAudioBank.gd")
const BULLET := preload("res://Bullet.tscn")
const WEATHER := preload("res://DayNightWeatherManager.gd")
var failures := 0

class Target:
	extends StaticBody2D
	var hits := 0
	var lost_hp := 0
	func take_damage(amount: int, _from_player: bool = false) -> void:
		hits += 1
		lost_hp += amount

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var ambient := root.get_node_or_null("CityAudioManager")
	if ambient:
		ambient.set_process(false)
		for child in ambient.get_children():
			if child is AudioStreamPlayer: child.stop()
	for kind in ["pistol", "magnum", "smg", "ak47", "m4a1", "shotgun", "sawed_off", "hunting_rifle"]:
		var sound := ProceduralAudio.get_gunshot_stream(kind) as AudioStreamRandomizer
		check(sound != null and sound == BANK.sound(kind), "Existing weapon API reaches authored palette: " + kind)
		check(sound.streams_count == 5, "Five takes for " + kind)
		check(sound.playback_mode == AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS, "No consecutive identical takes")
		check(sound.get_stream(0) != sound.get_stream(1), "Distinct sample resources")
	var resolver := preload("res://audio/combat/ImpactMaterial.gd")
	for group in [&"paramedic", &"firefighter", &"mortician", &"police_officer", &"pedestrian"]:
		var actor := Node.new()
		actor.add_to_group(group)
		root.add_child(actor)
		check(resolver.resolve(actor) == &"flesh", "Human contact includes " + group)
		actor.free()
	var prop := Node.new()
	prop.set_meta("impact_material", &"wood")
	var child_collider := StaticBody2D.new()
	prop.add_child(child_collider)
	check(resolver.resolve(child_collider) == &"wood", "Child collider inherits authored surface")
	child_collider.set_meta("impact_material", &"metal")
	check(resolver.resolve(child_collider) == &"metal", "Specific collider surface overrides parent")
	prop.free()
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	for material in [&"concrete", &"metal", &"flesh", &"wood", &"glass"]:
		var target := Target.new()
		target.position = Vector2(150, 100)
		target.collision_layer = 1
		if material == &"metal": target.add_to_group("metal_prop")
		if material == &"flesh": target.add_to_group("gang_member")
		target.set_meta("impact_material", material)
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(16, 80)
		shape.shape = box
		target.add_child(shape)
		world.add_child(target)
		await physics_frame
		var bullet := BULLET.instantiate()
		bullet.position = Vector2(30, 100)
		bullet.direction = Vector2.RIGHT
		bullet.damage = 15
		world.add_child(bullet)
		for i in 15: await physics_frame
		var pool := world.get_node_or_null("CombatImpactAudio")
		check(pool != null, "Physical projectile collision creates impact audio")
		if pool:
			check(pool._recent.back().material == material, "Correct material from physical collision: " + material)
		check(target.hits == 1 and target.lost_hp == 15, "Feedback never duplicates or changes bullet damage")
		target.queue_free()
		await physics_frame
	var pool := world.get_node("CombatImpactAudio")
	var events: int = pool.events_played
	for i in 12:
		pool.play_impact(Vector2(500, 500), &"metal")
	check(pool.events_played == events + 1, "Same-frame pellets share one nearby impact sound")
	for i in 80:
		pool.play_impact(Vector2(i * 45, 600), &"concrete")
	check(pool.get_child_count() == 10 and pool._recent.size() <= 32, "Impacts have bounded voices and history")
	for voice in pool.voices:
		check(voice.bus == &"SFX", "Impact audio respects SFX settings")
	# Exercise the production Player shooting path, not just the bank in isolation.
	var player: Node = load("res://Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	world.add_child(player)
	await process_frame
	player.set_physics_process(false)
	for kind in ["pistol", "magnum", "smg", "ak47", "m4a1", "shotgun", "sawed_off"]:
		player.active_weapon_id = kind
		player.weapon_ammo[kind] = {"clip": 10, "reserve": 20}
		player._shoot_towards(player.global_position + Vector2(400, 0))
		check(player.weapon_ammo[kind].clip == 9, "Real shooting consumes one round: " + kind)
		var heard := false
		for child in player.get_children():
			if child is AudioStreamPlayer2D and child.stream == BANK.sound(kind):
				heard = child.playing and child.bus == &"SFX"
		check(heard, "Real Player plays the new shot through SFX: " + kind)
	if "combat-only" in OS.get_cmdline_user_args():
		world.queue_free()
		await create_timer(0.3).timeout
		print("COMBAT_AUDIO_ONLY failures=", failures)
		quit(0 if failures == 0 else 1)
		return
	var weather := WEATHER.new()
	weather.is_dynamic_time = false
	world.add_child(weather)
	weather.set_rain_intensity(0.25)
	weather.set_weather(1)
	var light_drops: int = weather.rain_particles.amount
	weather.set_weather(2)
	check(weather.rain_particles.amount > light_drops * 2 and weather.rain_particles.amount <= 620, "Strong rain is visibly denser with a fixed upper bound")
	check(weather.rain_particles.texture != null and weather.splash_particles.texture != null, "Rain streaks and splash textures are installed")
	check(weather.weather_audio.RAIN_TRIM_DB == -16.0, "Rain stays 10 dB below the first approved palette")
	weather.set_interior_mode(true)
	check(not weather.rain_particles.emitting and not weather.splash_particles.emitting, "No strong-rain particles indoors")
	world.queue_free()
	await create_timer(0.3).timeout
	print("COMBAT_AUDIO failures=", failures)
	quit(0 if failures == 0 else 1)
