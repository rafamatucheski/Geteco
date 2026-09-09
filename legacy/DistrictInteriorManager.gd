class_name DistrictInteriorManager
extends Node2D

## Integra duas fachadas do distrito com interiores locais e reutilizáveis.
## Não conhece Player.gd, WeaponStore.gd nem a lógica especial da Pay'n'Spray.

signal actor_entered_interior(actor: Node2D, interior_id: StringName)
signal actor_returned_to_district(actor: Node2D, interior_id: StringName)

@export_group("Posições no mapa fixo")
@export var ammu_nation_entrance_position := Vector2(419.0, 334.0)
@export var common_garage_entrance_position := Vector2(268.0, 1028.0)
@export var clothing_store_entrance_position := Vector2(227.0, 334.0)
@export var ammu_return_offset := Vector2(0.0, 36.0)
@export var garage_return_offset := Vector2(0.0, 36.0)
@export var clothing_return_offset := Vector2(0.0, 36.0)
@export_range(0.1, 1.5, 0.05) var transition_cooldown := 0.35

@onready var router: EntranceRouter = $EntranceRouter
@onready var ammu_entrance: BuildingEntrance = $WorldEntrances/AmmuNationEntrance
@onready var garage_entrance: BuildingEntrance = $WorldEntrances/CommonGarageEntrance
@onready var clothing_entrance: BuildingEntrance = $WorldEntrances/ClothingStoreEntrance
@onready var ammu_return: Marker2D = $WorldEntrances/AmmuNationReturn
@onready var garage_return: Marker2D = $WorldEntrances/CommonGarageReturn
@onready var clothing_return: Marker2D = $WorldEntrances/ClothingStoreReturn
@onready var ammu_interior: ShopInterior = $InteriorSpaces/AmmuNationInterior
@onready var garage_interior: Node2D = $InteriorSpaces/CommonGarageInterior
@onready var ammu_exit: BuildingEntrance = $InteriorSpaces/AmmuNationInterior/InteriorExit
@onready var garage_exit: BuildingEntrance = $InteriorSpaces/CommonGarageInterior.get_node_or_null("InteriorExit")
@onready var clothing_interior: Node2D = $InteriorSpaces/ClothingStoreInterior
@onready var clothing_shop: ShopInterior = $InteriorSpaces/ClothingStoreInterior/ShopInterior
@onready var clothing_exit: BuildingEntrance = $InteriorSpaces/ClothingStoreInterior/ShopInterior/InteriorExit


func _ready() -> void:
	_apply_fixed_layout()
	_configure_destinations()
	_configure_interiors()
	_bind_transfers()


func _apply_fixed_layout() -> void:
	ammu_entrance.position = ammu_nation_entrance_position
	garage_entrance.position = common_garage_entrance_position
	clothing_entrance.position = clothing_store_entrance_position
	# Each return is authored around the neighbouring lots: the Ammu-Nation
	# clears the rowhouse below it, and the garage clears its parking bays.
	ammu_return.position = ammu_nation_entrance_position + ammu_return_offset
	garage_return.position = common_garage_entrance_position + garage_return_offset
	clothing_return.position = clothing_store_entrance_position + clothing_return_offset


func _configure_destinations() -> void:
	if garage_exit == null and garage_interior:
		garage_exit = garage_interior.get_node_or_null("InteriorExit")
		
	var garage_spawn = garage_interior.get_node_or_null("SpawnPoint") if garage_interior else null
	if garage_spawn == null and garage_interior:
		garage_spawn = garage_interior.get("spawn_point")

	router.register_destination(&"ammu_interior_spawn", ammu_interior.spawn_point)
	if garage_spawn:
		router.register_destination(&"garage_interior_spawn", garage_spawn)
	router.register_destination(&"clothing_interior_spawn", clothing_shop.spawn_point)
	router.register_destination(&"ammu_exterior_return", ammu_return)
	router.register_destination(&"garage_exterior_return", garage_return)
	router.register_destination(&"clothing_exterior_return", clothing_return)

	var entrances_list: Array = [ammu_entrance, garage_entrance, clothing_entrance, ammu_exit, clothing_exit]
	if garage_exit:
		entrances_list.append(garage_exit)
	for entrance: BuildingEntrance in entrances_list:
		if entrance:
			router.bind_entrance(entrance)


