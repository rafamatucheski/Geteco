class_name HarborInteriorBase
extends Node2D

## Base class for Breakwater preview interiors.
## Provides solid walls, blackout boundary, lighting fixtures, spawn points, and exit doors.

signal actor_entered(actor: Node2D)
signal actor_exited(actor: Node2D)
signal modal_opened()
signal modal_closed()

func set_modal_state(active: bool) -> void:
	if active:
		modal_opened.emit()
	else:
		modal_closed.emit()

@export var interior_id: StringName = &"interior"
@export var display_name: String = "INTERIOR"
@export var room_size: Vector2 = Vector2(700, 480)
@export var wall_color: Color = Color("#11161b")
@export var floor_color: Color = Color("#1a2228")
@export var accent_color: Color = Color("#e8b44f")
@export var entrance_north: bool = false

var spawn_point: Marker2D
var exit_door: BuildingEntrance
var walls_body: StaticBody2D
var interactive_stations: Array[Dictionary] = []
var _resident_presentations: Dictionary = {}

const ENTRANCE_SCENE: PackedScene = preload("res://scripts/entrances/BuildingEntrance.tscn")

func _ready() -> void:
	add_to_group("harbor_interior")
	_build_blackout()
	_build_walls_and_floor()
	_build_lights()
	_setup_interior_content()
	# Nobody is inside any interior at boot: every embedded 3D-rig NPC (JagerNPC,
	# HarborConversationalNPC) starts with its SubViewport render pass disabled.
	# HarborInteriorManager re-enables it for the one interior the actor is
	# actually in and disables it again on exit — see set_npc_rendering_active().
	set_npc_rendering_active(false)

func _build_blackout() -> void:
	var blackout := Polygon2D.new()
	blackout.name = "Blackout"
	blackout.color = Color(0.02, 0.03, 0.04, 1.0)
	blackout.polygon = PackedVector2Array([
		Vector2(-2500, -2500), Vector2(2500, -2500),
		Vector2(2500, 2500), Vector2(-2500, 2500)
	])
	blackout.z_index = -5
	add_child(blackout)

func _build_walls_and_floor() -> void:
	# Floor polygon
	var floor_poly := Polygon2D.new()
	floor_poly.name = "Floor"
	var half := room_size * 0.5
	floor_poly.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y)
	])
	floor_poly.color = floor_color
	floor_poly.z_index = 0
	add_child(floor_poly)

	# Border trim
	var trim := Line2D.new()
	trim.name = "FloorTrim"
	trim.points = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
		Vector2(-half.x, -half.y)
	])
	trim.width = 3.0
	trim.default_color = accent_color.darkened(0.2)
	trim.z_index = 1
	add_child(trim)

	# Physical Solid Walls
	walls_body = StaticBody2D.new()
	walls_body.name = "InteriorSolidWalls"
	walls_body.collision_layer = 1
	walls_body.collision_mask = 0

	var wall_thk := 40.0
	# Top wall
	_add_wall_segment(walls_body, Vector2(0, -half.y - wall_thk * 0.5), Vector2(room_size.x + wall_thk * 2, wall_thk))
	# Bottom wall — solid, unless a subclass declares vehicle-bay gaps (a
	# pedestrian exit never needs one: the actor is teleported to the exterior
	# well before reaching this wall, but a vehicle driving itself out through
	# the gate has to physically pass through where the wall would otherwise
	# be, or it collides and stops dead a few px short of the exit sensor).
	var south_gaps := _get_south_wall_gaps()
	if south_gaps.is_empty():
		_add_wall_segment(walls_body, Vector2(0, half.y + wall_thk * 0.5), Vector2(room_size.x + wall_thk * 2, wall_thk))
	else:
		_build_south_wall_with_gaps(walls_body, half, wall_thk, south_gaps)
	# Left wall
	_add_wall_segment(walls_body, Vector2(-half.x - wall_thk * 0.5, 0), Vector2(wall_thk, room_size.y + wall_thk * 2))
	# Right wall
	_add_wall_segment(walls_body, Vector2(half.x + wall_thk * 0.5, 0), Vector2(wall_thk, room_size.y + wall_thk * 2))

	add_child(walls_body)

