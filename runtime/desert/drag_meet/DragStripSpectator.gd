extends "res://runtime/desert/drag_meet/DragMeetGuest.gd"
## Chunk-owned spectators retain ordinary civilian damage and retreat behavior.
## Only nearby spectators animate/simulate; no extra population controller.
var _near_clock := 0.0
var _gameplay: Node
var _near := false

func _create_person() -> Node3D:
	return preload("res://runtime/desert/drag_meet/DragSpectatorModel.gd").new()

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if dead or not is_instance_valid(person): return
	# Ordinary retreat, locomotion, damage and menu suppression take priority.
	person.activity = "cheer" if _panic <= 0.0 and not social_paused and automatic_direction.length_squared() < .01 else ""

func _ready() -> void:
	super._ready()
	add_to_group("desert_drag_strip_spectator")
	set_meta("authored_population_owner", "desert_drag_strip")
	var scene := get_tree().current_scene
	if is_instance_valid(scene): _gameplay = scene.get("gameplay")
	if is_instance_valid(_gameplay):
		_gameplay.weapon_fired.connect(_weapon_fired)
		_gameplay.explosion_occurred.connect(_explosion)
	_update_budget()

func _process(delta: float) -> void:
	_near_clock -= delta
	if _near_clock > 0.0: return
	_near_clock = .25
	_update_budget()

func _update_budget() -> void:
	var view_camera := get_viewport().get_camera_3d()
	if not is_instance_valid(view_camera): return
	var radius := 60.0 if _near else 45.0
	_near = view_camera.global_position.distance_squared_to(global_position) < radius * radius
	preload("res://runtime/desert/drag_meet/DragMeetAppearance.gd").set_animation_active(person,not dead and (_near or _panic>0.0))
	set_physics_process(not dead and (_near or _panic > 0.0))

func _weapon_fired(_id: String, origin: Vector3) -> void:
	if global_position.distance_squared_to(origin) < 52.0 * 52.0:
		alert(origin)
		set_physics_process(true)

func _explosion(origin: Vector3, radius: float, _source: Node) -> void:
	if global_position.distance_to(origin) < maxf(65.0, radius * 3.0):
		alert(origin)
		set_physics_process(true)

func alert(origin: Vector3) -> void:
	super.alert(origin)
	if is_instance_valid(person): person.activity = ""
	# Keep retreat behind the authored safety barrier even if the source is
	# behind the spectators. Sideways displacement alone cannot cross the strip.
	var side := signf(_home.z + 1320.0)
	_refuge.z = _home.z + side * .6
	_refuge.x = clampf(_refuge.x, _home.x - 1.0, _home.x + 1.0)
