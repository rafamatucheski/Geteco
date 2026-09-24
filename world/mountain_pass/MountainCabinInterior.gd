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
var _rendering_active := false
var _render_clock := 0.0
var cabin_variant := 0
var inline_model_script: Script = preload("res://world/mountain_pass/MountainCabinInline3D.gd")
var inline_mode := false
var inline_facade: Node2D
var inline_entrance: BuildingEntrance
var inline_manager: Node
var _inline_occupied := false
var _inline_floor := PackedVector2Array()
var _actor_scale: Node
var _saved_camera_position := Vector2.ZERO
var overview_camera: Camera2D
const CABIN_RENDER_INTERVAL := 1.0 / 30.0
const INLINE_BOUNDS := Rect2(-1.50, -1.65, 3.0, 3.30)

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

func _build_blackout() -> void:
	if not inline_mode: super._build_blackout()

func _setup_interior_content() -> void:
	_setup_3d_cabin_viewport()
	_setup_heat_source()
	_setup_weapon_stations()
	_build_projected_furniture()
	if inline_mode:
		_inline_floor = PackedVector2Array([
			project_floor(INLINE_BOUNDS.position),
			project_floor(Vector2(INLINE_BOUNDS.end.x, INLINE_BOUNDS.position.y)),
			project_floor(INLINE_BOUNDS.end),
			project_floor(Vector2(INLINE_BOUNDS.position.x, INLINE_BOUNDS.end.y)),
		])
		spawn_point = Marker2D.new()
		spawn_point.name = "SpawnPoint"
		spawn_point.position = project_floor(Vector2(0, 1.38))
		add_child(spawn_point)
	else:
		_create_spawn_and_exit(project_floor(Vector2(0, 3)), project_floor(Vector2(0, 4.15)), &"cabin_exterior_return", "SAIR DO CHALÉ")
		exit_door.custom_prompt_text = "E"
		exit_door.get_node("Facade").hide()
		_setup_overview_camera()

func _setup_overview_camera() -> void:
	overview_camera = Camera2D.new()
	overview_camera.name = "CabinOverview"
	overview_camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	overview_camera.enabled = false
	overview_camera.position = sprite_3d.position
	overview_camera.set_meta("mountain_fixed_framing", true)
	add_child(overview_camera)
	_update_overview_framing()
	get_viewport().size_changed.connect(_update_overview_framing)

func _update_overview_framing() -> void:
	if not is_instance_valid(overview_camera): return
	var screen := get_viewport_rect().size
	var footprint := Vector2(viewport_3d.size) * sprite_3d.scale
	overview_camera.zoom = Vector2.ONE * minf(screen.x / footprint.x, screen.y / footprint.y) * .94

func _setup_weapon_stations() -> void:
	if cabin_variant > 0:
		var cash := preload("res://world/mountain_pass/MountainCashPickup.gd").new()
		cash.name = "CabinCash"
		cash.pickup_id = String(interior_id) + "_cash_01"
		cash.amount = [0, 5000, 850, 450, 1200, 650, 1800][cabin_variant]
		cash.render_host = self
		var cash_floor := Vector2(.43, .27) if inline_mode else Vector2(1.4, 2.5)
		cash.position = project_floor(cash_floor)
		add_child(cash)
		cash.install_model(cabin_3d_world, Vector3(cash_floor.x, .08, cash_floor.y))
		return
	var stations := [
		["LegendaryRifleStation", "hunting_rifle", Vector2(3.1, 1.8), 35],
		["WoodAxeStation", "axe", Vector2(2.5, 2.8), 0],
		["HuntingKnifeStation", "knife", Vector2(-2.55, 1.3), 0],
	]
	if inline_mode:
		stations = [
			["LegendaryRifleStation", "hunting_rifle", Vector2(-.18, -.90), 35],
			["WoodAxeStation", "axe", Vector2(.42, -.15), 0],
			["HuntingKnifeStation", "knife", Vector2(-.31, .73), 0],
		]
	for entry in stations:
		var pickup := preload("res://world/mountain_pass/MountainWeaponPickup.gd").new()
		pickup.name = entry[0]
		pickup.weapon_id = entry[1]
		pickup.pickup_id = "mountain_cabin_" + String(entry[1])
		pickup.ammo = entry[3]
		pickup.render_host = self
		pickup.animate_on_floor = false
		pickup.hover_height = 0.38
		pickup.position = project_floor(entry[2])
		add_child(pickup)
		pickup.install_model(cabin_3d_world, Vector3(entry[2].x, 0.08, entry[2].y))
		_active_weapon_stations.append(pickup)

