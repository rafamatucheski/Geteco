extends Node
## One live conversation at a time. It never pauses threats or moves either body.
const PANEL := preload("res://ui/BuildingSocialPanel.gd")
const PROTECTION := preload("res://gameplay/DamageProtection.gd")
const VOICE_BINDING := preload("res://audio/VoiceActorBinding.gd")
const ACTOR_VOICE := preload("res://audio/ActorDialogueVoice.gd")
const TALK_DISTANCE := 2.4
const KEEP_DISTANCE := 2.8
const MAX_HEIGHT := 1.15
var session
var active := false
var target: Node3D
var panel: Control
var _room: Node3D
var _generation := 0
var _floor := -1
var _health := 0.0
var _clock := 0.0
var _mouse_mode := Input.MOUSE_MODE_HIDDEN
var _release_guard := false
var _connections: Array[Dictionary] = []

func _ready() -> void:
	name = "BuildingSocialInteraction"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

func _can_open() -> bool:
	if not is_instance_valid(session) or not session.ready_for_play or session.modal or get_tree().paused: return false
	if session.is_transition_blocked() or session.rescue_pending or session.arrest_pending: return false
	if session.world.driving.occupied or session.world.player.input_locked or session.world.gameplay.health <= 0: return false
	if int(session.world.gameplay.get("stars")) > 0: return false
	if session.world.gameplay.has_method("police_surrendering") and session.world.gameplay.police_surrendering(): return false
	if not is_instance_valid(session.building_entrance) or not session.building_entrance.in_building(): return false
	return is_instance_valid(session.room) and session.state.place_id not in ["maciota", "maciota_garage"]

func nearest_action() -> Dictionary:
	if active or _release_guard or not _can_open(): return {}
	var occupants: Node = session.room.get("occupants")
	if not is_instance_valid(occupants): return {}
	var nearest: Node3D
	var best := TALK_DISTANCE * TALK_DISTANCE
	# Only the current storey's owned residents; no global per-frame group scan.
	for resident: Node3D in occupants.residents:
		if not _accessible(resident, TALK_DISTANCE): continue
		var distance: float = session.world.player.global_position.distance_squared_to(resident.global_position)
		if distance <= best:
			best = distance
			nearest = resident
	if nearest == null: return {}
	return {"id":"building_social", "target":nearest, "label":"Conversar com " + str(nearest.social_snapshot().get("name", "morador"))}

func _accessible(resident: Node3D, distance: float) -> bool:
	if not is_instance_valid(resident) or resident.is_queued_for_deletion() or not resident.is_inside_tree() or not resident.is_visible_in_tree(): return false
	if not resident.is_in_group("building_resident") or not resident.has_method("social_snapshot"): return false
	if resident.get("dead") == true or PROTECTION.is_protected(resident): return false
	if not is_instance_valid(session.room) or not session.room.is_ancestor_of(resident): return false
	var player: Node3D = session.world.player
	var offset: Vector3 = resident.global_position - player.global_position
	if absf(offset.y) > MAX_HEIGHT or offset.length_squared() > distance * distance: return false
	if not bool(resident.social_snapshot().get("can_interact", false)): return false
	# The visible wall cutaway keeps its real collision: conversation cannot pass it.
	var query := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * 1.25, resident.global_position + Vector3.UP * 1.25, 1)
	return player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func open(resident: Node3D) -> bool:
	if active or _release_guard or not _can_open() or not _accessible(resident, TALK_DISTANCE): return false
	if not resident.begin_social(session.world.player): return false
	_mouse_mode = Input.mouse_mode
	session._menu("")
	session.panel.hide()
	active = true
	target = resident
	_room = session.room
	_generation = session.transition_generation
	_floor = int(_room.get("floor_index"))
	_health = float(session.world.gameplay.health)
	_clock = 0.0
	session.menu_closed = _dismiss
	if not is_instance_valid(panel):
		panel = PANEL.new()
		session.world.hud.add_child(panel)
		panel.action_requested.connect(choose)
		panel.close_requested.connect(close)
	var snapshot: Dictionary = resident.social_snapshot()
	panel.present(snapshot, resident.social_options(), str(snapshot.get("line", "Pode falar.")))
	var spoken := ACTOR_VOICE.speak(resident, str(snapshot.get("line", "Pode falar.")), VOICE_BINDING.resolve(resident, "building_social"), panel.reply_label)
	panel.reply_label.text = str(spoken.get("message", "Pode falar."))
	_position_panel()
	panel.focus_first.call_deferred()
	_listen(session.world.gameplay, "player_wounded", _wounded)
	_listen(session.world.gameplay, "police_warning_issued", close)
	_listen(session.world.gameplay, "npc_gunfire", _gunfire)
	_listen(session.world.gameplay, "explosion_occurred", _explosion)
	var reaction := resident.get_node_or_null("WorkplaceThreatReaction")
	if is_instance_valid(reaction): _listen(reaction, "threat_started", _threat_started)
	set_process(true)
	return true

