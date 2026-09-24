extends RefCounted
## V1 recorded crash Foley, positioned in the native 3D world.
const DIR := "res://audio/vehicle_crashes/"
const VEHICLE := preload("res://scripts/Vehicle.gd")
static var _last_take: Dictionary = {}
static var _streams: Dictionary = {}

static func play(owner: CharacterBody3D, target: Object, point: Vector3, speed: float) -> void:
	var now := Time.get_ticks_msec()
	if now - int(owner.get_meta("crash_audio_ms", -999999)) < 280: return
	if is_instance_valid(target) and target is Node and now - int(target.get_meta("crash_audio_ms", -999999)) < 100: return
	var motorcycle := str(owner.archetype).begins_with("bike_")
	if target is VEHICLE:
		motorcycle = motorcycle or str(target.get("archetype")).begins_with("bike_")
	var kind := "motorcycle" if motorcycle else ("bumper" if speed < 115.0 else ("heavy" if speed > 290.0 else ("metal" if target is VEHICLE else "solid")))
	var take := (int(_last_take.get(kind, -1)) + randi_range(1, 3)) % 4
	var path := "%s%s_%d.wav" % [DIR, kind, take]
	if not _streams.has(path): _streams[path] = load(path) as AudioStreamWAV
	var stream := _streams[path] as AudioStreamWAV
	if stream == null: return
	_last_take[kind] = take
	owner.set_meta("crash_audio_ms", now)
	if target is Node: target.set_meta("crash_audio_ms", now)
	var voice := AudioStreamPlayer3D.new()
	voice.stream = stream
	voice.max_distance = 53.0
	voice.unit_size = 14.0
	voice.volume_db = lerpf(-17.0, -3.5, clampf(speed / 500.0, 0.0, 1.0))
	voice.pitch_scale = randf_range(0.985, 1.015)
	voice.bus = &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"
	owner.get_parent().add_child(voice)
	voice.global_position = point
	voice.finished.connect(voice.queue_free)
	voice.play()
