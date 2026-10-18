extends Node
## Both investigations are local side quests; never changes campaign order,
## bridge flags, plane loot, expedition pickups or weapon ownership.
const PROGRESS := preload("res://systems/campaign/MountainStoryProgress.gd")
const PROPS := preload("res://activities/mountain_story/MountainStoryProps.gd")
const DEFINITIONS := preload("res://activities/ActivityDefinitions.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const PLANE_SCRIPT := preload("res://world/places/CargoPlaneNative.gd")
const LABELS := {"cargo_identified":"Investigar carga dos Cobras", "cargo_manifest":"Examinar manifesto",
	"cave_shelter":"Examinar vestígios do abrigo", "vicente_note":"Ler anotação de Vicente"}
var session
var _dialogues: Dictionary = {}
var _plane: Node3D
var _plane_props: Node3D
var _cave_props: Node3D
var _pending := ""
var _generation := 0
var _poll := 0.0
var _valid := true

func configure(owner_session) -> void:
	session = owner_session
	name = "MountainStory"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_valid = PROGRESS.validate_snapshot(session.state.world_state.get("mountain_story",PROGRESS.fresh_snapshot()))
	if not _valid:
		session.controller.save_invalid = true
		session.show_message("Estado das investigações da serra inválido; save original preservado.")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign/mountain-story-dialogue.json"))
	if parsed is Dictionary: _dialogues = parsed

func snapshot() -> Dictionary:
	return PROGRESS.data(session.state.world_state) if session != null else PROGRESS.fresh_snapshot()

func restore_snapshot(saved: Dictionary) -> bool:
	if session == null or not PROGRESS.validate_snapshot(saved): return false
	cancel_attempt()
	# Depois de um ciclo JSON o número volta como decimal (1.0); guarda sempre inteiro para
	# o estado salvo ser idêntico ao que existia antes de salvar.
	var stored: Dictionary = saved.duplicate(true)
	stored["version"] = int(stored.version)
	session.state.world_state.mountain_story = stored
	_valid = true
	return true

static func validate_snapshot(saved: Variant) -> bool:
	return PROGRESS.validate_snapshot(saved)

func busy() -> bool:
	return not _pending.is_empty()

func save_block_reason() -> String:
	return "Conclua a leitura da pista antes de salvar." if busy() else ""

func cancel_attempt() -> void:
	_generation += 1
	_pending = ""
	# Completed discoveries remain valid after death, arrest or travel. The
	# session owns closing its dialogue and restoring input during transitions.

func objective() -> String:
	if session == null or not _valid or session.state.region_id != "mountain": return ""
	return journal_line(session.state.world_state)

## Mesmo texto do objetivo, sem depender da região: o diário (JournalArcs) mostra de qualquer lugar.
static func journal_line(world_state: Dictionary) -> String:
	match PROGRESS.next_event(PROGRESS.data(world_state)):
		"cargo_identified": return "Carga dos Cobras · Investigue as caixas no avião caído no lago."
		"cargo_manifest": return "Carga dos Cobras · Entre pela rampa e examine o manifesto no corredor."
		"cave_shelter": return "Rastro de Vicente · Procure vestígios na Caverna da Queda."
		"vicente_note": return "Rastro de Vicente · Examine a anotação ao fundo do abrigo."
	return ""

func target_place_id() -> String:
	return PROGRESS.place_for(PROGRESS.next_event(snapshot()))

func target_position() -> Vector3:
	if session == null or not _valid or session.state.region_id != "mountain": return Vector3.INF
	var event := PROGRESS.next_event(snapshot())
	if event.is_empty(): return Vector3.INF
	var host := _host(event)
	if is_instance_valid(host): return host.to_global(PROPS.POINTS[event])
	if PROGRESS.place_for(event) == PROGRESS.CAVE:
		return PLACES.get_definition(PROGRESS.CAVE).entry_position
	return DEFINITIONS.at(Vector2(5450,-1150),"mountain")+Vector3(0,0,8)

func nearest_action() -> Dictionary:
	if busy() or not _eligible(): return {}
	var coordinator := get_tree().get_first_node_in_group("mountain_activities")
	if coordinator != null and coordinator.has_method("can_start") and not coordinator.can_start(self): return {}
	var event := PROGRESS.next_event(snapshot())
	if event.is_empty() or not _can_inspect(event): return {}
	return {"id":"mountain_story", "target":event, "label":LABELS[event],
		"position":_host(event).to_global(PROPS.POINTS[event]), "range":PROGRESS.INTERACTION_RANGE}

func perform(target: Variant) -> bool:
	var event := str(target.get("target","")) if target is Dictionary else str(target)
	if event.is_empty() or nearest_action().get("target","") != event: return false
	var lines := _lines(event)
	if lines.is_empty(): return false
	_pending = event
	var generation := _generation
	var host_id := _host(event).get_instance_id()
	session.show_dialogue(lines,func(): _complete_reading(event,generation,host_id))
	return true

func _complete_reading(event: String, generation: int, host_id: int) -> void:
	if generation != _generation or _pending != event: return
	_pending = ""
	var host := _host(event)
	if not is_instance_valid(host) or host.get_instance_id() != host_id or not _can_inspect(event): return
	var point: Vector3 = host.to_global(PROPS.POINTS[event])
	var player_point: Vector3 = session.world.player.global_position
	var distance := Vector2(point.x,point.z).distance_to(Vector2(player_point.x,player_point.z))
	var proof := {"region":session.state.region_id, "place":session.state.place_id,
		"anchor":"cargo_plane" if PROGRESS.place_for(event).is_empty() else PROGRESS.CAVE,
		"alive":session.world.gameplay.health > 0, "on_foot":not session.world.driving.occupied,
		"reachable":true, "distance":distance, "dialogue_complete":true}
	if not PROGRESS.record(session.state.world_state,event,proof): return
	var message := objective()
	if event == "cargo_manifest": message = "Carga dos Cobras concluída. Procure a Caverna da Queda."
	elif event == "vicente_note": message = "Rastro de Vicente concluído. A pista aponta para o deserto."
	session.show_message(message)
	session.save_game()

func _eligible(ignore_dialogue := false) -> bool:
	if session == null or not _valid or not session.ready_for_play or session.controller.save_invalid: return false
	if get_tree().paused: return false
	if session.state.region_id != "mountain" or session.world.gameplay.health <= 0: return false
	if session.rescue_pending or session.arrest_pending or session.world.driving.occupied or session.is_transition_blocked(): return false
	if session.modal and not ignore_dialogue: return false
	if session.world.player.input_locked and not ignore_dialogue: return false
	var ski = session.world.player.ski_controller
	return not (is_instance_valid(ski) and ski.skiing)

func _host(event: String) -> Node3D:
	if session == null: return null
	if PROGRESS.place_for(event) == PROGRESS.CAVE:
		if session.state.place_id == PROGRESS.CAVE and is_instance_valid(session.room) and not session.room.is_queued_for_deletion(): return session.room
		return null
	if session.state.place_id.is_empty() and is_instance_valid(_plane) and not _plane.is_queued_for_deletion(): return _plane
	return null

func _can_inspect(event: String, ignore_dialogue := false) -> bool:
	if event not in PROGRESS.EVENTS or not _eligible(ignore_dialogue): return false
	if session.state.place_id != PROGRESS.place_for(event): return false
	var host := _host(event)
	if not is_instance_valid(host): return false
	var point: Vector3 = host.to_global(PROPS.POINTS[event])
	var actor = session.world.player
	var actor_point: Vector3 = actor.global_position
	if not actor.is_on_floor(): return false
	if absf(actor_point.y-point.y) > 1.8: return false
	if Vector2(actor_point.x,actor_point.z).distance_to(Vector2(point.x,point.z)) > PROGRESS.INTERACTION_RANGE: return false
	# The ramp/cave must be physically present, with no wall between Dante and
	# the document. Its tiny visual sheet has no blocking collision of its own.
	var ray := PhysicsRayQueryParameters3D.create(actor_point+Vector3.UP*.95,point+Vector3.UP*.025,1,[actor.get_rid()])
	return session.world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func _physics_process(delta: float) -> void:
	if session == null or not session.ready_for_play or not is_finite(delta) or delta <= 0: return
	_poll += delta
	if _poll < .5: return
	_poll = 0
	if busy() and (not session.dialogue_open or not _can_inspect(_pending,true)): cancel_attempt()
	_refresh_props()

func _refresh_props() -> void:
	if session == null or not _valid or session.state.region_id != "mountain":
		_release_props()
		return
	if session.state.place_id == PROGRESS.CAVE and is_instance_valid(session.room):
		if not is_instance_valid(_cave_props) or _cave_props.get_parent() != session.room:
			if is_instance_valid(_cave_props): _cave_props.queue_free()
			_cave_props = PROPS.attach(session.room,true)
	else:
		if is_instance_valid(_cave_props): _cave_props.queue_free()
		_cave_props = null
	var plane_point := DEFINITIONS.at(Vector2(5450,-1150),"mountain")
	if not session.state.place_id.is_empty() or session.world.player.global_position.distance_to(plane_point) > 100:
		if is_instance_valid(_plane_props): _plane_props.queue_free()
		_plane_props = null
		_plane = null
		return
	if not is_instance_valid(_plane):
		for candidate in get_tree().get_nodes_in_group("native_world_rewards"):
			if candidate.get_script() == PLANE_SCRIPT and not candidate.is_queued_for_deletion():
				_plane = candidate
				break
	if is_instance_valid(_plane) and not is_instance_valid(_plane_props): _plane_props = PROPS.attach(_plane,false)

func _lines(key: String) -> Array:
	var result: Array = []
	var language := "en" if TranslationServer.get_locale().begins_with("en") else "pt"
	for line in _dialogues.get(key,[]):
		result.append({"speaker":line.speaker, "message":line[language]})
	return result

func _release_props() -> void:
	for prop in [_plane_props,_cave_props]:
		if is_instance_valid(prop): prop.queue_free()
	_plane = null
	_plane_props = null
	_cave_props = null

func _exit_tree() -> void:
	cancel_attempt()
	_release_props()