func choose(action_id: String) -> void:
	if not _still_owned() or not _accessible(target, KEEP_DISTANCE): close(); return
	var speaker := target
	var result: Dictionary = target.social_interact(action_id, session.world.player)
	# Intimidation can emit threat_started synchronously and relinquish the UI.
	if not active:
		_present_reply(speaker, str(result.get("line", "")), false)
		return
	if bool(result.get("close", false)) or not bool(target.social_snapshot().get("can_interact", false)):
		var line := str(result.get("line", ""))
		close()
		_present_reply(speaker, line, false)
		return
	panel.present(target.social_snapshot(), target.social_options())
	_present_reply(speaker, str(result.get("line", "")), true)

func _present_reply(speaker: Node3D, line: String, in_panel: bool) -> void:
	if line.is_empty() or not is_instance_valid(speaker): return
	var surface: Node = panel.reply_label if in_panel else null
	var binding := VOICE_BINDING.resolve(speaker, "building_social")
	var spoken := ACTOR_VOICE.speak(speaker, line, binding, surface)
	if in_panel: panel.reply_label.text = str(spoken.get("message", line))
	else: session.show_speech(str(speaker.social_snapshot().get("name", "")), str(spoken.get("message", line)), maxf(3.0, float(spoken.get("duration", 0.0))), false, str(binding.get("persona", "")), line, str(binding.get("character_id", "")), str(binding.get("section", "")))

func handle_input(event: InputEvent) -> bool:
	if not active: return _release_guard and not event.is_action("pause_game") and not event.is_action("ui_cancel")
	if event.is_action_pressed("pause_game") and not event.is_echo():
		close()
		return false # PauseInput receives the same event after relinquishing input.
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		close()
		return true
	if event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag: return false
	# Godot's focus navigation/accept reach the actual Buttons. Gameplay stays gated.
	for action in ["ui_accept", "ui_left", "ui_right", "ui_up", "ui_down", "ui_focus_next", "ui_focus_prev"]:
		if event.is_action(action): return false
	if event.is_action_pressed("interact") and not event.is_echo(): panel.activate_focused()
	return true

func blocks_gameplay_input() -> bool:
	return active or _release_guard

func _still_owned() -> bool:
	return active and is_instance_valid(session) and session.modal and session.menu_closed == Callable(self, "_dismiss")

func _process(delta: float) -> void:
	if _release_guard and not Input.is_action_pressed("fire"):
		_release_guard = false
		if not active: set_process(false)
	if not active: return
	if not _still_owned(): _dismiss(); return
	if get_tree().paused or not session.ready_for_play or session.rescue_pending or session.arrest_pending or session.is_transition_blocked() or session.world.driving.occupied:
		close(); return
	if not is_instance_valid(_room) or session.room != _room or session.transition_generation != _generation or int(_room.get("floor_index")) != _floor:
		close(); return
	if float(session.world.gameplay.health) < _health or int(session.world.gameplay.get("stars")) > 0:
		close(); return
	_clock -= delta
	if _clock > 0.0: return
	_clock = .12
	if not _accessible(target, KEEP_DISTANCE): close(); return
	panel.present(target.social_snapshot(), target.social_options())
	_position_panel()

func _position_panel() -> void:
	if not active or not is_instance_valid(target) or not is_instance_valid(panel): return
	var camera: Camera3D = session.world.get_viewport().get_camera_3d()
	if not is_instance_valid(camera): return
	var midpoint: Vector3 = (session.world.player.global_position + target.global_position) * .5 + Vector3.UP
	if not camera.is_position_behind(midpoint): panel.set_conversation_anchor(camera.unproject_position(midpoint))

func close() -> void:
	if not active: return
	var owns_menu := _still_owned()
	if owns_menu: session.close_menu()
	else: _dismiss()
	if owns_menu and is_instance_valid(session) and not session.modal:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if get_tree().paused else _mouse_mode

func _dismiss() -> void:
	if not active: return
	active = false
	if is_instance_valid(target):
		ACTOR_VOICE.stop(target)
		target.end_social()
	target = null
	_room = null
	if is_instance_valid(panel): panel.hide()
	for connection: Dictionary in _connections:
		var source: Object = connection.source
		if is_instance_valid(source) and source.is_connected(connection.signal_name, connection.callback): source.disconnect(connection.signal_name, connection.callback)
	_connections.clear()
	# Releasing a GUI button must not become an automatic shot in the same frame.
	_release_guard = Input.is_action_pressed("fire")
	set_process(_release_guard)

func _listen(source: Object, signal_name: String, callback: Callable) -> void:
	if not source.has_signal(signal_name): return
	source.connect(signal_name, callback)
	_connections.append({"source":source, "signal_name":signal_name, "callback":callback})

func _wounded(_lethal: bool) -> void:
	close()

func _threat_started(_resident: Node3D) -> void:
	close()

func _gunfire(origin: Vector3, _direction: Vector3, _shooter: Node3D) -> void:
	if active and session.world.player.global_position.distance_squared_to(origin) <= 900.0: close()

func _explosion(origin: Vector3, radius: float, _source: Node) -> void:
	if active and session.world.player.global_position.distance_squared_to(origin) <= pow(maxf(30.0, radius * 2.0), 2): close()

func _exit_tree() -> void:
	close()
	if is_instance_valid(panel): panel.queue_free()
