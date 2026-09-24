extends "res://world/harbor/interiors/HarborInteriorBase.gd"

var winter_stock := false
var shop_variant := 0
var inline_mode := false
var inline_model_script: Script
var inline_bounds := Rect2(-3.1, -1.72, 6.2, 3.48)
var inline_cash_floor := Vector2(1.35, -.32)
var inline_region: StringName = &"mountain"
var inline_facade: Node2D
var inline_entrance: BuildingEntrance
var inline_manager: Node
var _inline_occupied := false
var _inline_floor := PackedVector2Array()
var _saved_camera_position := Vector2.ZERO
var shop: ClothingStore
var viewport_3d: SubViewport
var camera_3d: Camera3D
var sprite_3d: Sprite2D
var room_model: Node3D
var overview_camera: Camera2D
var _actor_scale: Node
var _counter_hint: Label
var _counter_point := Vector2.ZERO
const TITLES := ["UNION", "ÚLTIMO ABRIGO", "BOUTIQUE ALPINA", "CASACOS DA VILA"]
const IDS := [&"harbor_clothing_union", &"mountain_outfitters", &"mountain_boutique", &"mountain_village_outfitters"]

func _init() -> void:
	room_size = Vector2(780, 550)

func _build_blackout() -> void:
	if not inline_mode: super._build_blackout()

func _build_walls_and_floor() -> void: pass
func _build_lights() -> void: pass

func _setup_interior_content() -> void:
	if winter_stock and shop_variant == 0: shop_variant = 1
	interior_id = IDS[shop_variant]
	display_name = TITLES[shop_variant]
	viewport_3d = SubViewport.new()
	viewport_3d.name = "ClothingViewport"
	viewport_3d.size = Vector2i(960, 840) if inline_mode else Vector2i(1280, 900)
	viewport_3d.own_world_3d = true
	viewport_3d.transparent_bg = true
	viewport_3d.msaa_3d = Viewport.MSAA_2X
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport_3d)
	var environment := WorldEnvironment.new()
	var lighting := Environment.new()
	lighting.background_mode = Environment.BG_COLOR
	lighting.background_color = Color("161b19")
	lighting.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	lighting.ambient_light_color = Color("c3b79f")
	lighting.ambient_light_energy = .65
	environment.environment = lighting
	viewport_3d.add_child(environment)
	var model_script: Script = inline_model_script if inline_mode and inline_model_script != null else (preload("res://world/mountain_pass/BoutiqueInlineArt3D.gd") if inline_mode else preload("res://world/harbor/interiors/ClothingInteriorArt3D.gd"))
	room_model = model_script.new()
	room_model.variant = shop_variant
	viewport_3d.add_child(room_model)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -25, 0)
	sun.light_color = Color("e6e7dc")
	sun.light_energy = .8
	sun.shadow_enabled = true
	viewport_3d.add_child(sun)
	camera_3d = Camera3D.new()
	camera_3d.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera_3d.size = 10.5 if inline_mode else 12.5
	camera_3d.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport_3d.add_child(camera_3d)
	var target := Vector3(0, 1.9, 0) if inline_mode else Vector3(0, .6, 0)
	camera_3d.look_at_from_position(target + (Vector3(0, 13, 11) if inline_mode else Vector3(0, 18, 15)), target, Vector3.UP)
	camera_3d.force_update_transform()
	camera_3d.reset_physics_interpolation()
	camera_3d.current = true
	sprite_3d = Sprite2D.new()
	sprite_3d.texture = viewport_3d.get_texture()
	if inline_mode:
		var metre := camera_3d.unproject_position(Vector3.RIGHT).distance_to(camera_3d.unproject_position(Vector3.ZERO))
		sprite_3d.scale = Vector2.ONE * 18.0 / metre
		sprite_3d.position = -(camera_3d.unproject_position(Vector3.ZERO) - Vector2(viewport_3d.size) * .5) * sprite_3d.scale
		sprite_3d.hide()
		room_size = Vector2(205, 150)
	else:
		sprite_3d.scale = Vector2.ONE * .6
	add_child(sprite_3d)
	if inline_mode:
		_inline_floor = _project_rect(inline_bounds)
	walls_body = StaticBody2D.new()
	walls_body.name = "ProjectedShopSolids"
	walls_body.collision_layer = 1
	walls_body.collision_mask = 0
	add_child(walls_body)
	preload("res://systems/interiors/InteriorSolidProjection.gd").build(room_model, walls_body, project_floor)
	if inline_mode:
		spawn_point = Marker2D.new()
		spawn_point.name = "SpawnPoint"
		spawn_point.position = project_floor(Vector2(0, 1.1))
		add_child(spawn_point)
	else:
		_create_spawn_and_exit(project_floor(Vector2(0, 3.2)), project_floor(Vector2(0, 4.1)), &"clothing_exit", "E")
		exit_door.custom_prompt_text = "E"
		exit_door.get_node("Facade").hide()
	_counter_point = project_floor(room_model.counter + Vector2(0, .7 if inline_mode else 1.3))
	_counter_hint = Label.new()
	_counter_hint.text = "E"
	_counter_hint.set_meta("interaction_action", &"interact")
	_counter_hint.position = _counter_point + Vector2(-12, -35)
	_counter_hint.size = Vector2(24, 28)
	_counter_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_counter_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_counter_hint.hide()
	add_child(_counter_hint)
	shop = ClothingStore.new()
	shop.winter_stock = winter_stock
	shop.store_title = display_name
	add_child(shop)
	shop.store_closed.connect(func(): set_modal_state(false))
	var cash := preload("res://world/mountain_pass/MountainCashPickup.gd").new()
	cash.name = "ShopCash"
	cash.pickup_id = String(interior_id) + "_cash_01"
	cash.amount = [300, 750, 1250, 450][shop_variant]
	cash.render_host = self
	var cash_floor := inline_cash_floor if inline_mode else Vector2(1.6, 2.9)
	cash.position = project_floor(cash_floor)
	add_child(cash)
	cash.install_model(room_model, Vector3(cash_floor.x, .08, cash_floor.y))
	if not inline_mode:
		overview_camera = Camera2D.new()
		overview_camera.name = "ShopOverview"
		overview_camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
		overview_camera.enabled = false
		overview_camera.set_meta("mountain_fixed_framing", true)
		add_child(overview_camera)
		_update_framing()
		get_viewport().size_changed.connect(_update_framing)