func _setup_3d_cabin_viewport() -> void:
	viewport_3d = SubViewport.new()
	viewport_3d.name = "CabinViewport3D"
	# The displayed room is about 749x520 pixels. A 1080x750 render target keeps
	# useful supersampling without paying for the former 1.44-million-pixel pass.
	viewport_3d.size = Vector2i(640, 560) if inline_mode else Vector2i(1080, 750)
	viewport_3d.transparent_bg = true
	viewport_3d.own_world_3d = true
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport_3d.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(viewport_3d)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.03, 0.02, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.38, 0.32, 0.26)
	env.ambient_light_energy = 1.0
	var world := viewport_3d.find_world_3d()
	if world:
		world.environment = env

	if inline_mode:
		cabin_3d_world = inline_model_script.new()
		cabin_3d_world.variant = cabin_variant
	elif cabin_variant == 0:
		cabin_3d_world = CABIN_3D_SCENE.new()
	else:
		cabin_3d_world = preload("res://world/mountain_pass/MountainCabinVariants3D.gd").new()
		cabin_3d_world.variant = cabin_variant
	viewport_3d.add_child(cabin_3d_world)

	camera_3d = Camera3D.new()
	camera_3d.name = "CabinCamera3D"
	# Match Maciota's aligned view: parallel projection, no lateral yaw.
	# Finalize before furniture, pickups and exits project their floor positions.
	camera_3d.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera_3d.size = 5.8 if inline_mode else 11.5
	camera_3d.current = true
	viewport_3d.add_child(camera_3d)
	var camera_target := Vector3(0.0, 1.1, 0.0) if inline_mode else Vector3(0.0, 0.6, 0.0)
	camera_3d.look_at_from_position(camera_target + (Vector3(0, 10, 7) if inline_mode else Vector3(0, 18, 15)), camera_target, Vector3.UP)
	# Streamed rooms are built after the first frame. Flush the camera transform
	# before projecting gameplay geometry, or it still uses the origin camera.
	camera_3d.force_update_transform()
	# Project collision footprints and the exit using the final fixed camera pose.
	camera_3d.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera_3d.reset_physics_interpolation()

	sprite_3d = Sprite2D.new()
	sprite_3d.name = "CabinDisplay3D"
	sprite_3d.texture = viewport_3d.get_texture()
	sprite_3d.position = Vector2(0, -20)
	# Escala calibrada para coincidir com a área jogável 2D
	# Preserve the exact previous on-screen footprint after reducing the target.
	if inline_mode:
		var metre := camera_3d.unproject_position(Vector3.RIGHT).distance_to(camera_3d.unproject_position(Vector3.ZERO))
		sprite_3d.scale = Vector2.ONE * 18.0 / metre
		sprite_3d.position = -(camera_3d.unproject_position(Vector3.ZERO) - Vector2(viewport_3d.size) * .5) * sprite_3d.scale
		sprite_3d.hide()
		room_size = Vector2(100, 84)
	else:
		sprite_3d.scale = Vector2(0.52, 0.52) * (1440.0 / 1080.0)
	sprite_3d.z_index = 0
	add_child(sprite_3d)