## Override to open gaps in the south wall for vehicles that must physically
## drive out through it. Each entry is Vector2(gap_center_x, gap_width) in
## this interior's local space. Empty by default (a fully solid wall).
func _get_south_wall_gaps() -> Array:
	return []

func _build_south_wall_with_gaps(body: StaticBody2D, half: Vector2, wall_thk: float, gaps: Array) -> void:
	var sorted_gaps: Array = gaps.duplicate()
	sorted_gaps.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var y := half.y + wall_thk * 0.5
	var cursor := -half.x - wall_thk
	var right_edge := half.x + wall_thk
	for gap in sorted_gaps:
		var gap_left: float = gap.x - gap.y * 0.5
		var gap_right: float = gap.x + gap.y * 0.5
		if gap_left > cursor:
			var seg_width := gap_left - cursor
			_add_wall_segment(body, Vector2(cursor + seg_width * 0.5, y), Vector2(seg_width, wall_thk))
		cursor = maxf(cursor, gap_right)
	if right_edge > cursor:
		var seg_width := right_edge - cursor
		_add_wall_segment(body, Vector2(cursor + seg_width * 0.5, y), Vector2(seg_width, wall_thk))

func _add_wall_segment(body: StaticBody2D, pos: Vector2, sz: Vector2) -> void:
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = sz
	col.shape = rect
	col.position = pos
	body.add_child(col)

	var poly := Polygon2D.new()
	poly.color = wall_color
	var h := sz * 0.5
	poly.polygon = PackedVector2Array([
		pos + Vector2(-h.x, -h.y), pos + Vector2(h.x, -h.y),
		pos + Vector2(h.x, h.y), pos + Vector2(-h.x, h.y)
	])
	poly.z_index = 4
	add_child(poly)

func _build_lights() -> void:
	var half := room_size * 0.5
	var light_offsets := [
		Vector2(-half.x * 0.5, -half.y * 0.5),
		Vector2(half.x * 0.5, -half.y * 0.5),
		Vector2(-half.x * 0.5, half.y * 0.5),
		Vector2(half.x * 0.5, half.y * 0.5)
	]

	for pos in light_offsets:
		var fixture := Polygon2D.new()
		fixture.color = Color("#2d3436")
		fixture.polygon = PackedVector2Array([
			Vector2(-24, -4), Vector2(24, -4), Vector2(24, 4), Vector2(-24, 4)
		])
		fixture.position = pos
		fixture.z_index = 6
		add_child(fixture)

		var tube := Polygon2D.new()
		tube.color = Color("#dfe6e9")
		tube.polygon = PackedVector2Array([
			Vector2(-20, -2), Vector2(20, -2), Vector2(20, 2), Vector2(-20, 2)
		])
		fixture.add_child(tube)

		var p_light := PointLight2D.new()
		p_light.color = Color(0.95, 0.98, 1.0)
		p_light.energy = 0.85
		p_light.position = pos
		p_light.z_index = 6

		var grad := Gradient.new()
		grad.colors = PackedColorArray([Color(1, 1, 1, 0.60), Color(1, 1, 1, 0)])
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.width = 300
		tex.height = 300
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		p_light.texture = tex
		add_child(p_light)

