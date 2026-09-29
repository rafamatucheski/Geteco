extends Node
## One occupied vehicle only. Reuses tire contact probes; five bounded, cached loops.
const SOURCES := {
	"hard": preload("res://audio/vehicle_fx/road.wav"),
	"grass": preload("res://audio/vehicle_fx/tire_grass.wav"),
	"dirt": preload("res://audio/vehicle_fx/tire_dirt.wav"),
	"snow": preload("res://audio/vehicle_fx/tire_snow.wav"),
	"wet": preload("res://audio/vehicle_fx/tire_wet.wav"),
}
static var streams: Dictionary = {}
var voices: Dictionary = {}
var vehicle: CharacterBody3D

func _ready() -> void:
	set_process(false)
	for kind in SOURCES:
		if not streams.has(kind):
			var stream := SOURCES[kind].duplicate() as AudioStreamWAV
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_end = roundi(stream.get_length() * stream.mix_rate) - (8 if kind == "hard" else 0)
			streams[kind] = stream
		var voice := AudioStreamPlayer.new()
		voice.name = "Tires_" + kind
		voice.bus = &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"
		voice.stream = streams[kind]
		voice.volume_linear = 0.0
		add_child(voice)
		voices[kind] = voice

func update_contacts(contacts: Array[Dictionary], speed: float, sliding: bool, delta: float) -> void:
	set_process(true)
	var weights := {"hard":0.0, "grass":0.0, "dirt":0.0, "snow":0.0, "wet":0.0}
	for contact in contacts:
		if contact.is_empty(): continue
		var kind := str(contact.kind)
		if kind == "water": kind = "wet"
		if not weights.has(kind): kind = "hard"
		weights[kind] += .5
		if bool(contact.wet) and kind != "wet":
			weights[kind] -= .2
			weights.wet += .2
	var moving := smoothstep(.3, 8.0, absf(speed))
	for kind in voices:
		var voice: AudioStreamPlayer = voices[kind]
		var level := -26.0 if kind == "hard" else -20.0
		var target := float(weights[kind]) * moving * db_to_linear(level + (3.0 if sliding else 0.0))
		voice.volume_linear = lerpf(voice.volume_linear, target, 1.0 - exp(-delta * 14.0))
		voice.pitch_scale = clampf(.72 + absf(speed) * .035, .72, 1.6)
		if voice.volume_linear < .0005:
			voice.stop()
		elif not voice.playing:
			voice.play()

func stop() -> void:
	set_process(false)
	for voice in voices.values():
		voice.stop()
		voice.volume_linear = 0.0

func _process(_delta: float) -> void:
	# A garage/streaming transition can freeze vehicle physics before its next tick.
	if not is_instance_valid(vehicle) or not vehicle.controlled or not vehicle.is_visible_in_tree() or not vehicle.is_physics_processing():
		stop()
