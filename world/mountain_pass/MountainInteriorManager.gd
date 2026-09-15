class_name MountainInteriorManager
extends Node2D

## Gerenciador de Interiores da Regiao MountainPass:
## Conecta as portas externas dos Chales Alpinos e da Ammu-Nation da Montanha
## aos respectivos interiores 2D jogaveis, gerenciando teletransporte, pontos de
## retorno, camera e sinais de transicao.

signal actor_entered_interior(actor: Node2D, interior_id: StringName)
signal actor_returned_to_exterior(actor: Node2D, interior_id: StringName)

const AMMUNATION_SCRIPT := preload("res://world/mountain_pass/MountainGunShopInterior.gd")
const CABIN_SCRIPT := preload("res://world/mountain_pass/MountainCabinInterior.gd")

var ammunation_interior: Node2D
var cabin_interior: Node2D
var bunker_interior: Node2D
var lumberjack_interior: Node2D
var ski_lodge_interior: Node2D
var mystery_cave_interior: Node2D
var region_ready := false

# Maps exterior entrance -> Dictionary { "interior_id": StringName, "return_pos": Vector2 }
var _exterior_doors: Dictionary = {}
# Maps interior_id -> interior Node2D
var _interiors: Dictionary = {}
# Maps actor -> return_pos Vector2
var _actor_returns: Dictionary = {}
var _actor_scale_helpers: Dictionary = {}

func _ready() -> void:
	_build_interiors()

func _build_interiors() -> void:
	var spaces_root := Node2D.new()
	spaces_root.name = "MountainInteriorSpaces"
	add_child(spaces_root)

	# 1. Ammu-Nation Interior (Loja de Armas e Caça com Armeiro Vance)
	ammunation_interior = AMMUNATION_SCRIPT.new()
	ammunation_interior.name = "MountainAmmunationInterior"
	ammunation_interior.position = Vector2(20000, 20000)
	spaces_root.add_child(ammunation_interior)
	_interiors[&"ammunation"] = ammunation_interior
	await _interior_budget_pause()

	# 2. Chalé Alpino Interior (Refúgio com Lareira de Pedra)
	cabin_interior = CABIN_SCRIPT.new()
	cabin_interior.name = "MountainCabinInterior"
	cabin_interior.position = Vector2(22500, 20000)
	spaces_root.add_child(cabin_interior)
	_interiors[&"mountain_cabin"] = cabin_interior
	await _interior_budget_pause()

	bunker_interior = preload("res://world/mountain_pass/MountainBunkerInterior.gd").new()
	bunker_interior.name = "MountainBunkerInterior"
	bunker_interior.position = Vector2(26000, 20000)
	spaces_root.add_child(bunker_interior)
	_interiors[&"mountain_bunker"] = bunker_interior
	await _interior_budget_pause()
	lumberjack_interior = preload("res://world/mountain_pass/LumberjackShelterInterior.gd").new()
	lumberjack_interior.name = "LumberjackShelterInterior"
	lumberjack_interior.position = Vector2(29500,20000)
	spaces_root.add_child(lumberjack_interior)
	_interiors[&"lumberjack_shelter"] = lumberjack_interior
	await _interior_budget_pause()
	var outfitters := preload("res://world/harbor/interiors/ClothingRoom3D.gd").new()
	outfitters.name = "MountainOutfittersInterior"
	outfitters.winter_stock = true
	outfitters.position = Vector2(33000, 20000)
	spaces_root.add_child(outfitters)
	_interiors[&"mountain_outfitters"] = outfitters
	outfitters.modal_opened.connect(_set_outfitters_modal.bind(true))
	outfitters.modal_closed.connect(_set_outfitters_modal.bind(false))
	await _interior_budget_pause()

	ski_lodge_interior = preload("res://world/mountain_pass/SummitSkiLodgeInterior.gd").new()
	ski_lodge_interior.name = "SummitSkiLodgeInterior"
	ski_lodge_interior.position = Vector2(36500, 20000)
	spaces_root.add_child(ski_lodge_interior)
	_interiors[&"ski_lodge"] = ski_lodge_interior
	await _interior_budget_pause()

	mystery_cave_interior = preload("res://world/mountain_pass/MountainMysteryCaveInterior.gd").new()
	mystery_cave_interior.name = "MountainMysteryCaveInterior"
	mystery_cave_interior.position = Vector2(40000, 20000)
	spaces_root.add_child(mystery_cave_interior)
	_interiors[&"mountain_mystery_cave"] = mystery_cave_interior

	# Conecta portas de saida dos interiores
	call_deferred("_bind_interior_exits")
	region_ready = true

func _set_outfitters_modal(active: bool) -> void:
	var actor := get_tree().get_first_node_in_group("player")
	if actor != null and actor.has_method("set_dialogue_active"):
		actor.set_dialogue_active(active)

func _interior_budget_pause() -> void:
	# One room per idle frame during world streaming; isolated scenes preserve
	# their synchronous ready contract for tools and existing tests.
	if get_parent().get("streamed_region") == true:
		await get_tree().process_frame

func _bind_interior_exits() -> void:
	for id in _interiors:
		var interior: Node2D = _interiors[id]
		for candidate in get_tree().get_nodes_in_group("harbor_interior_exit"):
			var exit_door := candidate as BuildingEntrance
			if exit_door == null or not interior.is_ancestor_of(exit_door):
				continue
			exit_door.get_node("InteractionArea").collision_mask = 4
			var callback := _on_exit_requested.bind(id)
			if not exit_door.destination_requested.is_connected(callback):
				exit_door.destination_requested.connect(callback)

