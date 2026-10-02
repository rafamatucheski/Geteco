extends Node3D
## Shared, bounded contact Foley. Public play keeps the legacy px/s interface.
const DIR := "res://audio/vehicle_crashes/"
const META := &"contact_audio_pool"
const MAX_VOICES := 12
const MAX_CONTACTS := 256
const MIN_SPEED := 0.75
const CONTACT_COOLDOWN := 0.45
const CONTACT_RELEASE := 0.12
const SOURCE_COOLDOWN := 0.07
const MAX_DISTANCE := 85.0
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const VEHICLE_KINDS := ["bumper", "heavy", "metal", "motorcycle", "solid"]
const MATERIAL_KINDS := ["glass", "wood", "flesh"]
static var _last_take: Dictionary = {}
static var _streams: Dictionary = {}
var voices: Array[AudioStreamPlayer3D] = []
var contacts: Dictionary = {}
var sources: Dictionary = {}
var bus_name := ""
var rng := RandomNumberGenerator.new()
var played_count := 0
var dropped_count := 0

## Hold all contact takes before playable collisions. No voices, bus or RNG
## are touched, and loader results are fetched only after their work ends.
static func prewarm(tree: SceneTree) -> void:
	for kind in VEHICLE_KINDS + MATERIAL_KINDS:
		var pending: Array[String] = []
		for take in (3 if kind in MATERIAL_KINDS else 4):
			var path := _sample_path(kind, take)
			if _streams.has(path): continue
			if ResourceLoader.has_cached(path) or not ResourceLoader.exists(path, "AudioStream"):
				_stream(path)
			elif ResourceLoader.load_threaded_request(path, "AudioStream") == OK:
				pending.append(path)
			else:
				_stream(path)
		for path in pending:
			while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				await tree.process_frame
			if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
				_streams[path] = ResourceLoader.load_threaded_get(path) as AudioStream
			else:
				_stream(path)
		await tree.process_frame

static func _sample_path(kind: String, take: int) -> String:
	return "res://assets/gameplay/audio/impact_%s_%d.wav" % [kind, take] if kind in MATERIAL_KINDS else "%s%s_%d.wav" % [DIR, kind, take]

static func _stream(path: String) -> AudioStream:
	if not _streams.has(path):
		var load_began := STALL_WORK.begin()
		_streams[path] = ResourceLoader.load(path, "AudioStream", ResourceLoader.CACHE_MODE_REUSE) as AudioStream if ResourceLoader.exists(path, "AudioStream") else null
		STALL_WORK.finish("contact_audio.load", load_began, {"path": path})
	return _streams[path] as AudioStream

func _ready() -> void:
	var stage := STALL_WORK.begin()
	set_process(false)
	set_physics_process(false)
	# Contact-only headroom; follows the existing SFX volume slider.
	bus_name = "ContactSFX_%d" % get_instance_id()
	AudioServer.add_bus()
	var bus_index := AudioServer.get_bus_count() - 1
	AudioServer.set_bus_name(bus_index, bus_name)
	AudioServer.set_bus_send(bus_index, "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master")
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -6.0
	AudioServer.add_bus_effect(bus_index, limiter)
	STALL_WORK.finish_slow("contact_audio.pool_bus",stage,5000,self)
	stage = STALL_WORK.begin()
	for index in MAX_VOICES:
		var voice := AudioStreamPlayer3D.new()
		voice.bus = bus_name
		voice.unit_size = 32.0 # Isometric camera listener stays ~36 m above the street.
		voice.max_distance = MAX_DISTANCE
		voice.max_db = 0.0
		add_child(voice)
		voices.append(voice)
	STALL_WORK.finish_slow("contact_audio.pool_voices",stage,5000,self)

func _exit_tree() -> void:
	for voice in voices: voice.stop()
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index >= 0: AudioServer.remove_bus(bus_index)
	contacts.clear()
	sources.clear()

static func pool(context: Node3D) -> Node3D:
	if not is_instance_valid(context) or not context.is_inside_tree(): return null
	var world := context.get_parent()
	if world == null: return null
	var existing = world.get_meta(META) if world.has_meta(META) else null
	if existing is WeakRef:
		var live = existing.get_ref()
		if is_instance_valid(live): return live
	var stage := STALL_WORK.begin()
	var director = load("res://audio/VehicleCrashAudio.gd").new()
	STALL_WORK.finish_slow("contact_audio.pool_script",stage,5000,context)
	director.name = "ContactAudio"
	stage = STALL_WORK.begin()
	world.add_child(director)
	STALL_WORK.finish_slow("contact_audio.pool_attach",stage,5000,context)
	world.set_meta(META, weakref(director))
	return director

