class_name MountainCabinInterior
extends "res://world/harbor/interiors/HarborInteriorBase.gd"

## Interior 3D Autêntico do Chalé Alpino de Montanha:
## Renderiza em tempo real um cenário 3D volumétrico completo (MountainCabin3D) via SubViewport,
## com paredes de toras, lareira monumental de pedras, fogão de ferro fundido, chaleira de cobre,
## sofá Chesterfield em couro conhaque, mesa de tronco, cama de 4 postes com colcha patchwork,
## bar dos caçadores e rádio militar, com armas coletáveis no piso livre.
## Mantém os colisores físicos 2D, fontes de calor ('heat_source') e gatilhos de saída intactos.

const CABIN_3D_SCENE := preload("res://world/mountain_pass/MountainCabin3D.gd")

var viewport_3d: SubViewport
var sprite_3d: Sprite2D
var cabin_3d_world: Node3D
var camera_3d: Camera3D
var _active_weapon_stations: Array[Area2D] = []

func _init() -> void:
	interior_id = &"mountain_cabin"
	display_name = "CHALE DA SERRA — REFÚGIO DOS CAÇADORES (3D)"
	room_size = Vector2(720, 500)
	wall_color = Color("#18100a")
	floor_color = Color("#2a180d")
	accent_color = Color("#d35400")

func _build_lights() -> void:
	# A iluminação completa, sombras dinâmicas e fogo vivo são gerados em 3D real pelo MountainCabin3D
	pass

func _setup_interior_content() -> void:
	_setup_3d_cabin_viewport()
	_setup_heat_source()
	_setup_weapon_stations()
	_build_projected_furniture()
	_create_spawn_and_exit(project_floor(Vector2(0, 3)), project_floor(Vector2(0, 4.15)), &"cabin_exterior_return", "SAIR DO CHALÉ")
	exit_door.custom_prompt_text = "[E] SAIR DO CHALÉ"
	exit_door.get_node("Facade").hide()

func _setup_weapon_stations() -> void:
	for entry in [
		["LegendaryRifleStation", "hunting_rifle", Vector2(3.1, 1.8), 35],
		["HuntingKnifeStation", "knife", Vector2(-2.55, 1.3), 0],
	]:
		var pickup := preload("res://world/mountain_pass/MountainWeaponPickup.gd").new()
		pickup.name = entry[0]
		pickup.weapon_id = entry[1]
		pickup.pickup_id = "mountain_cabin_" + String(entry[1])
		pickup.ammo = entry[3]
		pickup.position = project_floor(entry[2])
		add_child(pickup)
		pickup.install_model(cabin_3d_world, Vector3(entry[2].x, 0.08, entry[2].y))
		_active_weapon_stations.append(pickup)

func _setup_3d_cabin_viewport() -> void:
	viewport_3d = SubViewport.new()
	viewport_3d.name = "CabinViewport3D"
	viewport_3d.size = Vector2i(1440, 1000)
	viewport_3d.transparent_bg = true
	viewport_3d.own_world_3d = true
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_3d.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(viewport_3d)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.03, 0.02, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.30, 0.28)
	env.ambient_light_energy = 1.0
	var world := viewport_3d.find_world_3d()
	if world:
		world.environment = env

	cabin_3d_world = CABIN_3D_SCENE.new()
	viewport_3d.add_child(cabin_3d_world)

	camera_3d = Camera3D.new()
	camera_3d.name = "CabinCamera3D"
	camera_3d.fov = 46.0
	camera_3d.current = true
	viewport_3d.add_child(camera_3d)
	camera_3d.look_at_from_position(Vector3(3.2, 8.4, 8.5), Vector3(0.0, 1.2, -0.6), Vector3.UP)

	sprite_3d = Sprite2D.new()
	sprite_3d.name = "CabinDisplay3D"
	sprite_3d.texture = viewport_3d.get_texture()
	sprite_3d.position = Vector2(0, -20)
	# Escala calibrada para coincidir com a área jogável 2D
	sprite_3d.scale = Vector2(0.52, 0.52)
	sprite_3d.z_index = 0
	add_child(sprite_3d)

func _setup_heat_source() -> void:
	# Fonte de calor da lareira para o sistema termal do jogador
	var heat_area := Area2D.new()
	heat_area.name = "FireplaceHeatSource"
	heat_area.add_to_group("heat_source")
	var col := CollisionShape2D.new()
	var circ := CircleShape2D.new()
	circ.radius = 550.0
	col.shape = circ
	col.position = Vector2(0, -100)
	heat_area.add_child(col)
	add_child(heat_area)

func set_npc_rendering_active(active: bool) -> void:
	super.set_npc_rendering_active(active)
	if viewport_3d:
		viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if cabin_3d_world:
		cabin_3d_world.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED

func _build_walls_and_floor() -> void:
	# Physical layout follows the same camera as the displayed 3D room.
	pass

func project_floor(point: Vector2) -> Vector2:
	return sprite_3d.position + (camera_3d.unproject_position(Vector3(point.x, 0, point.y)) - Vector2(viewport_3d.size) * 0.5) * sprite_3d.scale

func _build_projected_furniture() -> void:
	walls_body = StaticBody2D.new()
	walls_body.name = "CabinProjectedSolids"
	walls_body.collision_layer = 1
	walls_body.collision_mask = 0
	add_child(walls_body)
	var footprints := {
		"NorthWall": Rect2(-7, -4.8, 14, 0.4),
		"WestWall": Rect2(-7.1, -4.8, 0.35, 9.6),
		"EastWall": Rect2(6.75, -4.8, 0.35, 9.6),
		"SouthWall": Rect2(-7, 4.5, 14, 0.35),
		"Fireplace": Rect2(-1.8, -4.6, 3.6, 1.45),
		"Sofa": Rect2(-2.85, -2.5, 1.25, 2.6),
		"Armchair": Rect2(1.65, -1.95, 1.15, 1.5),
		"CoffeeTable": Rect2(-0.8, -1.7, 1.6, 1.0),
		"Bed": Rect2(-5.95, 0.35, 2.3, 2.9),
		"BedsideTable": Rect2(-3.55, 0.5, 0.7, 0.6),
		"Chest": Rect2(-5.5, 3.3, 1.4, 0.6),
		"Counter": Rect2(-6, -3.25, 2.4, 0.9),
		"CounterReturn": Rect2(-4.25, -2.35, 0.9, 1.1),
		"RangerDesk": Rect2(4.2, -0.9, 1.2, 2.2)
	}
	for id in footprints:
		var rect: Rect2 = footprints[id]
		var shape := CollisionPolygon2D.new()
		shape.name = id
		shape.polygon = PackedVector2Array([project_floor(rect.position), project_floor(Vector2(rect.end.x, rect.position.y)), project_floor(rect.end), project_floor(Vector2(rect.position.x, rect.end.y))])
		walls_body.add_child(shape)