func register_exterior_entrance(entrance: BuildingEntrance, interior_id: StringName, return_pos: Vector2) -> void:
	if entrance == null:
		return
	# No mundo contínuo Dante usa a camada 4; a cena isolada também usava 1,
	# mascarando a falha de detecção das portas na partida vinda do porto.
	entrance.get_node("InteractionArea").collision_mask = 4
	_exterior_doors[entrance] = {
		"interior_id": interior_id,
		"return_pos": return_pos
	}
	var callback := _on_entrance_requested.bind(entrance)
	if not entrance.destination_requested.is_connected(callback):
		entrance.destination_requested.connect(callback)

func _on_entrance_requested(entrance_self: BuildingEntrance, actor: Node2D, _dest_id: StringName, _scene: PackedScene, _spawn: StringName, entrance_ref: BuildingEntrance) -> void:
	var data: Dictionary = _exterior_doors.get(entrance_ref, {})
	if data.is_empty():
		return
	
	var i_id: StringName = data["interior_id"]
	var interior: Node2D = _interiors.get(i_id)
	if interior == null:
		return
	if actor.has_method("stop_skiing"):
		actor.stop_skiing()

	# Salva ponto de retorno deste ator
	_actor_returns[actor] = data["return_pos"]
	actor.set_meta("police_exterior_position", data["return_pos"])

	# Teletransporta o jogador para o ponto de spawn do interior
	var spawn: Marker2D = interior.get_node_or_null("SpawnPoint") as Marker2D
	var spawn_pos := interior.global_position + Vector2(0, 150)
	if spawn:
		spawn_pos = spawn.global_position

	actor.set_meta("mountain_interior", true)
	actor.set_meta("mountain_interior_id", i_id)
	actor.global_position = spawn_pos
	if actor is CharacterBody2D:
		actor.velocity = Vector2.ZERO

	if interior.has_method("set_npc_rendering_active"):
		interior.set_npc_rendering_active(true)

	if interior.get("camera_3d") is Camera3D and interior.get("sprite_3d") is Sprite2D:
		if _actor_scale_helpers.has(actor):
			_actor_scale_helpers[actor].restore()
			_actor_scale_helpers[actor].queue_free()
		var helper := preload("res://systems/interiors/InteriorActorPresentation.gd").new()
		add_child(helper)
		helper.configure(actor, interior.camera_3d, interior.sprite_3d)
		_actor_scale_helpers[actor] = helper
	actor_entered_interior.emit(actor, i_id)

func _on_exit_requested(exit_door_self: BuildingEntrance, actor: Node2D, _dest_id: StringName, _scene: PackedScene, _spawn: StringName, interior_id: StringName) -> void:
	var starts_skiing := is_instance_valid(exit_door_self) and bool(exit_door_self.get_meta("starts_skiing", false))
	if starts_skiing and actor.get("ski_equipment_ready") != true:
		if actor.has_method("_show_weapon_notice"):
			actor._show_weapon_notice("RETIRE OS SKIS NO RACK ANTES DE IR ÀS PISTAS")
		return
	var interior: Node2D = _interiors.get(interior_id)
	if interior and interior.has_method("set_npc_rendering_active"):
		interior.set_npc_rendering_active(false)

	if _actor_scale_helpers.has(actor):
		_actor_scale_helpers[actor].restore()
		_actor_scale_helpers[actor].queue_free()
		_actor_scale_helpers.erase(actor)
	var return_pos: Vector2 = _actor_returns.get(actor, Vector2(6350, 600))
	if is_instance_valid(exit_door_self) and exit_door_self.has_meta("mountain_return_position"):
		return_pos = exit_door_self.get_meta("mountain_return_position")
	actor.remove_meta("mountain_interior")
	actor.remove_meta("mountain_interior_id")
	actor.remove_meta("police_exterior_position")
	_actor_returns.erase(actor)
	actor.global_position = return_pos
	if actor is CharacterBody2D:
		actor.velocity = Vector2.ZERO

	var actor_camera := actor.get_node_or_null("Camera") as Camera2D
	if actor_camera:
		actor_camera.make_current()
		actor_camera.reset_smoothing()
	if starts_skiing and actor.has_method("start_skiing"):
		actor.start_skiing(Vector2.UP)
		if actor.has_method("_show_weapon_notice"):
			actor._show_weapon_notice("SKI: W ACELERA · S FREIA · A/D CURVAM · ESPAÇO CRAVA AS BORDAS")
	actor_returned_to_exterior.emit(actor, interior_id)

func _process(_delta: float) -> void:
	# Respawns can bypass doors. Do not leave indoor scale, camera or shelter active.
	for actor in _actor_returns.keys():
		if not is_instance_valid(actor):
			if _actor_scale_helpers.has(actor):
				_actor_scale_helpers[actor].queue_free()
				_actor_scale_helpers.erase(actor)
			_actor_returns.erase(actor)
			continue
		var id: StringName = actor.get_meta("mountain_interior_id", &"")
		var interior: Node2D = _interiors.get(id)
		if interior and actor.global_position.distance_to(interior.global_position) > 1600.0:
			_actor_returns[actor] = actor.global_position
			_on_exit_requested(null, actor, &"", null, &"", id)
