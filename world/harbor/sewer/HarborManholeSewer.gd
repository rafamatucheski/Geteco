class_name HarborManholeSewer
extends Node2D

## Manhole transition into a separately instanced World2D. The street stays
## resident for the return; room physics, combat and audio are isolated and
## unloaded after Dante climbs out and replaces the cover.

enum State { SURFACE, OPENING, INSIDE, EXITING }

const INTERACTION_RADIUS := 27.0
const EXIT_RADIUS := 54.0
const SEWER_COLLISION_LAYER := 1
const INTERIOR_BOUNDS := Rect2(-130.0, -118.0, 460.0, 270.0)
const CANAL_BOUNDS := Rect2(112.0, -100.0, 54.0, 234.0)
const BRIDGE_HALF_HEIGHT := 23.0
const SECRET_POSITION := Vector2(265.0, 61.0)
const SECRET_PICKUP_ID := "harbor_police_sewer_sawed_off"
const STREET_POSITION := Vector2(1182.0, 2114.0)
const COVER_SLIDE := Vector2(-28.0, 0.0)
const COVER_GRIP := Vector2(-12.0, 6.0)

var state := State.SURFACE
var _inside := false
var _nearby_player: CharacterBody2D
var _player: CharacterBody2D
var _actor_state: Dictionary = {}
var _rig_transforms: Dictionary = {}
var _interior_overlay: Node2D
var _water_art: Node2D
var _secret_art: Node2D
var _exit_prompt: Label
var _secret_prompt: Label
var _ambient_water: AudioStreamPlayer
var _surface_sensor: Area2D
var _surface_art: ManholeSurfaceArt
var _lid_audio: AudioStreamPlayer2D
var _reward_collected := false
var _shaft_material: ShaderMaterial
var _arm_solver := preload("res://characters/PlayerCombatPose.gd").new()
var _isolation: RefCounted
var _transition_step := "surface":
	set(value):
		_transition_step = value
		if OS.get_cmdline_user_args().has("--diagnose-return"):
			print("SEWER_PHASE ", value, " t=", Time.get_ticks_msec())

func _exit_tree() -> void:
	if _isolation != null:
		_isolation.dispose()

class ManholeSurfaceArt:
	extends Node2D
	var lid: Node2D

	func _ready() -> void:
		lid = preload("res://world/harbor/sewer/ManholeCover3D.gd").new()
		lid.name = "SlidingCover3D"
		add_child(lid)

	var open_amount := 0.0:
		set(value):
			open_amount = clampf(value, 0.0, 1.0)
			if is_instance_valid(lid):
				lid.position = COVER_SLIDE * 2.0 * open_amount
			queue_redraw()

	func _draw() -> void:
		# Contact shadow and cast-iron collar keep the prop seated in the paving.
		draw_set_transform(Vector2(3.0, 5.0), 0.0, Vector2(1.0, 0.58))
		draw_circle(Vector2.ZERO, 26.0, Color(0.025, 0.03, 0.032, 0.42))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.58))
		draw_circle(Vector2.ZERO, 25.0, Color("#20282b"))
		draw_circle(Vector2.ZERO, 21.5, Color("#071014"))
		if open_amount > 0.08:
			var reveal := clampf((open_amount - 0.08) / 0.92, 0.0, 1.0)
			for rung in 4:
				var y := -10.0 + rung * 6.0
				draw_line(Vector2(-10.0, y), Vector2(10.0, y), Color(0.56, 0.62, 0.60, reveal), 1.6)
			draw_line(Vector2(-12.0, -13.0), Vector2(-12.0, 15.0), Color(0.42, 0.48, 0.47, reveal), 2.0)
			draw_line(Vector2(12.0, -13.0), Vector2(12.0, 15.0), Color(0.42, 0.48, 0.47, reveal), 2.0)
		# Contact shadow follows the loose cover across the pavement.
		draw_set_transform(COVER_SLIDE * 2.0 * open_amount + Vector2(1, 2), 0.0, Vector2(1, 0.58))
		draw_circle(Vector2.ZERO, 21.0, Color(0.02, 0.025, 0.03, 0.35))

class SewerWaterArt:
	extends Node2D
	var phase := 0.0
	var elapsed := 0.0
	func _process(delta: float) -> void:
		elapsed += delta
		if elapsed < 0.08: return
		phase = fposmod(phase + elapsed * 9.0, 18.0)
		elapsed = 0.0
		queue_redraw()
	func _draw() -> void:
		for y in range(-96, 126, 18):
			var level := float(y) + phase
			if absf(level) < BRIDGE_HALF_HEIGHT + 7.0: continue
			draw_line(Vector2(118, level), Vector2(160, level + 3), Color(0.37, 0.62, 0.56, 0.24), 1.0)
			draw_line(Vector2(126, level + 5), Vector2(152, level + 7), Color(0.56, 0.74, 0.61, 0.12), 1.0)

