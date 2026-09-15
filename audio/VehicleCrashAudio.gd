extends RefCounted
## Recorded crash Foley. See vehicle_crashes/SOURCES.json for origins and licenses.
const RATE := 44100
const SAMPLES := {
	"motorcycle": [
		preload("res://audio/vehicle_crashes/motorcycle_0.wav"),
		preload("res://audio/vehicle_crashes/motorcycle_1.wav"),
		preload("res://audio/vehicle_crashes/motorcycle_2.wav"),
		preload("res://audio/vehicle_crashes/motorcycle_3.wav"),
	],
	"bumper": [
		preload("res://audio/vehicle_crashes/bumper_0.wav"),
		preload("res://audio/vehicle_crashes/bumper_1.wav"),
		preload("res://audio/vehicle_crashes/bumper_2.wav"),
		preload("res://audio/vehicle_crashes/bumper_3.wav"),
	],
	"metal": [
		preload("res://audio/vehicle_crashes/metal_0.wav"),
		preload("res://audio/vehicle_crashes/metal_1.wav"),
		preload("res://audio/vehicle_crashes/metal_2.wav"),
		preload("res://audio/vehicle_crashes/metal_3.wav"),
	],
	"solid": [
		preload("res://audio/vehicle_crashes/solid_0.wav"),
		preload("res://audio/vehicle_crashes/solid_1.wav"),
		preload("res://audio/vehicle_crashes/solid_2.wav"),
		preload("res://audio/vehicle_crashes/solid_3.wav"),
	],
	"heavy": [
		preload("res://audio/vehicle_crashes/heavy_0.wav"),
		preload("res://audio/vehicle_crashes/heavy_1.wav"),
		preload("res://audio/vehicle_crashes/heavy_2.wav"),
		preload("res://audio/vehicle_crashes/heavy_3.wav"),
	],
}
static var _last_take: Dictionary = {}

static func family(speed: float, material: StringName, motorcycle_contact := false) -> String:
	if motorcycle_contact: return "motorcycle"
	if speed < 115.0: return "bumper"
	if speed > 290.0: return "heavy"
	return "metal" if material == &"metal" else "solid"

static func play(owner: Node2D, target: Node, position: Vector2, speed: float) -> void:
	var now := Time.get_ticks_msec()
	if now - int(owner.get_meta("crash_audio_ms", -999999)) < 280: return
	# Both vehicles can report the same physical contact in the same frame.
	if is_instance_valid(target) and now - int(target.get_meta("crash_audio_ms", -999999)) < 100: return
	owner.set_meta("crash_audio_ms", now)
	var material: StringName = preload("res://audio/combat/ImpactMaterial.gd").resolve(target)
	var motorcycle_contact := _is_motorcycle(owner) or _is_motorcycle(target)
	var kind := family(speed, material, motorcycle_contact)
	var take := (int(_last_take.get(kind, -1)) + randi_range(1, 3)) % 4
	_last_take[kind] = take
	var player := AudioStreamPlayer2D.new()
	player.stream = sound(kind, take)
	player.pitch_scale = randf_range(0.985, 1.015)
	player.volume_db = lerpf(-17.0, -3.5, clampf(speed / 500.0, 0.0, 1.0))
	player.max_distance = 850.0
	if AudioServer.get_bus_index("SFX") >= 0: player.bus = &"SFX"
	owner.get_parent().add_child(player)
	player.global_position = position
	player.finished.connect(player.queue_free)
	player.play()

static func sound(kind: String, take: int = 0) -> AudioStreamWAV:
	var variants: Array = SAMPLES.get(kind, SAMPLES["solid"])
	return variants[posmod(take, variants.size())]

static func _is_motorcycle(body: Node) -> bool:
	return is_instance_valid(body) and (body.is_in_group("motorcycle") or body.get_meta("vehicle_kind", "") == "motorcycle" or body.get("police_variant") == "motorcycle")
