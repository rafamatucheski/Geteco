extends RefCounted
## Event-driven spatial speech: one player per body, at most three live takes.
const VOICE := preload("res://audio/ExpressiveVoice.gd")
const BANK := preload("res://audio/DirectedVoiceBank.gd")
const PLAYER_NAME := "ActorDialogueVoice"
static var _active: Array[WeakRef] = []
static var _listener_ref: WeakRef
static var _listener_scene_id := 0

class ActorPlayer extends AudioStreamPlayer3D:
	var source := ""
	var binding: Dictionary = {}
	var surface: WeakRef
	var _check_left := 0.0
	var _death_fields: Array[String] = []
	var _listener: WeakRef
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_PAUSABLE
		bus = &"Dialogue" if AudioServer.get_bus_index("Dialogue") >= 0 else &"Master"
		# The isometric camera sits ~36m above/behind its focus. It supplies pan,
		# while audibility belongs to the player's position, as in combat audio.
		attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		max_distance = 0.0
		panning_strength = .6
		position.y = 1.55
		get_parent().tree_exiting.connect(silence)
		finished.connect(silence)
		for property in get_parent().get_property_list():
			if property.name in ["dead", "is_dead", "health", "hp"]: _death_fields.append(str(property.name))
		var settings := get_node_or_null("/root/V2Settings")
		if settings != null:
			settings.voice_language_changed.connect(func(_value):
				if playing or _visible_surface(): refresh(playing))
			settings.text_language_changed.connect(func(_value):
				if _visible_surface(): refresh(false))
		set_process(false)
	func _process(delta: float) -> void:
		_check_left -= delta
		if _check_left > 0: return
		_check_left = .25
		var actor := get_parent() as Node3D
		if not actor.is_visible_in_tree() or actor.is_queued_for_deletion() or _dead(actor) or (surface != null and not _visible_surface()):
			silence()
			return
		var gain := _hearing_gain()
		if gain <= -60.0: silence()
		else: volume_db = VOICE.playback_volume(stream) + gain
	func _hearing_gain() -> float:
		var listener := _listener.get_ref() as Node3D if _listener != null else null
		if not is_instance_valid(listener): return 0.0
		var distance := Vector2(global_position.x - listener.global_position.x, global_position.z - listener.global_position.z).length()
		var fraction := 1.0 - distance / 45.0
		return linear_to_db(fraction) if fraction > .001 else -80.0
	func _dead(actor: Node) -> bool:
		for field in _death_fields:
			if field in ["dead", "is_dead"] and actor.get(field) == true: return true
			if field in ["health", "hp"]:
				var value: Variant = actor.get(field)
				if (value is float or value is int) and value <= 0: return true
		return false
	func silence() -> void:
		stop()
		stream = null
		set_process(false)
	func _visible_surface() -> bool:
		var node := surface.get_ref() as Node if surface != null else null
		return is_instance_valid(node) and (not node.has_method("is_visible_in_tree") or node.is_visible_in_tree())
	func _surface_visibility_changed() -> void:
		if not _visible_surface(): silence()
	func set_surface(node: Node) -> void:
		var old := surface.get_ref() as Node if surface != null else null
		if is_instance_valid(old):
			if old.tree_exiting.is_connected(silence): old.tree_exiting.disconnect(silence)
			if old.has_signal("visibility_changed") and old.visibility_changed.is_connected(_surface_visibility_changed):
				old.visibility_changed.disconnect(_surface_visibility_changed)
		surface = weakref(node) if is_instance_valid(node) else null
		if is_instance_valid(node):
			node.tree_exiting.connect(silence)
			if node.has_signal("visibility_changed"): node.visibility_changed.connect(_surface_visibility_changed)
	func refresh(restart: bool) -> Dictionary:
		var shown := VOICE.presentation(source, str(binding.persona), "", "", str(binding.character_id), str(binding.get("section", "")))
		if surface != null:
			var label := surface.get_ref() as Node
			if is_instance_valid(label):
				if label is Label or label is Label3D: label.text = str(shown.message)
				elif label.has_method("set_voice_message"): label.set_voice_message(str(shown.message))
		if restart:
			silence()
			stream = shown.stream
			var gain := _hearing_gain()
			volume_db = VOICE.playback_volume(stream) + gain
			pitch_scale = 1.0
			if stream != null and gain > -60.0 and get_parent().is_visible_in_tree() and not _dead(get_parent()):
				play()
				set_process(true)
			else: stream = null
		return shown