func _configure_interiors() -> void:
	ammu_interior.shop_name = "AMMU-NATION"
	ammu_interior.accent_color = Color("d84b3e")
	ammu_interior.floor_color_primary = Color("252a30")
	ammu_interior.floor_color_secondary = Color("1e2329")
	ammu_interior.wall_color = Color("16191e")
	ammu_interior._apply_theme()


func _bind_transfers() -> void:
	router.actor_transferred.connect(_on_actor_transferred)


func _on_actor_transferred(actor: Node2D, destination_id: StringName, _marker: Node2D) -> void:
	if garage_exit == null and garage_interior:
		garage_exit = garage_interior.get_node_or_null("InteriorExit")
		if garage_exit: router.bind_entrance(garage_exit)

	var dnm = get_tree().get_first_node_in_group("day_night_manager")

	match destination_id:
		&"ammu_interior_spawn":
			_arm_cooldown(ammu_exit)
			actor_entered_interior.emit(actor, &"ammu_nation")
			_frame_interior_camera(actor, ammu_interior.global_position, Vector2(640, 480))
			if dnm and dnm.has_method("set_interior_mode"): dnm.set_interior_mode(true)
		&"garage_interior_spawn":
			if garage_exit: _arm_cooldown(garage_exit)
			actor_entered_interior.emit(actor, &"common_garage")
			_frame_interior_camera(actor, garage_interior.global_position, Vector2(800, 560))
			if dnm and dnm.has_method("set_interior_mode"): dnm.set_interior_mode(true)
		&"clothing_interior_spawn":
			_arm_cooldown(clothing_exit)
			actor_entered_interior.emit(actor, &"clothing_store")
			_frame_interior_camera(actor, clothing_shop.global_position, Vector2(640, 480))
			if dnm and dnm.has_method("set_interior_mode"): dnm.set_interior_mode(true)
		&"ammu_exterior_return":
			_arm_cooldown(ammu_entrance)
			actor_returned_to_district.emit(actor, &"ammu_nation")
			_reset_exterior_camera(actor)
			if dnm and dnm.has_method("set_interior_mode"): dnm.set_interior_mode(false)
		&"garage_exterior_return":
			_arm_cooldown(garage_entrance)
			actor_returned_to_district.emit(actor, &"common_garage")
			_reset_exterior_camera(actor)
			if dnm and dnm.has_method("set_interior_mode"): dnm.set_interior_mode(false)
		&"clothing_exterior_return":
			_arm_cooldown(clothing_entrance)
			actor_returned_to_district.emit(actor, &"clothing_store")
			_reset_exterior_camera(actor)
			if dnm and dnm.has_method("set_interior_mode"): dnm.set_interior_mode(false)


func _frame_interior_camera(actor: Node2D, center_pos: Vector2, size: Vector2) -> void:
	var cam := actor.get_node_or_null("Camera") as Camera2D
	if cam:
		cam.limit_left = int(center_pos.x - size.x * 0.5 - 10)
		cam.limit_top = int(center_pos.y - size.y * 0.5 - 10)
		cam.limit_right = int(center_pos.x + size.x * 0.5 + 10)
		cam.limit_bottom = int(center_pos.y + size.y * 0.5 + 10)

func _reset_exterior_camera(actor: Node2D) -> void:
	var cam := actor.get_node_or_null("Camera") as Camera2D
	if cam:
		cam.limit_left = -10000000
		cam.limit_top = -10000000
		cam.limit_right = 10000000
		cam.limit_bottom = 10000000


func _arm_cooldown(entrance: BuildingEntrance) -> void:
	if entrance == null: return
	entrance.enabled = false
	await get_tree().create_timer(transition_cooldown).timeout
	if is_instance_valid(entrance):
		entrance.enabled = true


func set_exterior_positions(ammu_position: Vector2, garage_position: Vector2) -> void:
	ammu_nation_entrance_position = ammu_position
	common_garage_entrance_position = garage_position
	if is_node_ready():
		_apply_fixed_layout()