func _setup_heat_source() -> void:
	# Fonte de calor da lareira para o sistema termal do jogador
	var heat_area := Area2D.new()
	heat_area.name = "FireplaceHeatSource"
	heat_area.add_to_group("heat_source")
	var col := CollisionShape2D.new()
	var circ := CircleShape2D.new()
	circ.radius = 34.0 if inline_mode else 550.0
	col.shape = circ
	col.position = project_floor(Vector2(0, -1.24)) if inline_mode else Vector2(0, -100)
	heat_area.add_child(col)
	add_child(heat_area)

func set_npc_rendering_active(active: bool) -> void:
	super.set_npc_rendering_active(active)
	_rendering_active = active
	if is_instance_valid(overview_camera):
		overview_camera.enabled = active and not inline_mode
		if active and not inline_mode: overview_camera.make_current()
	_render_clock = 0.0
	if viewport_3d:
		viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if cabin_3d_world:
		cabin_3d_world.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if not active and is_instance_valid(_actor_scale):
		_actor_scale.restore()
		_actor_scale.queue_free()
		_actor_scale = null

func _process(delta: float) -> void:
	if inline_mode: _update_inline_occupancy()
	if not _rendering_active or not is_instance_valid(viewport_3d): return
	# The actor adapter renders rigs in this room. Never let the hearth's
	# cache timer freeze their shared depth buffer between presentation frames.
	if int(viewport_3d.get_meta("interior_actor_count", 0)) > 0:
		viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		return
	_render_clock += delta
	if _render_clock >= CABIN_RENDER_INTERVAL:
		_render_clock = fmod(_render_clock, CABIN_RENDER_INTERVAL)
		viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE

func _build_walls_and_floor() -> void:
	# Physical layout follows the same camera as the displayed 3D room.
	pass

func project_floor(point: Vector2) -> Vector2:
	return sprite_3d.position + (camera_3d.unproject_position(Vector3(point.x, 0, point.y)) - Vector2(viewport_3d.size) * 0.5) * sprite_3d.scale

func contains_actor(actor: Node2D) -> bool:
	if inline_mode: return is_instance_valid(actor) and is_visible_in_tree() and contains_point(actor.global_position)
	return is_instance_valid(actor) and actor.get_meta("mountain_interior_id", &"") == interior_id and global_position.distance_to(actor.global_position) < 900.0

func contains_point(point: Vector2) -> bool:
	if inline_mode: return Geometry2D.is_point_in_polygon(to_local(point), _inline_floor)
	return super.contains_point(point)

func attach_inline_facade(facade: Node2D, entrance: BuildingEntrance, manager: Node) -> void:
	if not inline_mode: return
	inline_facade = facade
	inline_entrance = entrance
	inline_manager = manager
	global_position = facade.global_position
	z_as_relative = false
	z_index = 6
	show()
	process_mode = Node.PROCESS_MODE_INHERIT

func _update_inline_occupancy() -> void:
	var actor := get_tree().get_first_node_in_group("player") as Node2D
	var inside: bool = is_instance_valid(actor) and actor.get("is_dead") != true and contains_point(actor.global_position)
	if inside and not _inline_occupied:
		_inline_occupied = true
		sprite_3d.show()
		if is_instance_valid(inline_facade) and inline_facade.has_method("set_inline_occupied"):
			inline_facade.call("set_inline_occupied", true)
		actor.set_meta("mountain_interior", true)
		actor.set_meta("mountain_interior_id", interior_id)
		if is_instance_valid(inline_manager):
			inline_manager.set_active_interior(self)
			inline_manager.actor_entered_interior.emit(actor, interior_id)
		_actor_scale = preload("res://systems/interiors/InteriorActorPresentation.gd").new()
		add_child(_actor_scale)
		_actor_scale.configure(actor, camera_3d, sprite_3d)
		call_deferred("_retry_inline_pickups", actor)
		var cam := actor.get_node_or_null("Camera") as Camera2D
		if cam:
			_saved_camera_position = cam.position
			# Keep the full physical room for occupancy while framing the visible
			# cutaway more tightly on the small cabin facade.
			var camera_rect := Rect2(global_position - Vector2(45, 42.5), Vector2(90, 75)) if inline_mode else get_camera_rect()
			cam.set_meta("compact_interior", camera_rect)
			cam.limit_left = -10000000
			cam.limit_top = -10000000
			cam.limit_right = 10000000
			cam.limit_bottom = 10000000
			cam.reset_smoothing()
	elif not inside and _inline_occupied:
		_leave_inline_room(actor)