class SecretStashArt:
	extends Node2D

	var nearby := false
	var collected := false
	var clock := 0.0

	func _process(delta: float) -> void:
		if collected:
			return
		clock += delta
		queue_redraw()

	func _draw() -> void:
		if collected:
			return
		var lift := sin(clock * 2.2) * 1.5
		draw_circle(Vector2(0.0, 10.0), 24.0, Color(0.85, 0.49, 0.16, 0.10 if not nearby else 0.18))
		draw_rect(Rect2(-31.0, -10.0, 62.0, 36.0), Color("#1c2427"))
		draw_rect(Rect2(-28.0, -8.0, 56.0, 31.0), Color("#4c5557"))
		draw_rect(Rect2(-28.0, -8.0, 56.0, 31.0), Color("#88908c"), false, 2.0)
		draw_line(Vector2(-22.0, 4.0), Vector2(22.0, 4.0), Color("#20282b"), 3.0)
		# Compact double-barrel silhouette; the prompt is the only text.
		var p := Vector2(0.0, -14.0 + lift)
		draw_line(p + Vector2(-19.0, -2.0), p + Vector2(13.0, -2.0), Color("#aeb7b6"), 4.0)
		draw_line(p + Vector2(-19.0, 2.0), p + Vector2(13.0, 2.0), Color("#737f82"), 4.0)
		draw_line(p + Vector2(-18.0, 3.0), p + Vector2(-25.0, 13.0), Color("#8b5c36"), 6.0)

func _ready() -> void:
	z_as_relative = false
	_build_surface()
	set_process(false)

func _build_surface() -> void:
	_surface_art = ManholeSurfaceArt.new()
	_surface_art.name = "SurfaceCover"
	_surface_art.z_as_relative = false
	_surface_art.z_index = 4
	_surface_art.scale = Vector2.ONE * 0.50
	add_child(_surface_art)

	_surface_sensor = Area2D.new()
	_surface_sensor.name = "InteractionArea"
	_surface_sensor.collision_layer = 0
	_surface_sensor.collision_mask = 4
	var sensor_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = INTERACTION_RADIUS
	sensor_shape.shape = circle
	_surface_sensor.add_child(sensor_shape)
	add_child(_surface_sensor)
	_surface_sensor.body_entered.connect(_on_surface_body_entered)
	_surface_sensor.body_exited.connect(_on_surface_body_exited)

	var prompt := _make_prompt(_surface_art, Vector2(-28.0, -50.0))
	prompt.name = "Prompt"
	prompt.hide()

	_lid_audio = AudioStreamPlayer2D.new()
	_lid_audio.name = "LidAudio"
	_lid_audio.bus = &"SFX"
	_lid_audio.stream = preload("res://world/harbor/HarborAudioBank.gd").sound("metal")
	_lid_audio.volume_db = -7.0
	_lid_audio.max_distance = 480.0
	add_child(_lid_audio)

func _make_prompt(parent: Node, at: Vector2) -> Label:
	var prompt := Label.new()
	prompt.text = "E"
	prompt.position = at
	prompt.size = Vector2(56.0, 24.0)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 13)
	prompt.add_theme_color_override("font_color", Color("#f4dfad"))
	prompt.add_theme_color_override("font_outline_color", Color("#11191c"))
	prompt.add_theme_constant_override("outline_size", 4)
	prompt.z_as_relative = false
	prompt.z_index = 250
	parent.add_child(prompt)
	return prompt

func _on_surface_body_entered(body: Node2D) -> void:
	if state != State.SURFACE or not body.is_in_group("player") or not body is CharacterBody2D:
		return
	_nearby_player = body as CharacterBody2D
	_refresh_surface_prompt()

func _on_surface_body_exited(body: Node2D) -> void:
	if body != _nearby_player:
		return
	_nearby_player = null
	_refresh_surface_prompt()

func _refresh_surface_prompt() -> void:
	var prompt := _surface_art.get_node_or_null("Prompt") as Label
	if prompt != null:
		prompt.visible = state == State.SURFACE and _can_use_surface(_nearby_player)

