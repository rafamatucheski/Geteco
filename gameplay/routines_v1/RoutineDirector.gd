extends Node
## Lifecycle por contexto/proximidade para rotinas produtivas do V1. Somente uma
## varredura pequena a cada 0,25 s fica ativa; atores distantes deixam a arvore.

const CATALOG := preload("res://gameplay/routines_v1/RoutineCatalog.gd")
const ACTOR := preload("res://gameplay/routines_v1/V1RoutineActor.gd")
const SCAN_INTERVAL := .25
const ACTIVATE_DISTANCE := 48.0
const RELEASE_DISTANCE := 62.0
const MAX_OUTDOOR_ACTORS := 12

var world
var session
var controller
var definitions: Array[Dictionary] = []
var actors: Dictionary = {}
var suspended_states: Dictionary = {}
var scan_clock := 0.0
var context_key := ""

func configure(owner_world, owner_session, owner_controller) -> void:
	world = owner_world
	session = owner_session
	controller = owner_controller
	name = "V1RoutineDirector"
	definitions = CATALOG.definitions()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(true)

func _exit_tree() -> void:
	for actor in actors.values():
		if is_instance_valid(actor): actor.queue_free()
	actors.clear()
	suspended_states.clear()

func _process(delta: float) -> void:
	if session == null or world == null or not is_instance_valid(world.player): return
	scan_clock -= delta
	if scan_clock > 0: return
	scan_clock = SCAN_INTERVAL
	refresh_context()

func refresh_context() -> void:
	if session == null or session.state == null: return
	var next_key := "%s:%s" % [session.state.region_id,session.state.place_id]
	if next_key != context_key:
		_clear_all()
		context_key = next_key
	_sync_active_set()

func _sync_active_set() -> void:
	var candidates: Array[Dictionary] = []
	var place_id: String = session.state.place_id
	var region_id: String = session.state.region_id
	for definition in definitions:
		if definition.region != region_id or definition.place_id != place_id: continue
		if not _shift_active(definition): continue
		var resolved := _resolved(definition)
		if resolved.is_empty(): continue
		var distance: float = world.player.global_position.distance_to(resolved.position)
		var threshold := RELEASE_DISTANCE if actors.has(definition.id) and is_instance_valid(actors[definition.id]) else ACTIVATE_DISTANCE
		if not place_id.is_empty() or distance <= threshold:
			resolved["focus_distance"] = distance
			candidates.append(resolved)
	candidates.sort_custom(func(a: Dictionary,b: Dictionary): return float(a.focus_distance)<float(b.focus_distance))
	var desired: Dictionary = {}
	var limit := candidates.size() if not place_id.is_empty() else mini(MAX_OUTDOOR_ACTORS,candidates.size())
	for index in limit: desired[candidates[index].id] = candidates[index]
	for id in actors.keys():
		var actor = actors[id]
		if not is_instance_valid(actor):
			actors.erase(id)
			continue
		var keep := desired.has(id)
		if keep and place_id.is_empty(): keep = actor.global_position.distance_to(world.player.global_position) <= RELEASE_DISTANCE
		if not keep:
			_suspend(id, actor)
	for id in desired:
		if actors.has(id) and is_instance_valid(actors[id]): continue
		_spawn(desired[id])

func _resolved(definition: Dictionary) -> Dictionary:
	var result := definition.duplicate(true)
	if not str(definition.place_id).is_empty():
		if not is_instance_valid(session.room): return {}
		var local: Variant = definition.get("local_position")
		if not local is Vector3: return {}
		result["position"] = session.room.to_global(local)
	return result

func _shift_active(definition: Dictionary) -> bool:
	if definition.get("kind","") != "dock_worker": return true
	if not str(definition.get("id","")).begins_with("south_port_worker_"): return true
	var hour := 12.0
	if is_instance_valid(session.weather): hour = float(session.weather.time_of_day) * 24.0
	return (hour >= 6.0 and hour < 18.0) or bool(definition.get("night_shift",false))

func _spawn(definition: Dictionary) -> void:
	var id: String = str(definition.id)
	if _tree_has(id): return
	var state: Dictionary = suspended_states.get(id, {})
	var restore_position := str(definition.get("place_id", "")).is_empty()
	var point: Vector3 = state.get("position", definition.position) if restore_position else definition.position
	if not point.is_finite() or not session.position_clear(point+Vector3.UP*.04):
		# A troca de chunk pode suspender um morador depois que seu piso saiu da
		# física. Nesse caso a posição salva já afundou; recomece no posto válido.
		point = definition.position
		restore_position = false
		if not point.is_finite() or not session.position_clear(point+Vector3.UP*.04): return
	var actor = ACTOR.new()
	actor.configure(definition,Callable(session,"position_clear"))
	actor.position = point+Vector3.UP*.04
	world.add_child(actor)
	if not state.is_empty():
		actor.restore_routine(state, restore_position)
		if not restore_position: actor.velocity.y = 0.0
	actors[id] = actor

func _suspend(id: String, actor) -> void:
	if is_instance_valid(actor) and actor.has_method("snapshot_routine"):
		suspended_states[id] = actor.snapshot_routine()
	if is_instance_valid(actor): actor.queue_free()
	actors.erase(id)

func _tree_has(id: String) -> bool:
	for node in get_tree().get_nodes_in_group("v1_routine_actor"):
		if str(node.get_meta("v1_routine_id","")) == id: return true
	return false

func _clear_all() -> void:
	for id in actors.keys(): _suspend(id, actors[id])

func nearest_action() -> Dictionary:
	if session == null or world == null or world.driving.occupied: return {}
	var best := {}
	var nearest := INF
	for id in actors:
		var actor = actors[id]
		if not is_instance_valid(actor): continue
		var lines: Array = actor.definition.get("lines",[])
		if lines.is_empty(): continue
		var distance: float = world.player.global_position.distance_to(actor.global_position)
		if distance <= 1.7 and distance < nearest:
			nearest = distance
			best = {"id":"v1_routine","target":id,"label":"Conversar","position":actor.global_position}
	return best

func perform(id: String) -> bool:
	if not actors.has(id) or not is_instance_valid(actors[id]): return false
	var action := nearest_action()
	if action.get("target","") != id: return false
	var actor = actors[id]
	var message: String = actor.next_dialogue_line()
	if message.is_empty(): return false
	actor.begin_interaction()
	session.show_dialogue([{"speaker":actor.definition.get("display_name","Morador"),"message":message}])
	return true

func active_ids() -> Array[String]:
	var result: Array[String] = []
	for id in actors:
		if is_instance_valid(actors[id]): result.append(id)
	return result
