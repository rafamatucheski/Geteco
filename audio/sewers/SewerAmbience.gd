extends Node
## One shared stream per occupied room; hidden rooms never retain a playing bed.
const BED := preload("res://audio/sewers/enclosed_flow.wav")
var channel: AudioStreamPlayer
var clock := 0.0

func _ready() -> void:
	name = "SewerAmbience"
	process_mode = Node.PROCESS_MODE_ALWAYS
	channel = AudioStreamPlayer.new()
	channel.name = "EnclosedFlow"
	var stream := BED.duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length() * stream.mix_rate)
	channel.stream = stream
	channel.volume_db = -8.0
	channel.bus = &"Ambient" if AudioServer.get_bus_index(&"Ambient") >= 0 else &"Master"
	add_child(channel)
	_sync()

func _process(delta: float) -> void:
	clock -= delta
	if clock > 0.0: return
	clock = .2
	_sync()

func _sync() -> void:
	var room := get_parent() as Node3D
	var audible := room != null and room.is_visible_in_tree() and room.can_process() and not get_tree().paused
	# Candidates are built while Dante is still on the street. Only the admitted
	# room owns a sound bed, including save restoration and canceled descents.
	if audible:
		var place := room.get_parent()
		var world := place.get_parent() if place != null else null
		var session: Variant = world.get("session") if world != null else null
		if session != null: audible = session.room == place and session.state.place_id == str(place.definition.id)
	if audible and not channel.playing: channel.play()
	elif not audible and channel.playing: channel.stop()

func _exit_tree() -> void:
	if is_instance_valid(channel): channel.stop()