func _can_use_surface(actor: CharacterBody2D) -> bool:
	if not is_instance_valid(actor) or not actor.visible:
		return false
	if bool(actor.get("is_dead")) or bool(actor.get("is_arrested")):
		return false
	if bool(actor.get("is_in_dialogue")) or bool(actor.get("is_control_disabled")):
		return false
	return actor.global_position.distance_to(global_position) <= INTERACTION_RADIUS + 3.0

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or event.is_echo():
		return
	if state == State.SURFACE and request_interaction(_nearby_player):
		get_viewport().set_input_as_handled()
		return
	if state != State.INSIDE or not is_instance_valid(_player):
		return
	if not _reward_collected and _player.global_position.distance_to(to_global(SECRET_POSITION)) <= 48.0:
		get_viewport().set_input_as_handled()
		_collect_secret()
	elif _player.global_position.distance_to(global_position) <= EXIT_RADIUS:
		get_viewport().set_input_as_handled()
		_begin_exit()

func request_interaction(actor: CharacterBody2D) -> bool:
	if state != State.SURFACE or not _can_use_surface(actor):
		return false
	_begin_entry(actor)
	return true

func _process(_delta: float) -> void:
	if state != State.INSIDE or not is_instance_valid(_player):
		return
	if bool(_player.get("is_dead")) or bool(_player.get("is_arrested")):
		_force_surface_restore()
		return
	var at_exit := _player.global_position.distance_to(global_position) <= EXIT_RADIUS
	var at_secret := not _reward_collected and _player.global_position.distance_to(to_global(SECRET_POSITION)) <= 48.0
	if is_instance_valid(_exit_prompt):
		_exit_prompt.visible = at_exit and not at_secret
	if is_instance_valid(_secret_prompt):
		_secret_prompt.visible = at_secret
	if is_instance_valid(_secret_art):
		_secret_art.set("nearby", at_secret)

func _begin_entry(actor: CharacterBody2D) -> void:
	state = State.OPENING
	_player = actor
	_capture_actor_state(actor)
	_refresh_surface_prompt()
	actor.velocity = Vector2.ZERO
	actor.set("is_control_disabled", true)
	actor.set_physics_process(false)
	_set_weapon_visible(false)
	_ensure_interior_loaded()

	var align := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	align.tween_property(actor, "global_position", global_position + COVER_GRIP, 0.26)
	await align.finished
	if not is_instance_valid(actor):
		return

	_lid_audio.pitch_scale = 0.88
	_lid_audio.play()
	var open := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	open.tween_method(_prepare_cover_drag, 0.0, 1.0, 0.42)
	open.tween_method(_apply_cover_drag, 0.0, 1.0, 1.15)
	open.tween_method(_release_cover_drag, 1.0, 0.0, 0.28)
	await open.finished
	var approach := create_tween().set_trans(Tween.TRANS_SINE)
	approach.tween_property(actor, "global_position", global_position, 0.32)
	await approach.finished
	await _face_ladder()
	await _animate_ladder(0.0, 18.0, 2.0, false)
	_activate_interior()
	await get_tree().process_frame
	await _animate_ladder(-38.0, 0.0, 0.85, true)
	_restore_actor_visuals()
	_finish_transition_to_inside()

func _activate_interior() -> void:
	if not is_instance_valid(_player) or not is_instance_valid(_interior_overlay):
		return
	_inside = true
	_isolation.enter(_player, _interior_overlay)
	_interior_overlay.show()
	_interior_overlay.process_mode = Node.PROCESS_MODE_INHERIT
	_player.collision_layer = 4
	_player.collision_mask = SEWER_COLLISION_LAYER
	_player.z_as_relative = false
	_player.z_index = 10
	_player.set_meta("harbor_interior", true)
	_player.set_meta("harbor_sewer_inside", true)
	if is_instance_valid(_ambient_water):
		_ambient_water.stream_paused = false
		_ambient_water.play()
	if is_instance_valid(_water_art):
		_water_art.set_process(true)

func _finish_transition_to_inside() -> void:
	if not is_instance_valid(_player):
		return
	_restore_rig()
	_set_weapon_visible(true)
	_player.set_physics_process(bool(_actor_state.get("physics_processing", true)))
	_player.set("is_control_disabled", false)
	state = State.INSIDE
	set_process(true)
	_refresh_inside_prompts()

