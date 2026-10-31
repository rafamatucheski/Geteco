extends Node3D
## Um ponto de integração para as missões e corridas escritas da montanha.
## Instalado pelo patch revisado de arquivo compartilhado; sem autoload nem entrada global.
const STORY := preload("res://activities/mountain_story/MountainStory.gd")
const DOWNHILL := preload("res://activities/mountain_downhill/MountainDownhill.gd")
const JEEP := preload("res://activities/mountain_jeep/MountainJeepController.gd")
const PACK_STATE := preload("res://systems/campaign/MountainPackState.gd")
const TITLES := {
	"mountain_story": "Carga dos Cobras e Rastro de Vicente",
	"mountain_downhill": "Descida da Meia Noite · seis rivais",
	"mountain_jeep": "Trilha dos Pinheiros · jipe",
}
var session
var components: Dictionary = {}
var tracked := "mountain_story"

func configure(owner_session) -> void:
	session = owner_session
	name = "MountainActivities"
	add_to_group("mountain_activities")
	if not validate_world(session.state.world_state, session.state.economy.snapshot()):
		session.controller.save_invalid = true
		session.show_message("Progresso da montanha inválido; save original preservado.")
		return
	for pair in [["mountain_story", STORY], ["mountain_downhill", DOWNHILL], ["mountain_jeep", JEEP]]:
		var component: Node = pair[1].new()
		components[pair[0]] = component
		add_child(component)
		component.configure(session)

func can_start(requester: Node) -> bool:
	if session == null or not session.ready_for_play or session.modal: return false
	if session.controller.save_invalid or session.is_transition_blocked(): return false
	if session.get_tree().paused or session.world.gameplay.health <= 0: return false
	if session.state.intro.stage != "complete" or not session.state.campaign.active_id.is_empty(): return false
	if session.arrival != null and session.arrival.active: return false
	if session.activities != null and not session.activities.can_rest(): return false
	if session.mountain_progression != null:
		if session.mountain_progression.skiing or not session.mountain_progression.race.mode.is_empty(): return false
	if session.motocross != null and session.motocross.mounted: return false
	if session.skate != null and session.skate.controls_locked(): return false
	if session.passenger_transport != null and session.passenger_transport.riding: return false
	if session.urban_operations != null:
		var freight = session.urban_operations.freight
		if freight != null and freight.active_bay >= 0: return false
		var quest = session.urban_operations.get("village_quest")
		if is_instance_valid(quest) and quest.data.started and not quest.data.completed: return false
	for component in components.values():
		if component != requester and not component.save_block_reason().is_empty(): return false
	return true

func busy() -> bool:
	return not save_block_reason().is_empty()

func save_block_reason() -> String:
	for component in components.values():
		var reason: String = component.save_block_reason()
		if not reason.is_empty(): return reason
	return ""

func nearest_action() -> Dictionary:
	# Uma corrida ativa precisa manter a ação de cancelar mesmo perto de outro objeto de missão.
	for component in components.values():
		if component.save_block_reason().is_empty(): continue
		var active_action: Dictionary = component.nearest_action()
		if not active_action.is_empty(): return active_action
	for component in components.values():
		var action: Dictionary = component.nearest_action()
		if not action.is_empty(): return action
	return {}

func handles(action: Dictionary) -> bool:
	return components.has(str(action.get("id", "")))

func perform(action: Dictionary) -> bool:
	var id := str(action.get("id", ""))
	if not components.has(id): return false
	var current: Dictionary = components[id].nearest_action()
	if current.get("target", "") != action.get("target", ""): return false
	tracked = id
	return components[id].perform(str(action.get("target", "")))

func cancel_attempt() -> void:
	for component in components.values(): component.cancel_attempt()

func write_snapshot() -> void:
	if session == null or session.controller.save_invalid: return
	for key in components:
		session.state.world_state[key] = components[key].snapshot()

func _objective_owner() -> Node:
	if session == null or not session.ready_for_play or session.state.region_id != "mountain": return null
	if session.state.intro.stage != "complete" or not session.state.campaign.active_id.is_empty(): return null
	if session.arrival != null and session.arrival.active: return null
	for component in components.values():
		if not component.save_block_reason().is_empty(): return component
	var selected: Node = components.get(tracked)
	return selected if is_instance_valid(selected) and can_start(selected) else null

func objective() -> String:
	var component := _objective_owner()
	return component.objective() if is_instance_valid(component) else ""

func target_position() -> Vector3:
	var component := _objective_owner()
	if not is_instance_valid(component): return Vector3.INF
	if not session.state.place_id.is_empty() and is_instance_valid(session.room):
		if not component.has_method("target_place_id") or component.target_place_id() != session.state.place_id:
			return session.room.exit_position
	return component.target_position()

func show_journal() -> void:
	if session == null: return
	session._menu("Atividades da montanha")
	if busy():
		session._button("Cancelar tentativa", func():
			cancel_attempt()
			session.close_menu()
			session.save_game())
	else:
		for key in TITLES:
			if not components.has(key): continue
			var chosen := str(key)
			session._button(str(TITLES[key]), _track.bind(chosen))
	session._button("Fechar", session.close_menu)

func _track(key: String) -> void:
	tracked = key
	session.close_menu()
	if session.state.region_id != "mountain": session.show_message("Siga para a serra para encontrar esta atividade.")

static func validate_world(world_state: Dictionary, economy: Dictionary) -> bool:
	return PACK_STATE.validate_world(world_state, economy)
