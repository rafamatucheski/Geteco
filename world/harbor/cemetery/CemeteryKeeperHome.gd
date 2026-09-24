extends "res://world/mountain_pass/MountainStaticModelView.gd"

const HOME_LOCAL := Vector2(-235, -245)
const WORK_LOCAL := Vector2(-65, 274)
const SECRET_FLAG := &"cemetery_keeper_secret_known"
const DEAD_FLAG := &"cemetery_keeper_dead"

var keeper: CharacterBody2D
var room: Node2D
var entrance: BuildingEntrance
var state := "initializing"
var _work_left := 20.0
var _wake_left := 0.0
var _was_inside := false
var _night := false
var _proximity_door_open := false
var _door_tween: Tween
var _wake_tween: Tween

func _ready() -> void:
	name = "KeeperHouse"
	add_to_group("cemetery_keeper_home")
	z_index = 4
	build_view(preload("res://world/harbor/cemetery/CemeteryHouseExterior3D.gd"), 10.8, 20, Vector3(0, 1.1, 0))
	# Refresh the cached facade on arrival/re-entry, including after loading
	# offscreen. No continuous exterior render pass is needed.
	var visibility := VisibleOnScreenNotifier2D.new()
	visibility.rect = sprite_3d.transform * sprite_3d.get_rect()
	add_child(visibility)
	visibility.screen_entered.connect(func(): viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE)
	var footprint := StaticBody2D.new()
	footprint.name = "HouseFootprint"
	footprint.collision_layer = 1
	footprint.collision_mask = 0
	footprint.add_to_group("building_blocker")
	footprint.add_to_group("building_geodata")
	var solids := get_solid_rects()
	footprint.set_meta("solid_rects_local", solids)
	for solid in solids:
		var shape := CollisionShape2D.new()
		var rect_shape := RectangleShape2D.new()
		rect_shape.size = solid.size
		shape.shape = rect_shape
		shape.position = solid.get_center()
		footprint.add_child(shape)
	add_child(footprint)
	entrance = preload("res://scripts/entrances/BuildingEntrance.tscn").instantiate()
	entrance.name = "Entrance"
	entrance.position = project_floor(Vector2(0, 3.05))
	entrance.display_name = "CASA DO COVEIRO"
	entrance.custom_prompt_text = "E"
	entrance.handle_input_locally = false
	entrance.show_interaction_prompt = false
	entrance.show_entrance_marker = false
	entrance.open_duration = .4
	add_child(entrance)
	entrance.add_to_group("harbor_entrance")
	entrance.get_node("Facade").hide()
	var sensor := entrance.get_node("InteractionArea") as Area2D
	sensor.collision_mask = 4
	sensor.position = Vector2(0, 14)
	var return_marker := Marker2D.new()
	return_marker.name = "OutsideReturn"
	return_marker.position = Vector2(0, 26)
	entrance.add_child(return_marker)
	entrance.door_state_changed.connect(func(_door: BuildingEntrance, open: bool):
		model.set_door_open(open)
		_refresh_door_render())
	_build_home.call_deferred()

func _refresh_door_render() -> void:
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	if _door_tween and _door_tween.is_valid(): _door_tween.kill()
	_door_tween = create_tween()
	_door_tween.tween_interval(.5)
	_door_tween.tween_callback(func(): viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE)

func get_solid_rects() -> Array[Rect2]:
	var front_y: float = project_floor(Vector2(0.0, 2.7)).y
	var min_y := 99999.0
	var min_x := 99999.0
	var max_x := -99999.0
	if is_instance_valid(model):
		for child in model.get_children():
			if child is MeshInstance3D and child.mesh != null:
				var aabb: AABB = child.mesh.get_aabb()
				for i in 8:
					var pt3d: Vector3 = child.transform * aabb.get_endpoint(i)
					if pt3d.y > 0.30 or pt3d.z < 2.8:
						var pt2d: Vector2 = project_point(pt3d)
						min_y = minf(min_y, pt2d.y)
						min_x = minf(min_x, pt2d.x)
						max_x = maxf(max_x, pt2d.x)
	if min_x < max_x and min_y < front_y:
		return [Rect2(min_x, min_y, max_x - min_x, front_y - min_y)]
	return []