func _project_rect(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([project_floor(rect.position), project_floor(Vector2(rect.end.x, rect.position.y)), project_floor(rect.end), project_floor(Vector2(rect.position.x, rect.end.y))])

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
	z_index = 9 if inline_region == &"harbor" else 6
	show()
	process_mode = Node.PROCESS_MODE_INHERIT

func project_floor(point: Vector2) -> Vector2:
	return sprite_3d.position + (camera_3d.unproject_position(Vector3(point.x, 0, point.y)) - Vector2(viewport_3d.size) * .5) * sprite_3d.scale

func _update_framing() -> void:
	var screen := get_viewport_rect().size
	var footprint := Vector2(viewport_3d.size) * sprite_3d.scale
	overview_camera.zoom = Vector2.ONE * minf(screen.x / footprint.x, screen.y / footprint.y) * .94

func _at_counter(actor: Node2D) -> bool:
	return to_local(actor.global_position).distance_to(_counter_point) < (24 if inline_mode else 52)

func contains_actor(actor: Node2D) -> bool:
	return is_instance_valid(actor) and is_visible_in_tree() and contains_point(actor.global_position)

func on_actor_entered(actor: Node2D) -> void:
	if is_instance_valid(_actor_scale): _actor_scale.restore(); _actor_scale.queue_free()
	_actor_scale = preload("res://systems/interiors/InteriorActorPresentation.gd").new()
	add_child(_actor_scale)
	_actor_scale.configure(actor, camera_3d, sprite_3d)

func _process(_delta: float) -> void:
	if inline_mode: _update_inline_occupancy()
	var actor := get_tree().get_first_node_in_group("player") as Node2D
	_counter_hint.visible = not inline_mode and contains_actor(actor) and _at_counter(actor) and not shop.is_active
	if _counter_hint.visible:
		_counter_hint.text = get_node("/root/GameInput").hint("interact")
		preload("res://ui/InteractionKeycap.gd").sync(_counter_hint, true)

func _update_inline_occupancy() -> void:
	var actor := get_tree().get_first_node_in_group("player") as Node2D
	var inside: bool = is_instance_valid(actor) and actor.get("is_dead") != true and contains_point(actor.global_position)
	if inside and not _inline_occupied:
		_inline_occupied = true
		sprite_3d.show()
		if is_instance_valid(inline_facade):
			if inline_facade.has_method("set_inline_occupied"):
				inline_facade.call("set_inline_occupied", true)
			else:
				inline_facade.sprite_3d.hide()
		actor.set_meta("%s_interior" % inline_region, true)
		actor.set_meta("%s_interior_id" % inline_region, interior_id)
		if is_instance_valid(inline_manager):
			inline_manager.set_active_interior(self)
			inline_manager.actor_entered_interior.emit(actor, interior_id)
		set_npc_rendering_active(true)
		on_actor_entered(actor)
		_collect_entry_cash_if_overlapping.call_deferred(actor)
		var cam := actor.get_node_or_null("Camera") as Camera2D
		if cam:
			_saved_camera_position = cam.position
			var camera_rect := get_camera_rect()
			if inline_region == &"mountain" and shop_variant == 1:
				camera_rect = Rect2(global_position - Vector2(70, 62), Vector2(140, 104))
			cam.set_meta("compact_interior", camera_rect)
			cam.limit_left = -10000000
			cam.limit_top = -10000000
			cam.limit_right = 10000000
			cam.limit_bottom = 10000000
			cam.reset_smoothing()
	elif not inside and _inline_occupied:
		_leave_inline_room(actor)

func _collect_entry_cash_if_overlapping(actor: Node2D) -> void:
	# The Area2D can report body_entered on the threshold before the room's
	# occupancy flag is set. Retry once after physics has refreshed overlaps.
	await get_tree().physics_frame
	if not _inline_occupied or not is_instance_valid(actor): return
	var cash := get_node_or_null("ShopCash") as Area2D
	if is_instance_valid(cash) and not cash.collected and actor in cash.get_overlapping_bodies():
		cash._collect(actor)

func _leave_inline_room(actor: Node2D, notify_manager := true) -> void:
	if shop.is_active: shop.close_store()
	_inline_occupied = false
	set_npc_rendering_active(false)
	sprite_3d.hide()
	if is_instance_valid(inline_facade):
		if inline_facade.has_method("set_inline_occupied"):
			inline_facade.call("set_inline_occupied", false)
		else:
			inline_facade.sprite_3d.show()
	if is_instance_valid(actor):
		actor.remove_meta("%s_interior" % inline_region)
		actor.remove_meta("%s_interior_id" % inline_region)
		var cam := actor.get_node_or_null("Camera") as Camera2D
		if cam:
			cam.remove_meta("compact_interior")
			cam.position = _saved_camera_position
			cam.reset_smoothing()
	if notify_manager and is_instance_valid(inline_manager):
		inline_manager.set_active_interior(null)
		inline_manager.actor_returned_to_exterior.emit(actor, interior_id)

func set_npc_rendering_active(active: bool) -> void:
	super.set_npc_rendering_active(active)
	if viewport_3d: viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if is_instance_valid(overview_camera):
		overview_camera.enabled = active
		if active: overview_camera.make_current()
	if not active and is_instance_valid(_actor_scale):
		_actor_scale.restore()
		_actor_scale.queue_free()
		_actor_scale = null

func _exit_tree() -> void:
	if _inline_occupied: _leave_inline_room(get_tree().get_first_node_in_group("player") as Node2D, false)
	if is_instance_valid(_actor_scale): _actor_scale.restore()

func _unhandled_input(event: InputEvent) -> void:
	var actor := get_tree().get_first_node_in_group("player") as Node2D
	if not contains_actor(actor) or shop.is_active: return
	if event.is_action_pressed("interact") and not event.is_echo() and _at_counter(actor):
		set_modal_state(true)
		shop.open_store(actor)
		get_viewport().set_input_as_handled()
