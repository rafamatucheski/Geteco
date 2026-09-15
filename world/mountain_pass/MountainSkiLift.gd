extends "res://world/mountain_pass/MountainProjectedExterior.gd"

var is_base_station := false
var prompt: Label
var _travelling := false
var _clock := 0.0
var _rider: Node2D
var _presentation := preload("res://world/mountain_pass/MountainLiftRiderPresentation.gd").new()
var _render_clock := 0.0

func _ready() -> void:
	z_as_relative = false
	z_index = 5
	build_view(preload("res://world/mountain_pass/MountainSkiLift3D.gd"), 10.0, 18.0, Vector3(0, 1.8, 0), Vector3(0, 13, 11), Vector2i(512, 448))
	depth_bounds = Rect2(-4.5,-3.8,9.0,8.0)
	install_projected_solids()
	if not is_base_station:
		set_process(true)
		return
	prompt = Label.new()
	prompt.position = Vector2(-140, -105)
	prompt.size = Vector2(280, 48)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.add_theme_font_size_override("font_size", 13)
	prompt.add_theme_color_override("font_color", Color("eef4f5"))
	prompt.add_theme_color_override("font_outline_color", Color("101820"))
	prompt.add_theme_constant_override("outline_size", 4)
	prompt.hide()
	add_child(prompt)
	set_process(true)

func _process(delta: float) -> void:
	super._process(delta)
	_clock += delta
	_render_clock += delta
	if _render_clock > 1.0/24.0:
		_render_clock = 0.0
		if int(viewport_3d.get_meta("interior_actor_count",0)) == 0 and get_viewport_rect().grow(180).has_point(get_viewport().get_canvas_transform()*global_position):
			viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	var schedule_script := preload("res://world/mountain_pass/MountainSkiSchedule.gd")
	var is_open := schedule_script.is_open(self)

	# Atualiza estado operacional do modelo 3D
	if is_instance_valid(model):
		model.set_operating(is_open)
		model.set_lit(not is_open)

	if not is_base_station or _travelling: return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var near := _can_board(player)
	prompt.visible = near
	if not near: return

	if not is_open:
		prompt.text = schedule_script.get_closed_notice(self, "TELEFÉRICO")
		return

	var key: String = get_node("/root/GameInput").hint("interact")
	prompt.text = "[%s] TELEFÉRICO PARA O CUME" % key
	if Input.is_action_just_pressed("interact"):
		_return_to_summit(player)

func _return_to_summit(player: Node2D, instant: bool = false) -> void:
	if not _can_board(player): return
	var schedule_script := preload("res://world/mountain_pass/MountainSkiSchedule.gd")
	if not schedule_script.is_open(self):
		if player.has_method("_show_weapon_notice"):
			player._show_weapon_notice("TELEFÉRICO ENCERRADO · HORÁRIO: 08:00 ÀS 18:00")
		return
	_travelling = true
	_rider = player
	prompt.hide()
	if player.get("is_skiing") == true: player.stop_skiing()
	player.is_control_disabled = true
	player.set_meta("mountain_lift_riding", true)
	player.velocity = Vector2.ZERO
	var area := get_parent() as Node2D
	var summit: Vector2 = area.to_global(preload("res://world/mountain_pass/MountainSkiLayout.gd").LIFT_SUMMIT)
	var path := Curve2D.new()
	path.bake_interval = 2.0
	var cable := area.get_node_or_null("ChairliftCable") as Line2D
	if cable:
		for i in range(cable.points.size() - 1, -1, -1):
			path.add_point(area.to_local(cable.to_global(cable.points[i])))
	else:
		path.add_point(area.to_local(global_position))
		path.add_point(area.to_local(summit))
	player._show_weapon_notice("SUBINDO PELO TELEFÉRICO · [%s] ADIANTAR VIAGEM" % get_node("/root/GameInput").hint("handbrake"))
	if not instant: _presentation.begin(player,area,cable.points if cable else PackedVector2Array([area.to_local(summit),position]))
	var expected := player.global_position
	var elapsed := 0.0
	var completed := instant
	var skip_armed := false
	while not instant and elapsed < 6.0:
		await get_tree().process_frame
		if get_tree().paused: continue
		if not is_instance_valid(player): break
		if player.get("is_dead") == true or player.get("is_recovering") == true or player.global_position.distance_to(expected) > 2.0:
			break
		if not Input.is_action_pressed("interact") and not Input.is_action_pressed("handbrake"):
			skip_armed = true
		elif skip_armed and (Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("handbrake")):
			completed = true
			break
		elapsed += get_process_delta_time()
		var progress := clampf(elapsed / 6.0, 0.0, 1.0)
		expected = area.to_global(path.sample_baked(path.get_baked_length() * progress))
		if cable: expected += cable.points[-1].direction_to(cable.points[0]).orthogonal()*14.0
		player.global_position = expected
		_presentation.update()
		completed = progress >= 1.0
	_presentation.restore()
	if is_instance_valid(player):
		player.remove_meta("mountain_lift_riding")
		# Release our input lock; death owns its separate physics/recovery state.
		player.is_control_disabled = false
		# Never overwrite a hospital or mission teleport.
		if player.get("is_dead") != true and player.get("is_recovering") != true:
			if completed:
				player.global_position = summit
				player.velocity = Vector2.ZERO
				player.reset_physics_interpolation()
				if player.get("ski_equipment_ready") == true: player.start_skiing(Vector2.UP)
				player._show_weapon_notice("CHEGADA AO CUME BRANCO")
	_travelling = false
	_rider = null

func _exit_tree() -> void:
	super._exit_tree()
	_presentation.restore()
	if is_instance_valid(_rider):
		_rider.remove_meta("mountain_lift_riding")
		_rider.is_control_disabled = false

func _can_board(player: Node2D) -> bool:
	if not is_instance_valid(player) or not player.visible: return false
	return not _travelling and is_instance_valid(player) and player.get("is_dead") != true and player.get("is_control_disabled") != true and player.get("is_in_dialogue") != true and player.get("is_recovering") != true and player.get("current_vehicle") == null and not player.has_meta("mountain_interior") and global_position.distance_to(player.global_position) < 115.0