func _begin_exit() -> void:
	if state != State.INSIDE or not is_instance_valid(_player):
		return
	state = State.EXITING
	_transition_step = "exit_align"
	set_process(false)
	_hide_inside_prompts()
	_player.velocity = Vector2.ZERO
	_player.set("is_control_disabled", true)
	_player.set_physics_process(false)
	_set_weapon_visible(false)
	var align := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	align.tween_property(_player, "global_position", global_position, 0.24)
	await align.finished
	await _face_ladder()
	await _animate_ladder(0.0, -38.0, 0.85, true)
	_transition_step = "restore_surface"
	_deactivate_interior()
	# Reparenting, camera/listener restoration and visibility are synchronous.
	# Start the emergence in the same transition; do not leave a hidden actor
	# waiting across the viewport teardown's frame signal.
	_transition_step = "emerge"
	await _animate_ladder(18.0, 0.0, 2.0, false)
	_transition_step = "clear_shaft"
	_restore_actor_visuals()
	_set_weapon_visible(false)
	# Dante clears the shaft before pulling the heavy cover back into place.
	# Physics stays paused during the authored step so street solids cannot
	# interrupt the hand/cover synchronization.
	var clear_shaft := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	clear_shaft.tween_property(_player, "global_position", global_position + COVER_SLIDE + COVER_GRIP, 0.26)
	await clear_shaft.finished
	_transition_step = "close_cover"
	_lid_audio.pitch_scale = 0.72
	_lid_audio.play()
	var close := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	close.tween_method(_prepare_cover_drag, 0.0, 1.0, 0.42)
	close.tween_method(_apply_cover_drag, 1.0, 0.0, 1.15)
	close.tween_method(_release_cover_drag, 1.0, 0.0, 0.28)
	await close.finished
	_transition_step = "surface"
	_finish_transition_to_surface()

func _deactivate_interior() -> void:
	_inside = false
	if _isolation != null:
		_isolation.leave()
	if is_instance_valid(_interior_overlay):
		_interior_overlay.hide()
		_interior_overlay.process_mode = Node.PROCESS_MODE_DISABLED
	if is_instance_valid(_ambient_water):
		_ambient_water.stop()
	if is_instance_valid(_player):
		_player.collision_layer = int(_actor_state.get("collision_layer", 4))
		_player.collision_mask = int(_actor_state.get("collision_mask", 7))
		_player.z_as_relative = bool(_actor_state.get("z_as_relative", true))
		_player.z_index = int(_actor_state.get("z_index", 10))
		_player.remove_meta("harbor_sewer_inside")
		_player.set_meta("harbor_interior", _actor_state.get("harbor_interior", false))

func _finish_transition_to_surface() -> void:
	if not is_instance_valid(_player):
		return
	_restore_rig()
	_set_weapon_visible(true)
	_player.set_physics_process(bool(_actor_state.get("physics_processing", true)))
	_player.set("is_control_disabled", bool(_actor_state.get("control_disabled", false)))
	state = State.SURFACE
	_teardown_interior()
	_nearby_player = _player
	_refresh_surface_prompt()

func _force_surface_restore() -> void:
	if is_instance_valid(_player):
		_deactivate_interior()
		_player.global_position = global_position + COVER_GRIP
		_restore_actor_visuals()
		_player.set_physics_process(bool(_actor_state.get("physics_processing", true)))
		_player.set("is_control_disabled", bool(_actor_state.get("control_disabled", false)))
	state = State.SURFACE
	_surface_art.open_amount = 0.0
	set_process(false)
	_teardown_interior()
	if is_instance_valid(_player) and _player.global_position.distance_to(global_position) <= INTERACTION_RADIUS:
		_nearby_player = _player
	_refresh_surface_prompt()

func _capture_actor_state(actor: CharacterBody2D) -> void:
	var sprite := actor.get("sprite_3d_display") as Sprite2D
	_actor_state = {
		"collision_layer": actor.collision_layer,
		"collision_mask": actor.collision_mask,
		"z_as_relative": actor.z_as_relative,
		"z_index": actor.z_index,
		"physics_processing": actor.is_physics_processing(),
		"control_disabled": bool(actor.get("is_control_disabled")),
		"sprite_scale": sprite.scale if is_instance_valid(sprite) else Vector2.ONE,
		"sprite_position": sprite.position if is_instance_valid(sprite) else Vector2.ZERO,
		"sprite_alpha": sprite.modulate.a if is_instance_valid(sprite) else 1.0,
		"sprite_material": sprite.material if is_instance_valid(sprite) else null,
		"harbor_interior": actor.get_meta("harbor_interior", false),
	}
	_rig_transforms.clear()
	for property in ["model_root", "torso_node", "head_node", "left_upper_arm", "left_lower_arm", "right_upper_arm", "right_lower_arm", "left_upper_leg", "left_lower_leg", "right_upper_leg", "right_lower_leg"]:
		var part := actor.get(property) as Node3D
		if is_instance_valid(part):
			_rig_transforms[part] = part.transform
	for property in ["left_lower_leg", "right_lower_leg"]:
		var leg := actor.get(property) as Node3D
		if leg and leg.has_node("Foot"):
			var foot := leg.get_node("Foot") as Node3D
			_rig_transforms[foot] = foot.transform