static func contact_kind(target: Object, speed: float, motorcycle: bool) -> String:
	var node := target as Node
	for depth in 5:
		if not is_instance_valid(node): break
		var material := str(node.get_meta("impact_material", "")).to_lower()
		if material in ["flesh", "wood", "glass"]: return material
		if "dead" in node and node is CharacterBody3D: return "flesh"
		if motorcycle: return "motorcycle"
		if material == "metal" or node.is_in_group("drivable"): return "metal"
		var label := str(node.name).to_lower()
		if "tree" in label or "wood" in label or "crate" in label: return "wood"
		if "rail" in label or "container" in label or "fence" in label or "pole" in label: return "metal"
		if "glass" in label: return "glass"
		if material == "concrete": break
		node = node.get_parent()
	return "motorcycle" if motorcycle else ("bumper" if speed < 115.0 else ("heavy" if speed > 290.0 else "solid"))

static func play(p_owner: CharacterBody3D, target: Object, point: Vector3, speed: float) -> void:
	play_contact(p_owner, target, point, speed / 16.0)

static func play_contact(context: Node3D, target: Object, point: Vector3, speed: float, kind := "", key := "") -> bool:
	if not is_finite(speed) or speed < MIN_SPEED or not point.is_finite(): return false
	if not is_instance_valid(context) or not context.is_inside_tree(): return false
	var camera := context.get_viewport().get_camera_3d()
	if camera != null and camera.global_position.distance_squared_to(point) > MAX_DISTANCE * MAX_DISTANCE: return false
	var motorcycle := str(context.get("archetype")).begins_with("bike_") if "archetype" in context else false
	if is_instance_valid(target) and "archetype" in target: motorcycle = motorcycle or str(target.get("archetype")).begins_with("bike_")
	if kind.is_empty(): kind = contact_kind(target, speed * 16.0, motorcycle)
	var source_id := context.get_instance_id()
	if key.is_empty():
		if is_instance_valid(target):
			var target_id := target.get_instance_id()
			key = "%d|%d" % [mini(source_id, target_id), maxi(source_id, target_id)]
		else: key = "%d|%s" % [source_id, str(Vector3i((point * 2.0).round()))]
	var director = pool(context)
	return director.emit_contact(source_id, key, point, speed, kind) if director != null else false

func emit_contact(source_id: int, key: String, point: Vector3, speed: float, kind: String) -> bool:
	var now := float(Engine.get_physics_frames()) / Engine.physics_ticks_per_second
	var previous: Dictionary = contacts.get(key, {})
	var held := not previous.is_empty() and now - float(previous.seen) < CONTACT_RELEASE
	var last_play := float(previous.get("played", -1000.0))
	contacts[key] = {"seen": now, "played": last_play}
	if contacts.size() > MAX_CONTACTS:
		for old_key in contacts.keys():
			if now - float(contacts[old_key].seen) > CONTACT_COOLDOWN: contacts.erase(old_key)
		while contacts.size() > MAX_CONTACTS: contacts.erase(contacts.keys()[0])
	# Refreshing seen on rejected contacts silences sustained pressure/scraping.
	if held or now - last_play < CONTACT_COOLDOWN: return false
	if now - float(sources.get(source_id, -1000.0)) < SOURCE_COOLDOWN: return false
	if sources.size() > MAX_CONTACTS:
		for old_source in sources.keys():
			if now - float(sources[old_source]) > CONTACT_COOLDOWN: sources.erase(old_source)
	var volume := lerpf(-19.0, -3.0, clampf((speed - MIN_SPEED) / 17.0, 0.0, 1.0))
	var chosen: AudioStreamPlayer3D
	for voice in voices:
		if not voice.playing:
			chosen = voice
			break
	if chosen == null:
		# Do not cut an equally loud crash tail to make room for another impact.
		for voice in voices:
			if voice.volume_db + 3.0 < volume and (chosen == null or voice.volume_db < chosen.volume_db): chosen = voice
	if chosen == null:
		dropped_count += 1
		return false
	var count := 3 if kind in ["glass", "wood", "flesh"] else 4
	var take := (int(_last_take.get(kind, -1)) + rng.randi_range(1, count - 1)) % count
	var stream := _stream(_sample_path(kind, take))
	if stream == null: return false
	_last_take[kind] = take
	contacts[key].played = now
	sources[source_id] = now
	var stage := STALL_WORK.begin()
	chosen.stop()
	STALL_WORK.finish_slow("contact_audio.stop",stage,5000,self)
	stage = STALL_WORK.begin()
	chosen.stream = stream
	chosen.global_position = point
	chosen.volume_db = volume
	chosen.pitch_scale = rng.randf_range(0.96, 1.04)
	STALL_WORK.finish_slow("contact_audio.configure_voice",stage,5000,self)
	stage = STALL_WORK.begin()
	chosen.play()
	STALL_WORK.finish_slow("contact_audio.play",stage,5000,self)
	played_count += 1
	return true
