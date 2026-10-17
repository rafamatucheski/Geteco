extends SceneTree
## Real fleet, authored WAV resources and native playback nodes. This is a
## functional contract test; headless results do not approve sound quality/FPS.
const CATALOG := preload("res://audio/FleetEngineDesign.gd")
const BANKS := preload("res://audio/EngineDesignBanks.gd")
const VOICE := preload("res://audio/EngineDesignVoice.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const LEGACY := preload("res://audio/VehicleEngineProfile.gd")
const DESERT := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const MINING := preload("res://gameplay/mining/MiningFleet.gd")
var checks := 0
var failures: Array[String] = []
var inventory: Array[Dictionary] = []

func _initialize() -> void:
	create_timer(180.0).timeout.connect(func(): push_error("ENGINE_DESIGN_CONTRACT timeout"); quit(2))
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func actual_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in FLEET.all(): ids.append(str(id))
	for id in DESERT.IDS + MINING.IDS + ["biarticulated_510", "armored_truck", "desert_cargo_truck", "jessica_jetta_gli", "digo_amarok_2014", "digo_gol_1993", "cobra_boss_ironback"]:
		if id not in ids: ids.append(str(id))
	ids.sort()
	return ids

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or not BANKS.enabled():
		push_error("Engine design contract requires --no-save and the new mixer enabled")
		quit(2)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://audio/engine_design/manifest.json"))
	check(parsed is Dictionary and parsed.get("profiles") is Array, "authored manifest is available")
	if not failures.is_empty(): quit(1); return
	var manifest_profiles := {}
	for item in parsed.profiles: manifest_profiles[str(item.id)] = item
	var representatives := {}
	for id in actual_ids():
		var spec: Dictionary = FLEET.spec(id)
		var profile := CATALOG.profile(id)
		var dedicated := CATALOG.dedicated_profile(id)
		check(not spec.is_empty(), "actual fleet entry exists: " + id)
		check(not profile.is_empty() or not dedicated.is_empty(), "actual vehicle has authored or intentional dedicated audio: " + id)
		check(profile.is_empty() or dedicated.is_empty(), "vehicle is not assigned two audio systems: " + id)
		if not profile.is_empty():
			check(CATALOG.has_profile(profile) and manifest_profiles.has(profile), "assigned profile has authored files: " + id)
			if not representatives.has(profile): representatives[profile] = id
		else:
			check(LEGACY.bank_family(id) == dedicated, "dedicated electric/tank/motorcycle sound remains correct: " + id)
		inventory.append({"id": id, "profile": profile, "dedicated": dedicated})
	# Compatibility vehicles are real saved/controller IDs even when absent from
	# FleetCatalog.all(). They must remain explicit, not fall through to a hatch.
	for pair in [["maciota_m8", "v8_twin_turbo"], ["maciota_350z", "vq35_v6_na"], ["supra_a80", "jz2_i6_turbo"], ["cargo_flatbed_truck", "truck_v12_diesel"]]:
		check(CATALOG.profile(pair[0]) == pair[1], "specific powertrain identity: " + pair[0])
		if not representatives.has(pair[1]): representatives[pair[1]] = pair[0]
	check(CATALOG.profile("unknown_vehicle_id").is_empty(), "unknown archetype is not silently mapped to a combustion engine")
	check(BANKS.bank("unknown_profile").is_empty(), "unknown bank does not produce invalid streams")
	await BANKS.prewarm(self)
	var host := Node3D.new()
	root.add_child(host)
	var voice := VOICE.new()
	host.add_child(voice)
	for profile in CATALOG.all_profile_ids():
		check(manifest_profiles.has(profile), "runtime metadata appears in authoring manifest: " + profile)
		if not manifest_profiles.has(profile): continue
		var item: Dictionary = manifest_profiles[profile]
		var meta: Dictionary = CATALOG.metadata(profile)
		check(PackedFloat64Array(CATALOG.rpm_bands(profile)) == PackedFloat64Array(item.rpm_bands), "runtime RPM anchors match actual authored bank: " + profile)
		for field in ["cylinders", "fuel", "turbo", "bypass_valve"]:
			check(meta.get(field) == item.get(field), "runtime metadata matches authoring " + profile + "/" + field)
		check(BANKS.is_ready(profile), "complete profile published by prewarm: " + profile)
		for state in ["loaded", "coast"]:
			var bank: Array[AudioStreamWAV] = BANKS.bank(profile, state)
			var again: Array[AudioStreamWAV] = BANKS.bank(profile, state)
			check(bank.size() == 7, "seven real runtime bands: " + profile + "/" + state)
			if bank.size() != 7: continue
			for index in 7:
				var stream := bank[index]
				check(is_same(stream, again[index]), "immutable stream shared by repeated consumers: %s/%s/%d" % [profile, state, index])
				check(stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == 22050 and not stream.stereo and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "runtime stream format/loop: %s/%s/%d" % [profile, state, index])
				check(stream.loop_end == int(item.band_frames[index]), "runtime excludes guard and retains authored duration: %s/%s/%d" % [profile, state, index])
				check(roundi(stream.get_length()*stream.mix_rate) == int(item.band_frames[index])+8, "authored samples loaded completely: %s/%s/%d" % [profile, state, index])
		check((BANKS.effect(profile, "turbo_spool") != null) == bool(meta.turbo), "turbo spool follows aspiration: " + profile)
		check((BANKS.effect(profile, "bypass_release") != null) == bool(meta.bypass_valve), "bypass absent from diesel and aspirated profiles: " + profile)
		check(representatives.has(profile), "profile is assigned to a real or compatibility vehicle: " + profile)
		if not representatives.has(profile): continue
		check(voice.configure(representatives[profile]), "real voice binds prepared profile: " + profile)
		if not BANKS.is_ready(profile): continue
		exercise_voice(voice, profile, meta)
	for id in CATALOG.DEDICATED_PROFILES:
		check(not voice.configure(id), "dedicated vehicle does not start authored combustion voice: " + id)
		check(voice.snapshot().motor_voices == 0, "legacy selection silences previous designed voice: " + id)
	var refs: Array[WeakRef] = []
	for node in voice.get_children():
		if node.has_method("has_stream_playback") and node.has_stream_playback(): refs.append(weakref(node.get_stream_playback()))
	host.free()
	var drain_deadline := Time.get_ticks_usec()+2000000
	while refs.any(func(ref): return ref.get_ref() != null) and Time.get_ticks_usec() < drain_deadline:
		await process_frame
		OS.delay_usec(1000)
	check(refs.all(func(ref): return ref.get_ref() == null), "native playbacks released after voice owner exits")
	print("ENGINE_DESIGN_INVENTORY ", JSON.stringify(inventory))
	print("ENGINE_DESIGN_CONTRACT vehicles=", inventory.size(), " profiles=", manifest_profiles.size(), " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func exercise_voice(voice: Node3D, profile: String, meta: Dictionary) -> void:
	var rpm: Array = CATALOG.rpm_bands(profile)
	voice.stop()
	voice.update_mix(float(rpm[0]), 0.0, .1, -18.0, Vector3.ZERO, true)
	var state: Dictionary = voice.snapshot()
	check(state.motor_voices > 0 and state.playing_by_state[0] > 0 and state.playing_by_state[1] == 0, "idle still combusts with released pedal: " + profile)
	var middle := sqrt(float(rpm[4])*float(rpm[5]))
	for tick in 20: voice.update_mix(middle, .5, .1, -18.0, Vector3.ZERO, true)
	state = voice.snapshot()
	check(state.motor_voices == 4 and state.playing_by_state == [2, 2], "partial throttle crossfades two RPM bands and two loads: " + profile)
	for tick in 20: voice.update_mix(middle, 0.0, .1, -18.0, Vector3.ZERO, true)
	state = voice.snapshot()
	check(state.coast_weight > .99 and state.playing_by_state[1] == 2, "release at speed reaches authored coast bank: " + profile)
	for node in voice.get_children():
		if node is AudioStreamPlayer3D and node.playing:
			check(node.attenuation_model == AudioStreamPlayer3D.ATTENUATION_DISABLED, "newly activated coast/FX voices stay foreground: " + profile)
	var high := float(rpm[6])*.9
	for tick in 30: voice.update_mix(high, 1.0, .1, -18.0, Vector3.ZERO, true)
	state = voice.snapshot()
	check(state.spool_playing == bool(meta.turbo), "sustained high loaded RPM spools only a turbo: " + profile)
	voice.update_mix(high, .7, .1, -18.0, Vector3.ZERO, true, true, true)
	check(voice.snapshot().release_playing == bool(meta.bypass_valve), "loaded shift releases only an authored gasoline bypass: " + profile)
	voice.update_mix(high, 1.0, .1, -24.0, Vector3(2, 0, 0), false)
	state = voice.snapshot()
	check(not state.spool_playing and not state.release_playing, "background slot does not add foreground turbo effects: " + profile)
	check(state.motor_voices <= 4 and voice.get_child_count() <= 6, "bounded motor and effect nodes: " + profile)
	voice.stop()
	state = voice.snapshot()
	check(state.motor_voices == 0 and not state.spool_playing and not state.release_playing and not state.active, "stop silences every design layer: " + profile)
	voice.update_mix(middle, .5, .1, -18.0, Vector3.ZERO, true, false)
	check(voice.snapshot().motor_voices > 0 and not voice.snapshot().spool_playing, "restart restores motor with boost explicitly disabled: " + profile)
	voice.stop()