func _apply_reach_pose(amount: float) -> void:
	if not is_instance_valid(_player):
		return
	_apply_part_rotation("torso_node", Vector3(0.38, 0.0, 0.0), amount, Vector3(0.0, -0.08, 0.0))
	_apply_part_rotation("left_upper_arm", Vector3(-1.05, 0.0, -0.20), amount)
	_apply_part_rotation("right_upper_arm", Vector3(-1.05, 0.0, 0.20), amount)
	_apply_part_rotation("left_lower_arm", Vector3(0.68, 0.0, 0.0), amount)
	_apply_part_rotation("right_lower_arm", Vector3(0.68, 0.0, 0.0), amount)
	_apply_part_rotation("left_upper_leg", Vector3(0.34, 0.0, 0.0), amount)
	_apply_part_rotation("right_upper_leg", Vector3(0.34, 0.0, 0.0), amount)
	_apply_part_rotation("left_lower_leg", Vector3(0.62, 0.0, 0.0), amount)
	_apply_part_rotation("right_lower_leg", Vector3(0.62, 0.0, 0.0), amount)
	_player.call("_sync_upper_body_anchors", 0.38 * amount)

func _apply_cover_drag(amount: float) -> void:
	if not is_instance_valid(_player):
		return
	_surface_art.open_amount = amount
	_player.global_position = global_position + COVER_GRIP + COVER_SLIDE * amount
	_pose_cover_drag(amount, 1.0)

func _prepare_cover_drag(weight: float) -> void:
	_pose_cover_drag(_surface_art.open_amount, weight)

func _release_cover_drag(weight: float) -> void:
	_pose_cover_drag(_surface_art.open_amount, weight)
	_player.model_root.rotation.y = -PI / 2.0

func _pose_cover_drag(progress: float, weight: float) -> void:
	var original: Transform3D = _rig_transforms[_player.model_root]
	_player.model_root.rotation.y = lerp_angle(original.basis.get_euler().y, -PI / 2.0, weight)
	# Flex the hips as well as knees; lowering only the chest folded the old
	# animation in half while its feet skated. Two short alternating backsteps.
	_apply_part_rotation("torso_node", Vector3(0.30, 0, 0), weight, Vector3(0, -0.15, -0.045))
	_player.call("_sync_upper_body_anchors", 0.30 * weight)
	for side in [-1.0, 1.0]:
		var phase := fposmod(progress * 2.0 + (0.5 if side > 0 else 0.0), 1.0)
		var planted := phase < 0.65
		var z := lerpf(0.16, -0.16, phase / 0.65) if planted else lerpf(-0.16, 0.16, smoothstep(0, 1, (phase - 0.65) / 0.35))
		var lift := 0.0 if planted else sin((phase - 0.65) / 0.35 * PI) * 0.045
		_pose_drag_leg("left" if side < 0 else "right", z, lift, weight)
		var upper := _player.get("left_upper_arm" if side < 0 else "right_upper_arm") as Node3D
		var lower := _player.get("left_lower_arm" if side < 0 else "right_lower_arm") as Node3D
		_arm_solver._solve_arm(upper, lower, Vector3(side * 0.12, 0.75, -0.29), side)
		var base_upper: Transform3D = _rig_transforms[upper]
		var base_lower: Transform3D = _rig_transforms[lower]
		upper.quaternion = base_upper.basis.get_rotation_quaternion().slerp(upper.quaternion, weight)
		lower.quaternion = base_lower.basis.get_rotation_quaternion().slerp(lower.quaternion, weight)

func _pose_drag_leg(side: String, z: float, lift: float, weight: float) -> void:
	var upper := _player.get(side + "_upper_leg") as Node3D
	var lower := _player.get(side + "_lower_leg") as Node3D
	var base: Transform3D = _rig_transforms[upper]
	upper.position = base.origin + Vector3(0, -0.15, 0) * weight
	# Planar two-bone IK using Dante's actual 0.34/0.30 rig segments.
	var target := Vector2(z * weight, upper.position.y - (0.045 + lift * weight))
	var distance := clampf(target.length(), 0.08, 0.639)
	var knee := -acos(clampf((distance * distance - 0.34 * 0.34 - 0.30 * 0.30) / (2 * 0.34 * 0.30), -1, 1))
	var hip := atan2(-target.x, target.y) - atan2(0.30 * sin(knee), 0.34 + 0.30 * cos(knee))
	upper.rotation = Vector3(hip, 0, 0)
	lower.rotation = Vector3(knee, 0, 0)
	var foot := lower.get_node_or_null("Foot") as Node3D
	if foot: foot.rotation.x = -hip - knee

