extends Control
## Mira de arma de fogo e direção/alcance de corpo a corpo, guiadas pelas regras de contato reais.
var gameplay: Node
var blocked := false
var world_point := Vector3.ZERO
var confirmed := false
var melee := false
var in_range := false
var _reach_visible := false
var _reach_from := Vector2.ZERO
var _reach_to := Vector2.ZERO
var _reach_tick := Vector2.ZERO
var _contact_point := Vector2.ZERO
var _contact_visible := false

func _ready() -> void:
	name = "AimReticle"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100
	hide()

func _process(_delta: float) -> void:
	if not is_instance_valid(gameplay) or get_tree().paused:
		hide()
		return
	var next_melee: bool = gameplay.melee_feedback_active()
	if melee != next_melee:
		melee = next_melee
		queue_redraw()
	visible = melee or gameplay.aim_feedback_active()
	if not visible: return
	var camera: Camera3D = gameplay.camera
	if not is_instance_valid(camera):
		hide()
		return
	# O FullSession resolve a entrada do mouse no processamento de render. Consulta depois
	# dele (prioridade 100), para o marcador usar o cursor e o cano deste quadro.
	var feedback: Dictionary = gameplay.melee_feedback() if melee else gameplay.aim_feedback()
	var next_confirmed: bool = bool(feedback.get("confirmed", false)) if melee else gameplay.hitmarker_active()
	if confirmed != next_confirmed:
		confirmed = next_confirmed
		queue_redraw()
	world_point = feedback.point
	if blocked != bool(feedback.blocked):
		blocked = feedback.blocked
		queue_redraw()
	var controls := get_node_or_null("/root/GameInput")
	var pointer_aim: bool = controls == null or (not controls.using_gamepad and not controls.get_meta("touch_controls_active",false) and controls.touch_aim.is_zero_approx())
	visible = pointer_aim or not camera.is_position_behind(world_point)
	if not visible: return
	# Obstruction changes feedback colour, never the mouse cursor position.
	position = get_viewport().get_mouse_position() if pointer_aim else camera.unproject_position(world_point)
	if melee:
		in_range = bool(feedback.get("in_range", false))
		_project_melee_reach(camera, feedback)
		queue_redraw()

func _project_melee_reach(camera: Camera3D, feedback: Dictionary) -> void:
	var origin: Vector3 = feedback.origin
	var direction: Vector3 = feedback.direction
	var reach: float = float(feedback.reach)
	var endpoint: Vector3 = origin + direction * reach
	if blocked: endpoint = world_point
	var start: Vector3 = origin + direction * minf(0.6, reach * 0.3)
	_reach_visible = not camera.is_position_behind(start) and not camera.is_position_behind(endpoint)
	_contact_visible = in_range and not blocked and not camera.is_position_behind(world_point)
	if _contact_visible: _contact_point = camera.unproject_position(world_point) - position
	if not _reach_visible: return
	_reach_from = camera.unproject_position(start) - position
	_reach_to = camera.unproject_position(endpoint) - position
	var axis := _reach_to - _reach_from
	_reach_tick = Vector2(-axis.y, axis.x).normalized() * 3.5

func _draw_melee() -> void:
	var ink := Color("ffb568") if blocked else (Color("d8f5b3") if in_range else Color("c7cbd0"))
	if _reach_visible and not _contact_visible:
		# Só o ponto final: sem linha móvel atravessando a cena.
		draw_line(_reach_to - _reach_tick, _reach_to + _reach_tick, Color(0.02, 0.03, 0.04, 0.4), 2.5, true)
		draw_line(_reach_to - _reach_tick, _reach_to + _reach_tick, Color(ink, 0.65), 1.0, true)
	if _contact_visible:
		draw_arc(_contact_point, 4.0, 0.0, TAU, 16, Color(0.02, 0.03, 0.04, 0.4), 2.5, true)
		draw_arc(_contact_point, 4.0, 0.0, TAU, 16, Color(ink, 0.8), 1.0, true)
	# O cursor fica sob o mouse mesmo quando o alvo está fora de alcance.
	for sign_side in [-1.0, 1.0]:
		var corner := Vector2(sign_side * 4.0, 0)
		draw_line(corner, Vector2(0, -4), Color(0.02, 0.03, 0.04, 0.5), 2.5, true)
		draw_line(corner, Vector2(0, 4), Color(0.02, 0.03, 0.04, 0.5), 2.5, true)
		draw_line(corner, Vector2(0, -4), Color(ink, 0.85), 1.0, true)
		draw_line(corner, Vector2(0, 4), Color(ink, 0.85), 1.0, true)
	if blocked:
		draw_line(Vector2(-2.5, -2.5), Vector2(2.5, 2.5), ink, 1.5, true)
		draw_line(Vector2(-2.5, 2.5), Vector2(2.5, -2.5), ink, 1.5, true)
	elif in_range:
		draw_circle(Vector2.ZERO, 1.7, ink, true, -1.0, true)

func _draw() -> void:
	var ink := Color("ffb568") if blocked else Color("f7fbef")
	if confirmed:
		for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:
			draw_line(corner * 12.0, corner * 18.0, Color.BLACK, 5.0, true)
			draw_line(corner * 12.0, corner * 18.0, Color("fff1b2"), 2.5, true)
	if melee:
		_draw_melee()
		return
	for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(direction * 5.0, direction * 10.0, Color(0.03, 0.04, 0.06, 0.95), 4.0, true)
		draw_line(direction * 5.0, direction * 10.0, ink, 2.0, true)
	if blocked:
		for slope in [-1.0, 1.0]:
			draw_line(Vector2(-3, -3 * slope), Vector2(3, 3 * slope), Color.BLACK, 4.0, true)
			draw_line(Vector2(-3, -3 * slope), Vector2(3, 3 * slope), ink, 2.0, true)
	else:
		draw_circle(Vector2.ZERO, 2.5, Color.BLACK, true, -1.0, true)
		draw_circle(Vector2.ZERO, 1.3, ink, true, -1.0, true)
