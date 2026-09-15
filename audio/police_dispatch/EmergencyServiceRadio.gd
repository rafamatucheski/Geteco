extends RefCounted

static var _next_message := {}
static var _streams := {}

static func play_at(actor: Node2D, event: StringName) -> void:
	if not is_instance_valid(actor) or not actor.is_inside_tree(): return
	if event not in [&"fire_dispatch", &"fire_clear", &"fire_blocked", &"medical_dispatch", &"medical_admission"]: return
	var service := "fire" if String(event).begins_with("fire") else "medical"
	var now := Time.get_ticks_msec()
	if now < int(_next_message.get(service, 0)): return
	_next_message[service] = now + 20000
	if not _streams.has(event): _streams[event] = load("res://audio/police_dispatch/%s.wav" % event)
	if _streams[event] == null: return
	var speaker := AudioStreamPlayer2D.new()
	speaker.stream = _streams[event]
	speaker.bus = "SFX"
	speaker.volume_db = -16
	speaker.max_distance = 650
	actor.add_child(speaker)
	speaker.finished.connect(speaker.queue_free)
	speaker.play()