func _face_ladder() -> void:
	var model := _player.get("model_root") as Node3D
	var facing := model.rotation.y if model else 0.0
	_restore_rig()
	if model: model.rotation.y = facing
	var turn := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	if is_instance_valid(model):
		turn.tween_property(model, "rotation:y", lerp_angle(model.rotation.y, 0.0, 1.0), 0.32)
	turn.tween_method(_apply_reach_pose, 0.0, 0.0, 0.32)
	await turn.finished

func _animate_ladder(start: float, finish: float, seconds: float, ceiling: bool) -> void:
	var sprite := _player.get("sprite_3d_display") as Sprite2D
	if not is_instance_valid(sprite):
		return
	if _shaft_material == null:
		_shaft_material = ShaderMaterial.new()
		_shaft_material.shader = preload("res://world/harbor/sewer/ShaftClip.gdshader")
	sprite.material = _shaft_material
	_apply_ladder_frame(0.0, start, finish, ceiling)
	var motion := create_tween()
	motion.tween_method(_apply_ladder_frame.bind(start, finish, ceiling), 0.0, 1.0, seconds)
	await motion.finished

func _apply_ladder_frame(progress: float, start: float, finish: float, ceiling: bool) -> void:
	if not is_instance_valid(_player):
		return
	var sprite := _player.get("sprite_3d_display") as Sprite2D
	# Ease each rung transfer, not the whole descent: deliberate hand-over-hand
	# steps at constant body size. Clip against a stationary shaft lip.
	var step_progress := progress * 3.0
	var stepped := (floorf(step_progress) + smoothstep(0.0, 1.0, fposmod(step_progress, 1.0))) / 3.0
	var offset := lerpf(start, finish, stepped)
	sprite.position = _actor_state.sprite_position + Vector2(0.0, offset)
	_shaft_material.set_shader_parameter("lip_y", ((-20.0 if ceiling else 6.0) - offset) / sprite.scale.y)
	_shaft_material.set_shader_parameter("ceiling", ceiling)
	_apply_climb_pose(progress if finish > start else 1.0 - progress)

func _apply_climb_pose(progress: float) -> void:
	if not is_instance_valid(_player):
		return
	var alternating := sin(progress * TAU * 1.5)
	_apply_part_rotation("torso_node", Vector3(0.12, 0.0, alternating * 0.035), 1.0, Vector3(0.0, -0.04, 0.0))
	_player.call("_sync_upper_body_anchors", 0.12)
	# Reuse Dante's anatomical arm solver; shoulders stay attached to his shirt.
	_arm_solver._solve_arm(_player.left_upper_arm, _player.left_lower_arm, Vector3(-0.185, 1.16 + alternating * 0.13, -0.22), -1.0)
	_arm_solver._solve_arm(_player.right_upper_arm, _player.right_lower_arm, Vector3(0.185, 1.16 - alternating * 0.13, -0.22), 1.0)
	_apply_part_rotation("left_upper_leg", Vector3(-0.48 - alternating * 0.30, 0.0, 0.0), 1.0)
	_apply_part_rotation("right_upper_leg", Vector3(-0.48 + alternating * 0.30, 0.0, 0.0), 1.0)
	_apply_part_rotation("left_lower_leg", Vector3(0.85 + alternating * 0.35, 0.0, 0.0), 1.0)
	_apply_part_rotation("right_lower_leg", Vector3(0.85 - alternating * 0.35, 0.0, 0.0), 1.0)

func _apply_part_rotation(property: String, offset: Vector3, amount: float, position_offset: Vector3 = Vector3.ZERO) -> void:
	var part := _player.get(property) as Node3D
	if not is_instance_valid(part) or not _rig_transforms.has(part):
		return
	var base: Transform3D = _rig_transforms[part]
	part.transform = base
	part.rotation = base.basis.get_euler() + offset * amount
	part.position = base.origin + position_offset * amount

func _restore_rig() -> void:
	for part in _rig_transforms:
		if is_instance_valid(part):
			part.transform = _rig_transforms[part]