func _retry_inline_pickups(actor: Node2D) -> void:
	if not _inline_occupied or not is_instance_valid(actor): return
	var pickups: Array[Area2D] = _active_weapon_stations.duplicate()
	var cash := get_node_or_null("CabinCash") as Area2D
	if cash != null: pickups.append(cash)
	for pickup in pickups:
		if is_instance_valid(pickup) and not bool(pickup.get("collected")) and pickup.global_position.distance_to(actor.global_position) <= 32.0:
			pickup.call("_collect", actor)

func _leave_inline_room(actor: Node2D) -> void:
	_inline_occupied = false
	set_npc_rendering_active(false)
	sprite_3d.hide()
	if is_instance_valid(inline_facade) and inline_facade.has_method("set_inline_occupied"):
		inline_facade.call("set_inline_occupied", false)
	if is_instance_valid(actor):
		actor.remove_meta("mountain_interior")
		actor.remove_meta("mountain_interior_id")
		var cam := actor.get_node_or_null("Camera") as Camera2D
		if cam:
			cam.remove_meta("compact_interior")
			cam.position = _saved_camera_position
			cam.reset_smoothing()
	if is_instance_valid(inline_manager):
		inline_manager.set_active_interior(null)
		inline_manager.actor_returned_to_exterior.emit(actor, interior_id)

func _exit_tree() -> void:
	if _inline_occupied: _leave_inline_room(get_tree().get_first_node_in_group("player") as Node2D)
	if is_instance_valid(_actor_scale): _actor_scale.restore()

func _build_projected_furniture() -> void:
	walls_body = StaticBody2D.new()
	walls_body.name = "CabinProjectedSolids"
	walls_body.collision_layer = 1
	walls_body.collision_mask = 0
	add_child(walls_body)
	if inline_mode:
		preload("res://systems/interiors/InteriorSolidProjection.gd").build(cabin_3d_world, walls_body, project_floor)
		return
	var footprints := {
		"NorthWall": Rect2(-7, -4.8, 14, 0.4),
		"WestWall": Rect2(-7.1, -4.8, 0.35, 9.6),
		"EastWall": Rect2(6.75, -4.8, 0.35, 9.6),
		"SouthWall": Rect2(-7, 4.5, 14, 0.35),

	}
	for id in footprints:
		var rect: Rect2 = footprints[id]
		var shape := CollisionPolygon2D.new()
		shape.name = id
		shape.polygon = PackedVector2Array([project_floor(rect.position), project_floor(Vector2(rect.end.x, rect.position.y)), project_floor(rect.end), project_floor(Vector2(rect.position.x, rect.end.y))])
		walls_body.add_child(shape)
	preload("res://systems/interiors/InteriorSolidProjection.gd").build(cabin_3d_world, walls_body, project_floor)
	# The perspective floor extends beyond the displayed texture at the front.
	# Its clipped edge must also be solid; the exit sensor remains inside it.
	var half := Vector2(viewport_3d.size) * sprite_3d.scale * 0.5
	for edge in [
		[Vector2(0, half.y + 32), Vector2(half.x * 2 + 128, 64)],
		[Vector2(0, -half.y - 32), Vector2(half.x * 2 + 128, 64)],
		[Vector2(-half.x - 32, 0), Vector2(64, half.y * 2)],
		[Vector2(half.x + 32, 0), Vector2(64, half.y * 2)],
	]:
		var boundary := CollisionShape2D.new()
		boundary.position = sprite_3d.position + edge[0]
		var rectangle := RectangleShape2D.new()
		rectangle.size = edge[1]
		boundary.shape = rectangle
		walls_body.add_child(boundary)