func _build_home() -> void:
	var world := get_parent().get_parent()
	var manager := world.get_node_or_null("Interiors")
	if not manager:
		push_error("Cemetery house needs HarborInteriorManager")
		return
	room = preload("res://world/harbor/cemetery/CemeteryKeeperRoom.gd").new()
	room.name = "CemeteryKeeperInterior"
	room.home = self
	room.position = global_position
	manager.get_node("InteriorSpaces").add_child(room)
	room.attach_inline_home(self)
	var old_body := get_node_or_null("HouseFootprint") as StaticBody2D
	if old_body:
		old_body.collision_layer = 0
		old_body.queue_free()
	keeper = preload("res://world/harbor/cemetery/CemeteryKeeper.gd").new()
	keeper.name = "Anselmo"
	keeper.home = self
	room.add_child(keeper)
	keeper.route_finished.connect(_on_route_finished)
	keeper.died.connect(func():
		if _wake_tween and _wake_tween.is_valid(): _wake_tween.kill()
		get_node("/root/CampaignState").set_campaign_flag(DEAD_FLAG, true)
		state = "dead")
	if get_node("/root/CampaignState").has_campaign_flag(DEAD_FLAG):
		keeper.is_dead = true
		keeper.hide()
		keeper.collision_layer = 0
		state = "dead"
	elif is_sleep_time():
		_go_to_bed()
	elif hour() >= closing_hour():
		keeper.position = room.project_floor(Vector2(1.5, -.1))
		keeper.set_visual_scale(38)
		state = "home_evening"
	else:
		keeper.position = room.project_floor(Vector2(.8, 1.8))
		keeper.set_visual_scale(38)
		state = "leaving_home"
		keeper.walk_to(PackedVector2Array([room.to_global(room.project_floor(Vector2(0, 2.7)))]))
	_night = is_sleep_time()
	room.art.set_night(_night)

func hour() -> float:
	var weather := get_tree().get_first_node_in_group("day_night_manager")
	return fposmod(float(weather.get("time_of_day")), 1.0) * 24.0 if weather else 12.0

func is_sleep_time() -> bool:
	return hour() < 6.0

func closing_hour() -> float:
	# The default full day lasts only 180 real seconds. Reserve enough real
	# walking time (including the indoor leg) to reach home before midnight.
	var weather := get_tree().get_first_node_in_group("day_night_manager")
	var day_seconds := 180.0
	if weather and weather.get("day_length_seconds") != null:
		day_seconds = maxf(60.0, float(weather.get("day_length_seconds")))
	return maxf(6.0, 24.0 - 30.0 * 24.0 / day_seconds)

func _process(delta: float) -> void:
	if not is_instance_valid(keeper) or not is_instance_valid(room): return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if is_instance_valid(player) and player.global_position.distance_to(Vector2(66000,20000)) < 500.0:
		player.global_position = room.spawn_point.global_position
		player.velocity = Vector2.ZERO
		player.reset_physics_interpolation()
	var door_near: bool = is_instance_valid(player) and player.visible and player.global_position.distance_to(entrance.global_position) < 62.0
	var keeper_near: bool = keeper.global_position.distance_to(entrance.global_position) < 45.0
	var should_open: bool = door_near or keeper_near or room.actor_inside()
	if should_open != _proximity_door_open:
		_proximity_door_open = should_open
		if should_open: entrance.open_door()
		else: entrance.close_door()
	var inside: bool = room.actor_inside()
	if is_sleep_time() != _night:
		_night = is_sleep_time()
		room.art.set_night(_night)
		if inside: room.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	if keeper.is_dead:
		_was_inside = inside
		return
	if not keeper.burial_identity.is_empty(): return
	if inside and is_sleep_time() and state in ["sleeping", "going_to_bed"]: disturb_keeper()
	if not inside and _was_inside and state in ["waking", "hostile"]:
		if _wake_tween and _wake_tween.is_valid(): _wake_tween.kill()
		keeper.set_sleeping(false)
		keeper.hostile = false
		keeper.weapon.hide()
		if keeper.get_parent() == room:
			state = "going_to_bed"
			keeper.walk_to(PackedVector2Array([room.to_global(room.project_floor(Vector2(1.5, -.1)))]))
	_was_inside = inside
	if state == "waking":
		_wake_left -= delta
		if _wake_left <= 0:
			keeper.hostile = true
			state = "hostile"
		return
	if state == "hostile": return
	# Return before midnight; the same resident walks through his own door.
	if (hour() >= closing_hour() or is_sleep_time()) and state in ["working", "walking_to_work"]:
		_return_home()
	elif state == "home_evening" and is_sleep_time():
		_go_to_bed()
	elif not is_sleep_time() and hour() < closing_hour() and state in ["sleeping", "home_evening"]:
		keeper.set_sleeping(false)
		keeper.position = room.project_floor(Vector2(1.5, -.1))
		state = "leaving_home"
		keeper.walk_to(PackedVector2Array([room.to_global(room.project_floor(Vector2(0, 2.7)))]))
	elif state == "working":
		_work_left -= delta
		if _work_left <= 0:
			keeper.work_pose = not keeper.work_pose
			_work_left = 15.0
	if state in ["working", "home_evening"]:
		var actor := get_tree().get_first_node_in_group("player") as Node2D
		if is_instance_valid(actor) and actor.visible and actor.global_position.distance_to(keeper.global_position) < 65 and keeper.speech.text.is_empty():
			keeper.say("E", 1.0)