static func speak(actor: Node3D, canonical_text: String, binding: Dictionary, subtitle_surface: Node = null) -> Dictionary:
	var fallback := {"message":TranslationServer.translate(canonical_text), "stream":null, "duration":0.0, "directed":false}
	if not is_instance_valid(actor): return fallback
	if binding.is_empty():
		stop(actor)
		return fallback
	var row := BANK.canonical(canonical_text, str(binding.get("persona", "")))
	var person := BANK.profile(row)
	if person.is_empty() or str(binding.get("gender", "")) != str(person.get("gender", "")) or str(binding.get("character_id", "")) != str(person.get("character_id", "")):
		stop(actor)
		return fallback
	var listener := _listener_for(actor)
	if is_instance_valid(listener) and Vector2(actor.global_position.x - listener.global_position.x, actor.global_position.z - listener.global_position.z).length() >= 45.0:
		# Reject offscreen/distant speech before allocating a player, loading PCM
		# or displacing any nearby speaker from the three active slots.
		stop(actor)
		return fallback
	var player := actor.get_node_or_null(PLAYER_NAME) as ActorPlayer
	if player == null:
		player = ActorPlayer.new()
		player.name = PLAYER_NAME
		actor.add_child(player)
	player.source = canonical_text
	player.binding = binding.duplicate()
	player._listener = weakref(listener) if is_instance_valid(listener) else null
	player.set_surface(subtitle_surface)
	var survivors: Array[WeakRef] = []
	for reference in _active:
		var old := reference.get_ref() as ActorPlayer
		if is_instance_valid(old) and old != player and old.playing: survivors.append(reference)
	var shown := player.refresh(true)
	if player.playing:
		while survivors.size() >= 3:
			var oldest := survivors.pop_front().get_ref() as ActorPlayer
			if is_instance_valid(oldest): oldest.silence()
		survivors.append(weakref(player))
	_active = survivors
	return shown

static func _listener_for(actor: Node) -> Node3D:
	if not actor.is_inside_tree(): return null
	var scene := actor.get_tree().current_scene
	if not is_instance_valid(scene): return null
	var body := _listener_ref.get_ref() as Node3D if _listener_ref != null else null
	if scene.get_instance_id() == _listener_scene_id and is_instance_valid(body): return body
	_listener_scene_id = scene.get_instance_id()
	_listener_ref = null
	for property in scene.get_property_list():
		if property.name != "player": continue
		body = scene.get("player") as Node3D
		if is_instance_valid(body): _listener_ref = weakref(body)
		return body
	return null

static func stop(actor: Node) -> void:
	if not is_instance_valid(actor): return
	var player := actor.get_node_or_null(PLAYER_NAME) as ActorPlayer
	if player != null:
		player.silence()

static func remaining(actor: Node) -> float:
	if not is_instance_valid(actor): return 0.0
	var player := actor.get_node_or_null(PLAYER_NAME) as ActorPlayer
	if player == null or not player.playing or player.stream == null: return 0.0
	return maxf(0.0, player.stream.get_length() - player.get_playback_position()) + .15

static func remaining_for(surface: Node) -> float:
	if not is_instance_valid(surface): return 0.0
	for reference in _active:
		var player := reference.get_ref() as ActorPlayer
		if not is_instance_valid(player) or player.surface == null or player.surface.get_ref() != surface: continue
		if player.playing and player.stream != null:
			return maxf(0.0, player.stream.get_length() - player.get_playback_position()) + .15
	return 0.0

static func stop_all() -> void:
	for reference in _active:
		var player := reference.get_ref() as ActorPlayer
		if is_instance_valid(player):
			player.silence()
	_active.clear()
