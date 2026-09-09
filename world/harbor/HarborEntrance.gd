@tool
extends "res://scripts/entrances/BuildingEntrance.gd"

## Visual-only facade stage, reusing BuildingEntrance's sensor, signals and API.
## The building solid remains intact until a real interior is explicitly wired.
@export var role := "garage"
@export var door_width := 120.0
@export var door_height := 38.0
@export var accent_color := Color("#d7ae68")
@export var interior_available := false
var open_amount := 0.0:
	set(value):
		open_amount = clampf(value, 0.0, 1.0)
		queue_redraw()
var _away_time := 0.0


func _ready() -> void:
	# The inherited scene owns these nodes. Its textual prompt/static panels are
	# replaced by this code-native animated facade, not layered over another door.
	$Facade.hide()
	$Prompt.text = ""
	$InteractionArea.collision_mask = 7 if role in ["garage", "fire_station"] else 4
	$InteractionArea.position = Vector2(0, 40)
	var sensor_shape := RectangleShape2D.new()
	sensor_shape.size = Vector2(door_width + 12, 64)
	$InteractionArea/CollisionShape2D.shape = sensor_shape
	handle_input_locally = false
	open_duration = 0.55
	close_duration = 0.45
	auto_close_delay = 0.7
	super._ready()
	add_to_group("harbor_entrance")
	var outside := Marker2D.new()
	outside.name = "OutsideReturn"
	outside.position = Vector2(0, 42)
	add_child(outside)
	set_process(not Engine.is_editor_hint())
	queue_redraw()


func _refresh_prompt() -> void:
	var prompt := get_node_or_null("Prompt") as Label
	if prompt != null:
		prompt.text = ""
		prompt.hide()


func _on_body_entered(body: Node2D) -> void:
	if not _accepts_actor(body):
		return
	if body not in _nearby_actors:
		_nearby_actors.append(body)
		actor_approached.emit(self, body)
	if enabled and is_actor_in_range(body):
		_away_time = 0.0
		open_door()


func _process(delta: float) -> void:
	# A parked car can become player-driven without crossing the sensor again.
	# Likewise, an abandoned car must not keep a shutter open forever.
	for actor in _nearby_actors.duplicate():
		if not is_instance_valid(actor) or not _accepts_actor(actor):
			_nearby_actors.erase(actor)
	for body in _sensor.get_overlapping_bodies():
		if body not in _nearby_actors and _accepts_actor(body):
			_on_body_entered(body)
	if get_nearest_actor() != null and enabled:
		_away_time = 0.0
	elif _door_open and not _busy:
		_away_time += delta
		if _away_time >= auto_close_delay:
			close_door()


func _accepts_actor(body: Node2D) -> bool:
	if not is_instance_valid(body):
		return false
	if body.is_in_group(actor_group):
		return true
	if not (body.is_in_group("vehicle") and body.get("is_driven_by_player") == true):
		return false
	if role == "garage":
		return true
	if role == "fire_station":
		# Only the station's own bay trucks (tagged with a "home_bay" meta by
		# HarborFireStationInterior) may drive in; an arbitrary city vehicle
		# must not be teleported into a bay that already holds its resident
		# truck.
		return body.has_meta("home_bay")
	return false


func request_interaction(actor: Node2D) -> bool:
	if not enabled or _busy or not is_actor_in_range(actor):
		return false
	if interior_available:
		return super.request_interaction(actor)
	# No destination event, actor displacement or pretend transition at this stage.
	open_door()
	return true


func _set_door_open(value: bool) -> void:
	if _door_open == value and (is_equal_approx(open_amount, 1.0 if value else 0.0) or (_door_tween != null and _door_tween.is_running())):
		return
	_door_open = value
	if value:
		_away_time = 0.0
	if _door_tween != null:
		_door_tween.kill()
	_door_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_door_tween.tween_property(self, "open_amount", 1.0 if value else 0.0, open_duration if value else close_duration)
	door_state_changed.emit(self, value)


func get_entrance_state() -> Dictionary:
	return {
		"role": role, "width": door_width, "open_amount": open_amount,
		"threshold_position": global_position,
		"approach_position": to_global(Vector2(0, 42)),
		"outward": global_transform.y.normalized(),
		"interior_available": interior_available, "destination_id": destination_id,
		"return_marker": NodePath("OutsideReturn"),
	}


func _draw() -> void:
	var frame := Rect2(-door_width * 0.5 - 5, -door_height - 5, door_width + 10, door_height + 10)
	var opening := Rect2(-door_width * 0.5, -door_height, door_width, door_height)
	draw_rect(frame, Color("#25323a"))
	draw_rect(frame.grow(-2), accent_color.darkened(0.42), false, 2)
	draw_rect(opening, Color("#101d25"))
	# Soft light suggests a future vestibule, not a painted navigable interior.
	draw_rect(Rect2(opening.position + Vector2(2, 2), opening.size - Vector2(4, 4)), Color(0.36, 0.46, 0.43, open_amount * 0.35))
	if role in ["garage", "fire_station", "ammunation"]:
		var remaining := door_height * (1.0 - open_amount)
		if remaining > 0.1:
			var shutter := Rect2(opening.position, Vector2(door_width, remaining))
			draw_rect(shutter, accent_color.darkened(0.42))
			for rib in range(4, int(remaining), 5):
				draw_line(shutter.position + Vector2(2, rib), shutter.position + Vector2(door_width - 2, rib), accent_color.lightened(0.12), 1.2)
			draw_line(Vector2(-door_width / 2, -door_height + remaining), Vector2(door_width / 2, -door_height + remaining), Color("#c9d2cc"), 3)
		# Roller housing never spills onto the authored approach.
		draw_rect(Rect2(-door_width / 2 - 3, -door_height - 5, door_width + 6, 6), Color("#64716d"))
	else:
		var half := door_width * 0.5 * (1.0 - open_amount)
		if half > 0.1:
			for side in [-1.0, 1.0]:
				var x := -door_width / 2 if side < 0 else door_width / 2 - half
				var panel := Rect2(x, -door_height, half, door_height)
				draw_rect(panel, Color("#59777b") if role != "morgue" else Color("#66707c"))
				draw_rect(panel, accent_color, false, 1.5)
				if half > 8:
					draw_line(panel.position + Vector2(3, 5), panel.position + Vector2(half - 3, 11), Color("#b2d3cf"), 1.5)
					draw_line(Vector2(panel.get_center().x, -door_height * 0.55), Vector2(panel.get_center().x, -door_height * 0.3), Color("#e2ded0"), 2)
	draw_line(Vector2(-door_width / 2, 2), Vector2(door_width / 2, 2), Color("#b9b7a4"), 3)
	draw_circle(Vector2(door_width / 2 + 2, -door_height + 3), 2, Color("#91cbb0") if _door_open else accent_color)