func _outside_approach() -> Vector2:
	return entrance.get_node("OutsideReturn").global_position

func _on_route_finished() -> void:
	match state:
		"leaving_home":
			if room._resident_presentations.has(keeper):
				var presentation: Node = room._resident_presentations[keeper]
				if is_instance_valid(presentation):
					presentation.restore()
					presentation.queue_free()
				room._resident_presentations.erase(keeper)
			keeper.reparent(self)
			keeper.global_position = entrance.global_position + Vector2(0, 8)
			keeper.reset_physics_interpolation()
			keeper.set_visual_scale(20)
			model.set_door_open(true)
			_refresh_door_render()
			_close_after_passage()
			var cemetery := get_parent() as Node2D
			state = "walking_to_work"
			keeper.walk_to(PackedVector2Array([cemetery.to_global(Vector2(HOME_LOCAL.x, -145)), cemetery.to_global(Vector2(-65, -145)), cemetery.to_global(WORK_LOCAL)]))
		"walking_to_work":
			state = "working"
			keeper.work_pose = true
		"returning_home":
			keeper.reparent(room)
			keeper.position = room.project_floor(Vector2(0, 2.7))
			keeper.reset_physics_interpolation()
			keeper.set_visual_scale(38)
			if room.can_process(): room.set_npc_rendering_active(true)
			model.set_door_open(true)
			_refresh_door_render()
			_close_after_passage()
			state = "going_to_bed"
			keeper.walk_to(PackedVector2Array([room.to_global(room.project_floor(Vector2(1.5, -.1)))]))
		"going_to_bed":
			if is_sleep_time(): _go_to_bed()
			else: state = "home_evening"

func _close_after_passage() -> void:
	await get_tree().create_timer(1.2).timeout
	if is_instance_valid(model):
		model.set_door_open(false)
		_refresh_door_render()

func _return_home() -> void:
	state = "returning_home"
	var cemetery := get_parent() as Node2D
	keeper.walk_to(PackedVector2Array([cemetery.to_global(Vector2(-65, -145)), cemetery.to_global(Vector2(HOME_LOCAL.x, -145)), entrance.global_position + Vector2(0, 8)]))

func _go_to_bed() -> void:
	state = "sleeping"
	keeper.hostile = false
	keeper.set_visual_scale(38)
	keeper.position = room.project_floor(Vector2(2.98, -.92))
	keeper.set_sleeping(true)
	keeper.reset_physics_interpolation()

func disturb_keeper() -> void:
	if keeper.is_dead or state in ["waking", "hostile"]: return
	if keeper.get_parent() != room: return
	state = "waking"
	_wake_left = 1.6
	keeper.walk_to(PackedVector2Array())
	keeper.say("ANSELMO: Quem entrou?! Fora da minha casa!", 5)
	room.show_message("ANSELMO: Fora da minha casa!")
	keeper.set_sleeping(false)
	keeper.model.rotation.x = -PI / 2
	keeper.model.position.y = .68
	keeper.model.shovel.hide()
	if _wake_tween and _wake_tween.is_valid(): _wake_tween.kill()
	_wake_tween = create_tween().set_parallel(true)
	_wake_tween.tween_property(keeper.model, "rotation:x", 0.0, .85)
	_wake_tween.tween_property(keeper.model, "position:y", 0.0, .85)
	_wake_tween.tween_property(keeper, "position", room.project_floor(Vector2(1.5, -.1)), 1.0)

func can_engage(actor: Node2D) -> bool:
	return is_instance_valid(actor) and is_instance_valid(room) and room.actor_inside() and keeper.get_parent() == room and keeper.global_position.distance_to(actor.global_position) < 550

func reveal_secret() -> void:
	if is_sleep_time() or keeper.hostile: return
	get_node("/root/CampaignState").set_campaign_flag(SECRET_FLAG, true)
	var text := "O túmulo de Samuel está vazio. Anselmo escondeu a última carta junto ao muro sudeste: siga as pegadas e a fita, depois do último banco."
	room.show_message(text)
	var actor := get_tree().get_first_node_in_group("player")
	if not room.actor_inside() and actor and actor.has_method("_show_weapon_notice"):
		actor._show_weapon_notice("SEGREDO DO COVEIRO: carta no canto sudeste do cemitério.")
	keeper.say("ANSELMO: Samuel não está lá. A carta, junto ao muro sudeste... não mostre a ninguém.", 8)

func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(keeper) or keeper.is_dead or is_sleep_time(): return
	if not event.is_action_pressed("interact") or event.is_echo(): return
	var actor := get_tree().get_first_node_in_group("player") as Node2D
	if is_instance_valid(actor) and actor.visible and actor.global_position.distance_to(keeper.global_position) < 65:
		get_viewport().set_input_as_handled()
		reveal_secret()