func _restore_actor_visuals() -> void:
	if not is_instance_valid(_player):
		return
	var sprite := _player.get("sprite_3d_display") as Sprite2D
	if is_instance_valid(sprite):
		sprite.scale = _actor_state.get("sprite_scale", sprite.scale)
		sprite.position = _actor_state.get("sprite_position", sprite.position)
		sprite.modulate.a = float(_actor_state.get("sprite_alpha", 1.0))
		sprite.material = _actor_state.get("sprite_material")
	_restore_rig()
	_set_weapon_visible(true)

func _set_weapon_visible(value: bool) -> void:
	if not is_instance_valid(_player):
		return
	var weapon := _player.get("current_gun_mesh") as Node3D
	if is_instance_valid(weapon):
		weapon.visible = value

func _ensure_interior_loaded() -> void:
	if is_instance_valid(_interior_overlay):
		return
	_reward_collected = _player.get("world_pickups_collected") is Array and _player.world_pickups_collected.has(SECRET_PICKUP_ID)
	_interior_overlay = preload("res://world/harbor/sewer/SewerInterior.tscn").instantiate()
	_interior_overlay.name = "RuntimeSewer"
	_interior_overlay.set_meta("sewer_controller", self)
	_interior_overlay.set_meta("combat_scene_root", _interior_overlay)
	_interior_overlay.z_as_relative = false
	_interior_overlay.z_index = 0
	_interior_overlay.visible = false
	_interior_overlay.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(_interior_overlay)

	_isolation = preload("res://world/harbor/sewer/SewerIsolation.gd").new()
	_isolation.build(self, _interior_overlay)
	var effects := preload("res://guns/combat/WeaponEffects.gd").new()
	_interior_overlay.add_child(effects)
	_water_art = SewerWaterArt.new()
	_water_art.name = "AnimatedWater"
	_water_art.set_process(false)
	_interior_overlay.add_child(_water_art)
	_build_interior_collisions()

	_secret_art = SecretStashArt.new()
	_secret_art.name = "SecretStash"
	_secret_art.position = SECRET_POSITION
	_secret_art.scale = Vector2.ONE * 0.42
	_secret_art.set("collected", _reward_collected)
	_secret_art.visible = not _reward_collected
	_secret_art.set_process(not _reward_collected)
	_interior_overlay.add_child(_secret_art)

	_exit_prompt = _make_prompt(_interior_overlay, Vector2(-28.0, -55.0))
	_exit_prompt.name = "ExitPrompt"
	_exit_prompt.hide()
	_secret_prompt = _make_prompt(_interior_overlay, SECRET_POSITION + Vector2(-28.0, -58.0))
	_secret_prompt.name = "SecretPrompt"
	_secret_prompt.hide()

	_ambient_water = AudioStreamPlayer.new()
	_ambient_water.name = "SewerWater"
	_ambient_water.bus = &"SFX"
	_ambient_water.stream = preload("res://world/harbor/HarborAudioBank.gd").sound("water")
	_ambient_water.volume_db = -22.0
	_interior_overlay.add_child(_ambient_water)

func _build_interior_collisions() -> void:
	var collision_root := Node2D.new()
	collision_root.name = "SewerCollisions"
	_interior_overlay.add_child(collision_root)
	var thickness := 18.0
	_add_wall(collision_root, Rect2(INTERIOR_BOUNDS.position, Vector2(INTERIOR_BOUNDS.size.x, thickness)))
	_add_wall(collision_root, Rect2(Vector2(INTERIOR_BOUNDS.position.x, INTERIOR_BOUNDS.end.y - thickness), Vector2(INTERIOR_BOUNDS.size.x, thickness)))
	_add_wall(collision_root, Rect2(INTERIOR_BOUNDS.position, Vector2(thickness, INTERIOR_BOUNDS.size.y)))
	_add_wall(collision_root, Rect2(Vector2(INTERIOR_BOUNDS.end.x - thickness, INTERIOR_BOUNDS.position.y), Vector2(thickness, INTERIOR_BOUNDS.size.y)))
	var top_water_height := -BRIDGE_HALF_HEIGHT - CANAL_BOUNDS.position.y
	_add_wall(collision_root, Rect2(CANAL_BOUNDS.position, Vector2(CANAL_BOUNDS.size.x, top_water_height)))
	_add_wall(collision_root, Rect2(Vector2(CANAL_BOUNDS.position.x, BRIDGE_HALF_HEIGHT), Vector2(CANAL_BOUNDS.size.x, CANAL_BOUNDS.end.y - BRIDGE_HALF_HEIGHT)))
	# Utility cabinet and stacked crates also have honest physical footprints.
	_add_wall(collision_root, Rect2(212.0, -56.0, 72.0, 45.0))
	_add_wall(collision_root, Rect2(208.0, 100.0, 65.0, 24.0))
	_add_wall(collision_root, Rect2(-98.0, 32.0, 33.0, 46.0))