func _create_spawn_and_exit(spawn_pos: Vector2, exit_pos: Vector2, exit_dest_id: StringName, exit_label: String = "SAIR", north: bool = false) -> void:
	spawn_point = Marker2D.new()
	spawn_point.name = "SpawnPoint"
	spawn_point.position = spawn_pos
	add_child(spawn_point)

	exit_door = ENTRANCE_SCENE.instantiate() as BuildingEntrance
	exit_door.name = "InteriorExit"
	exit_door.position = exit_pos
	exit_door.rotation = PI if north else 0.0
	exit_door.destination_id = exit_dest_id
	exit_door.display_name = exit_label
	exit_door.entrance_kind = BuildingEntrance.EntranceKind.BUILDING
	exit_door.panel_slide_distance = 22.0
	exit_door.add_to_group("harbor_interior_exit")

	var sensor := exit_door.get_node_or_null("InteractionArea") as Area2D
	if sensor:
		sensor.position = Vector2(0, -25)
		sensor.collision_mask = 7
		sensor.body_entered.connect(func(body: Node2D):
			if body.is_in_group("vehicle") and body.get("is_driven_by_player") == true:
				if not body in exit_door._nearby_actors:
					exit_door._nearby_actors.append(body)
					exit_door.actor_approached.emit(exit_door, body)
					exit_door._refresh_prompt()
		)
		sensor.body_exited.connect(func(body: Node2D):
			if body in exit_door._nearby_actors:
				exit_door._nearby_actors.erase(body)
				exit_door.actor_departed.emit(exit_door, body)
				exit_door._refresh_prompt()
		)

	var prompt := exit_door.get_node_or_null("Prompt") as Label
	if prompt:
		prompt.position = Vector2(-90, 36 if north else -44)

	add_child(exit_door)

func get_camera_rect() -> Rect2:
	return Rect2(global_position - room_size * 0.5, room_size)

## "Este ator esta dentro deste comodo?" — pergunta de pertencimento, separada
## do enquadramento da camera. Por padrao sao a mesma coisa; um interior com
## area jogavel fora do quadro (a pista do portao da garagem) sobrescreve so
## esta, sem mexer no zoom.
func contains_point(point: Vector2) -> bool:
	return get_camera_rect().has_point(point)

func contains_actor(actor: Node2D) -> bool:
	return is_instance_valid(actor) and is_visible_in_tree() and contains_point(actor.global_position)

func add_cash_reward(model: Node3D, floor_position: Vector2, amount: int, reward_id: String) -> Area2D:
	var reward := preload("res://world/mountain_pass/MountainCashPickup.gd").new()
	reward.name = "RoomCash"
	reward.pickup_id = reward_id
	reward.amount = amount
	reward.render_host = self
	reward.position = call("project_floor", floor_position)
	add_child(reward)
	reward.install_model(model, Vector3(floor_position.x, .08, floor_position.y))
	return reward

## Every interior NPC that composites a 3D rig into a Sprite2D (JagerNPC,
## HarborConversationalNPC) exposes its render target as `viewport_3d`. This
## interior is always instantiated far away in world space but never removed,
## so without this the NPC would render a full 3D pass every frame even while
## nobody is inside. Toggled by HarborInteriorManager on actual enter/exit.
func set_npc_rendering_active(active: bool) -> void:
	# Projected rooms admit their residents to the same depth buffer as furniture.
	# The shared adapter restores each rig before an empty room is suspended.
	if not active:
		for presentation in _resident_presentations.values():
			if is_instance_valid(presentation):
				presentation.restore()
				presentation.queue_free()
		_resident_presentations.clear()
	elif get("camera_3d") is Camera3D and get("sprite_3d") is Sprite2D:
		for resident in find_children("*", "CharacterBody2D", true, false):
			# Store fitting previews belong to their own viewport, not the room.
			if resident.get_viewport() != get_viewport(): continue
			var ancestor := resident.get_parent()
			while ancestor != null and ancestor != self and not ancestor is Control and not ancestor is CanvasLayer:
				ancestor = ancestor.get_parent()
			if ancestor is Control or ancestor is CanvasLayer: continue
			if _resident_presentations.has(resident): continue
			var rig = resident.get("model_root")
			if rig == null: rig = resident.get("model")
			if not rig is Node3D: continue
			var presentation := preload("res://systems/interiors/InteriorActorPresentation.gd").new()
			add_child(presentation)
			presentation.configure(resident, get("camera_3d"), get("sprite_3d"))
			_resident_presentations[resident] = presentation
	var mode := SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	for child in find_children("*", "", true, false):
		var vp = child.get("viewport_3d")
		if vp is SubViewport:
			vp.render_target_update_mode = mode

## Virtual method to be overridden by subclasses.
func _setup_interior_content() -> void:
	pass
