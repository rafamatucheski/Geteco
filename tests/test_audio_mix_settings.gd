extends SceneTree
## Independent live sliders, silence, migration, save/cancel/defaults and routing.
## Does not approve perceptual balance or rendered performance.
const SETTINGS := preload("res://runtime/Settings.gd")
const DESIGN := preload("res://audio/EngineDesignVoice.gd")
const DESERT := preload("res://audio/desert_cars/DesertCarAudio.gd")
const ROAD := preload("res://audio/VehicleRoadAudio.gd")
const CRASH := preload("res://audio/VehicleCrashAudio.gd")
const FIREFLY := preload("res://audio/FireflyBank.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func levels() -> Dictionary:
	var result := {}
	for bus in SETTINGS.AUDIO_CHANNELS.values():
		var idx := AudioServer.get_bus_index(bus)
		result[bus] = [AudioServer.get_bus_volume_db(idx), AudioServer.is_bus_mute(idx)]
	return result

func run() -> void:
	var path := SETTINGS.default_path()
	if path.begins_with("user://"):
		push_error("Use --isolated-save-root to protect player settings")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var settings := root.get_node("V2Settings")
	var bus_count := AudioServer.bus_count
	var effects := {}
	for bus in SETTINGS.AUDIO_CHANNELS.values():
		var idx := AudioServer.get_bus_index(bus)
		check(idx >= 0, "category exists: " + bus)
		if idx < 0: quit(1); return
		if bus != "Master": check(AudioServer.get_bus_send(idx) == &"Master", bus + " is independent of other category sliders")
		effects[bus] = AudioServer.get_bus_effect_count(idx)
	settings._setup_audio_buses()
	check(AudioServer.bus_count == bus_count, "setup does not duplicate buses")
	for bus in effects:
		check(AudioServer.get_bus_effect_count(AudioServer.get_bus_index(bus)) == effects[bus], "setup does not duplicate gain or ducking: " + bus)
	for bus in ["Vehicles", "Radio", "Music", "Ambient"]:
		var idx := AudioServer.get_bus_index(bus)
		var duck: AudioEffectCompressor
		for i in AudioServer.get_bus_effect_count(idx):
			var effect := AudioServer.get_bus_effect(idx, i)
			if effect is AudioEffectCompressor: duck = effect
		check(duck != null and duck.sidechain == &"Dialogue" and duck.release_ms >= 300.0, bus + " yields to actual speech with smooth recovery")
		if bus == "Vehicles":
			check(duck != null and duck.mix < .7 and is_zero_approx(duck.gain), "engine retains dry body and has no extra +10 dB gain")
	check(AudioServer.get_bus_index("Dialogue") > AudioServer.get_bus_index("Vehicles"), "speech processes before sidechain destinations")

	var menu: Control = load("res://ui/SettingsMenu.tscn").instantiate()
	root.add_child(menu)
	menu.size = Vector2(1280, 720)
	await process_frame
	menu.open()
	menu._select_tab(1)
	if DisplayServer.get_name() != "headless":
		for argument in OS.get_cmdline_user_args():
			if not argument.begins_with("--audio-mix-capture="): continue
			await process_frame
			await RenderingServer.frame_post_draw
			var capture_path := argument.trim_prefix("--audio-mix-capture=")
			check(root.get_texture().get_image().save_png(capture_path) == OK, "audio options capture saved")
	var original: Dictionary = menu.snapshot.duplicate(true)
	for key in SETTINGS.AUDIO_CHANNELS:
		check(menu._widgets.has(key), "slider present: " + key)
		var before := levels()
		var slider: HSlider = menu._widgets[key].get_meta("slider")
		slider.value = .37
		var bus: String = SETTINGS.AUDIO_CHANNELS[key]
		var idx := AudioServer.get_bus_index(bus)
		check(is_equal_approx(float(settings.get(key)), .37) and is_equal_approx(AudioServer.get_bus_volume_db(idx), linear_to_db(.37)+(preload("res://gameplay/CombatAudio.gd").WEAPON_TRIM_DB if bus == "Weapons" else 0.0)), "live slider applies: " + key)
		for other in before:
			if other != bus: check(levels()[other] == before[other], key + " preserves " + other)
		slider.value = 0.0
		check(AudioServer.is_bus_mute(idx), "zero fully silences: " + key)
		slider.value = .63
		check(not AudioServer.is_bus_mute(idx), "raising slider restores sound: " + key)
	menu.close()
	for key in SETTINGS.AUDIO_CHANNELS:
		check(is_equal_approx(float(settings.get(key)), float(original[key])), "cancel restores: " + key)
	menu.show()
	menu.open()
	menu._select_tab(1)
	menu._restore_tab_defaults()
	for key in ["vehicle_volume", "dialogue_volume", "ui_volume"]:
		check(is_equal_approx(float(settings.get(key)), 1.0), "defaults restore: " + key)
	check(is_equal_approx(settings.radio_volume, .8), "radio default is independent of music")
	check(is_equal_approx(settings.weapon_volume,.7),"weapons default is independent and quieter")
	for key in SETTINGS.AUDIO_CHANNELS:
		(menu._widgets[key].get_meta("slider") as HSlider).value = .41 + SETTINGS.AUDIO_CHANNELS.keys().find(key) * .05
	var committed := {}
	for key in SETTINGS.AUDIO_CHANNELS: committed[key] = settings.get(key)
	menu._save()
	check(FileAccess.file_exists(path), "Save writes isolated config")
	for key in SETTINGS.AUDIO_CHANNELS: settings.set(key, .1)
	check(settings.load_settings(path) == OK, "saved audio reloads")
	for key in committed: check(is_equal_approx(float(settings.get(key)), float(committed[key])), "save roundtrip: " + key)
	# Legacy preferences seed new categories without changing the old choices.
	var legacy := ConfigFile.new()
	legacy.set_value("audio", "sfx_volume", .42)
	legacy.set_value("audio", "music_volume", .27)
	var legacy_path := path.get_base_dir().path_join("legacy-audio.cfg")
	check(legacy.save(legacy_path) == OK and settings.load_settings(legacy_path) == OK, "legacy config loads")
	check(is_equal_approx(settings.vehicle_volume, .42) and is_equal_approx(settings.dialogue_volume, .42) and is_equal_approx(settings.ui_volume, .42), "legacy effects preference seeds independent vehicle/voice/UI controls")
	check(is_equal_approx(settings.radio_volume, .27), "legacy music preference seeds independent radio")
	settings.load_settings(path)
	settings.apply_settings()
	menu.queue_free()

	var stage := Node3D.new()
	root.add_child(stage)
	var design := DESIGN.new()
	stage.add_child(design)
	check(design._player("RoutingProbe").bus == &"Vehicles", "authored engine voices use Vehicles")
	var desert := DESERT.new()
	stage.add_child(desert)
	check(desert._player("RoutingProbe", -20).bus == &"Vehicles", "dedicated desert engine uses Vehicles")
	var road := ROAD.new()
	stage.add_child(road)
	check(road.voices.values().all(func(p): return p.bus == &"Vehicles"), "every tire surface follows Vehicles")
	var crash := CRASH.new()
	stage.add_child(crash)
	check(AudioServer.get_bus_send(AudioServer.get_bus_index(crash.bus_name)) == &"Vehicles", "vehicle collision limiter follows Vehicles")
	check(AudioServer.get_bus_send(AudioServer.get_bus_index(crash.body_bus_name)) == &"SFX", "body impacts retain Effects independently of Vehicles")
	check(preload("res://ui/MenuAudio.gd").get_sfx_bus_name() == "UI", "menu clicks use Interface")
	check(FIREFLY.bus_name() == &"SFX" and FIREFLY.bus_name(&"Vehicles") == &"Vehicles", "vehicle one-shots do not reroute combat")
	var actor := Node3D.new()
	stage.add_child(actor)
	var spatial_voice := preload("res://audio/ActorDialogueVoice.gd").ActorPlayer.new()
	actor.add_child(spatial_voice)
	check(spatial_voice.bus == &"Dialogue", "spatial actor speech follows Voices")
	var caption := Label.new()
	stage.add_child(caption)
	var caption_voice := preload("res://audio/VisibleDialogueVoice.gd").SurfacePlayer.new()
	caption.add_child(caption_voice)
	check(caption_voice.bus == &"Dialogue", "caption-owned speech follows Voices")
	var ferry := preload("res://cutscenes/opening/ferry/FerryVoiceTrack.gd").new()
	stage.add_child(ferry)
	check(ferry.player.bus == &"Dialogue", "cinematic speech follows Voices")
	var phone_bus := ferry._phone_bus()
	check(AudioServer.get_bus_send(AudioServer.get_bus_index(phone_bus)) == &"Dialogue", "filtered phone speech follows Voices")
	stage.queue_free()
	await process_frame
	check(AudioServer.bus_count == bus_count, "unloading contact pools releases both buses")
	print("AUDIO_MIX_SETTINGS checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