func _add_wall(parent: Node2D, rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.position = rect.get_center()
	body.collision_layer = SEWER_COLLISION_LAYER
	body.collision_mask = 0
	var shape_node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	shape_node.shape = shape
	body.add_child(shape_node)
	parent.add_child(body)

func _refresh_inside_prompts() -> void:
	if not is_instance_valid(_player):
		return
	if is_instance_valid(_exit_prompt):
		_exit_prompt.visible = _player.global_position.distance_to(global_position) <= EXIT_RADIUS
	if is_instance_valid(_secret_prompt):
		_secret_prompt.visible = not _reward_collected and _player.global_position.distance_to(to_global(SECRET_POSITION)) <= 48.0

func _hide_inside_prompts() -> void:
	if is_instance_valid(_exit_prompt):
		_exit_prompt.hide()
	if is_instance_valid(_secret_prompt):
		_secret_prompt.hide()

func _collect_secret() -> void:
	if _reward_collected or not is_instance_valid(_player):
		return
	_reward_collected = true
	if _player.get("world_pickups_collected") is Array and not _player.world_pickups_collected.has(SECRET_PICKUP_ID):
		_player.world_pickups_collected.append(SECRET_PICKUP_ID)
	if _player.has_method("add_weapon_loot"):
		_player.add_weapon_loot(&"sawed_off", 24)
	preload("res://audio/rewards/RewardAudioBank.gd").play(self, "weapon", -2.0)
	if is_instance_valid(_secret_art):
		_secret_art.set("collected", true)
		_secret_art.set_process(false)
		_secret_art.hide()
	if is_instance_valid(_secret_prompt):
		_secret_prompt.hide()

func _teardown_interior() -> void:
	if is_instance_valid(_interior_overlay):
		for voice in _interior_overlay.find_children("*", "AudioStreamPlayer", true, false): voice.stop()
		for voice in _interior_overlay.find_children("*", "AudioStreamPlayer2D", true, false): voice.stop()
	if _isolation != null:
		_isolation.dispose()
		_isolation = null
	if is_instance_valid(_interior_overlay):
		_interior_overlay.queue_free()
	_interior_overlay = null
	_water_art = null
	_secret_art = null
	_exit_prompt = null
	_secret_prompt = null
	_ambient_water = null

func contains_point(world_point: Vector2) -> bool:
	return _inside and INTERIOR_BOUNDS.has_point(to_local(world_point))

func get_camera_rect() -> Rect2:
	return Rect2(to_global(INTERIOR_BOUNDS.position), INTERIOR_BOUNDS.size)

func set_npc_rendering_active(active: bool) -> void:
	if is_instance_valid(_water_art):
		_water_art.set_process(active and _inside)

func get_runtime_stats() -> Dictionary:
	var body_count := 0
	if is_instance_valid(_interior_overlay):
		body_count = _interior_overlay.find_children("*", "StaticBody2D", true, false).size()
	return {
		"state": state,
		"transition_step": _transition_step,
		"inside": _inside,
		"interior_loaded": is_instance_valid(_interior_overlay),
		"interior_visible": is_instance_valid(_interior_overlay) and _interior_overlay.visible,
		"collision_bodies": body_count,
		"reward_collected": _reward_collected,
		"isolated_world": is_instance_valid(_interior_overlay) and _interior_overlay.get_world_2d() != get_world_2d(),
	}

## Test/benchmark seam: exercises the exact runtime layer without waiting for
## presentation tweens. Gameplay never calls this method.
func debug_enter_immediately(actor: CharacterBody2D) -> void:
	if state != State.SURFACE or not is_instance_valid(actor):
		return
	_player = actor
	_capture_actor_state(actor)
	_ensure_interior_loaded()
	_surface_art.open_amount = 1.0
	_activate_interior()
	_restore_actor_visuals()
	_player.set("is_control_disabled", false)
	_player.set_physics_process(bool(_actor_state.get("physics_processing", true)))
	state = State.INSIDE
	set_process(true)
	_refresh_inside_prompts()

func debug_exit_immediately() -> void:
	if not is_instance_valid(_player):
		return
	_deactivate_interior()
	_restore_actor_visuals()
	_player.set("is_control_disabled", bool(_actor_state.get("control_disabled", false)))
	_player.set_physics_process(bool(_actor_state.get("physics_processing", true)))
	_surface_art.open_amount = 0.0
	state = State.SURFACE
	set_process(false)
	_teardown_interior()
