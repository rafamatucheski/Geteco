extends Camera2D

## Câmera Dinâmica de Alta Velocidade com Efeitos de Neon e Nitro (Velozes e Furiosos Style)
## Expansão de FOV durante Boost de Nitro, Lead de Direção e Vinheta de Neon vibrante.

@export var zoom_close: float = 1.8   # Câmera próxima (Parado / baixa velocidade)
@export var zoom_far: float = 1.22    # Câmera distante (Velocidade de cruzeiro)
@export var zoom_nitro: float = 1.02  # Câmera hiper-afastada durante Nitro NOS
@export var max_speed: float = 600.0
@export var transition_speed: float = 4.2
@export var lead_distance: float = 52.0
@export var overview_zoom: float = 0.35 # Zoom para ver a cidade inteira em modo de edição
@export var overview_pan_sensitivity: float = 1.0
@export var overview_toggle_key: int = KEY_F9

var _shake_amount: float = 0.0
var _neon_overlay: CanvasLayer
var _neon_vignette: ColorRect
var _is_overview_mode: bool = false
var _is_dragging_overview: bool = false
var _drag_last_pos: Vector2 = Vector2.ZERO
var _overview_parent_position: Vector2 = Vector2.ZERO
var _has_overview_parent_position: bool = false


## Capture BEFORE moving/hiding the outgoing actor. Inactive player cameras can
## retain a smoothing position thousands of metres behind a driven vehicle.
static func capture_view(viewport: Viewport) -> Dictionary:
	var current := viewport.get_camera_2d()
	if current == null: return {}
	return {"center": current.get_screen_center_position(), "zoom": current.zoom,
		"compact_interior": current.get_meta("compact_interior", Rect2())}

static func handoff(target: Camera2D, state: Dictionary) -> void:
	if target == null: return
	target.offset = Vector2.ZERO
	var interior: Rect2 = state.get("compact_interior", Rect2())
	if interior.has_area():
		target.set_meta("compact_interior", interior)
	else:
		target.remove_meta("compact_interior")
	if target.has_method("set_overview_mode"): target.set_overview_mode(false)
	if "_shake_amount" in target: target._shake_amount = 0.0
	var actor := target.get_parent() as Node2D
	if actor:
		var center: Vector2 = state.get("center", actor.global_position)
		# Scene relocation is not a camera pan across the entire map.
		if not center.is_finite() or center.distance_to(actor.global_position) > 240.0:
			center = actor.global_position
		target.global_position = center
	var previous_zoom: Vector2 = state.get("zoom", target.zoom)
	if previous_zoom.is_finite() and previous_zoom.x > 0.0 and previous_zoom.y > 0.0:
		target.zoom = previous_zoom
	target.enabled = true
	target.set_process(true)
	target.make_current()
	target.reset_smoothing()
	target.force_update_scroll()

func _ready() -> void:
	_setup_neon_vignette()

func _setup_neon_vignette() -> void:
	_neon_overlay = CanvasLayer.new()
	_neon_overlay.layer = 15
	add_child(_neon_overlay)
	
	_neon_vignette = ColorRect.new()
	_neon_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_neon_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_neon_vignette.color = Color(0, 0, 0, 0)
	_neon_overlay.add_child(_neon_vignette)

func set_overview_mode(enabled: bool) -> void:
	_is_overview_mode = enabled
	_is_dragging_overview = false
	_has_overview_parent_position = false
	if _is_overview_mode:
		var parent_node := get_parent()
		if parent_node is Node2D:
			_overview_parent_position = parent_node.global_position
			_has_overview_parent_position = true

func is_overview_mode() -> bool:
	return _is_overview_mode

func apply_shake(amount: float) -> void:
	if is_finite(amount):
		_shake_amount = maxf(_shake_amount, amount)

func _safe_zoom(value: float, fallback: float) -> float:
	return clampf(value, 0.05, 20.0) if is_finite(value) and value > 0.0 else fallback

func _input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event and key_event.pressed and not key_event.echo and key_event.keycode == overview_toggle_key:
		set_overview_mode(not _is_overview_mode)

	if not _is_overview_mode:
		return

	var mouse_button := event as InputEventMouseButton
	if mouse_button:
		if mouse_button.button_index == MOUSE_BUTTON_MIDDLE:
			_is_dragging_overview = mouse_button.pressed
			_drag_last_pos = mouse_button.position
			get_viewport().set_input_as_handled()
			return

	var mouse_motion := event as InputEventMouseMotion
	if mouse_motion and _is_dragging_overview:
		var world_delta := mouse_motion.relative / maxf(zoom.x, 0.001) * overview_pan_sensitivity
		global_position -= world_delta
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	# Long frames must interpolate, never extrapolate through zero zoom. Reject
	# non-finite inputs before division/lerp: clamping alone cannot repair NaN.
	delta = maxf(delta, 0.0) if is_finite(delta) else 0.0
	var rate := maxf(transition_speed, 0.0) if is_finite(transition_speed) else 4.2
	var blend := 1.0 - exp(-rate * delta)
	var safe_close := _safe_zoom(zoom_close, 1.8)
	zoom = Vector2(_safe_zoom(zoom.x, safe_close), _safe_zoom(zoom.y, safe_close))
	if not position.is_finite():
		position = Vector2.ZERO
	var parent = get_parent()
	var current_speed: float = 0.0
	var is_boosting: bool = false
	var has_neon: bool = false
	var neon_col: Color = Color.CYAN
	
	if parent is CharacterBody2D:
		var character_parent := parent as CharacterBody2D
		current_speed = character_parent.velocity.length()
		is_boosting = character_parent.get("is_boosting") == true
		has_neon = character_parent.get("has_neon") == true
		var n_col = character_parent.get("neon_color")
		neon_col = n_col if n_col is Color else Color.CYAN
	elif parent is RigidBody2D:
		var rigid_parent := parent as RigidBody2D
		current_speed = rigid_parent.linear_velocity.length()
		is_boosting = rigid_parent.get("is_boosting") == true
		has_neon = rigid_parent.get("has_neon") == true
		var n_col = rigid_parent.get("neon_color")
		neon_col = n_col if n_col is Color else Color.CYAN
	
	if not is_finite(current_speed):
		current_speed = 0.0
	var target_zoom_val: float
	var target_lead := Vector2.ZERO
	if _is_overview_mode:
		target_zoom_val = _safe_zoom(overview_zoom, 0.35)
	else:
		var speed_limit := max_speed if is_finite(max_speed) and max_speed > 0.0 else 600.0
		var speed_factor = clampf(current_speed / speed_limit, 0.0, 1.0)
		target_zoom_val = lerp(safe_close, _safe_zoom(zoom_far, 1.22), speed_factor)
	
	# Efeito Velozes e Furiosos: Nitro puxa o zoom para trás revelando o rastro de fogo!
	if is_boosting and not _is_overview_mode:
		target_zoom_val = _safe_zoom(zoom_nitro, 1.02)
		
	if has_meta("mountain_zoom") and not _is_overview_mode:
		target_zoom_val = _safe_zoom(float(get_meta("mountain_zoom")), safe_close)
	if has_meta("compact_interior"):
		var room: Rect2 = get_meta("compact_interior")
		var screen := get_viewport_rect().size
		target_zoom_val = minf(screen.x / room.size.x, screen.y / room.size.y) * 0.88
	var target_zoom_vec = Vector2(target_zoom_val, target_zoom_val)
	zoom = zoom.lerp(target_zoom_vec, blend)

	if _is_overview_mode:
		if _has_overview_parent_position and parent is Node2D:
			var current_parent_pos = (parent as Node2D).global_position
			var parent_delta = current_parent_pos - _overview_parent_position
			if parent_delta.is_finite():
				global_position -= parent_delta
			_overview_parent_position = current_parent_pos
	else:
		if current_speed > 8.0 and parent is CharacterBody2D:
			var char_parent := parent as CharacterBody2D
			var lead_mult = 1.35 if is_boosting else 1.0
			var safe_lead := maxf(lead_distance, 0.0) if is_finite(lead_distance) else 52.0
			target_lead = char_parent.velocity.normalized() * minf(safe_lead * lead_mult, current_speed * 0.10)
		
		# Lead is a world-space direction; the camera position is parent-local.
		var local_lead: Vector2 = parent.global_transform.basis_xform_inv(target_lead) if parent is Node2D else target_lead
		if has_meta("compact_interior"):
			var room: Rect2 = get_meta("compact_interior")
			global_position = room.get_center()
		else:
			position = position.lerp(local_lead, blend)
		
	# Efeito de Vinheta de Neon pulsante na tela
	if _neon_vignette:
		if has_neon and (current_speed > 40.0 or is_boosting):
			var alpha_pulse = 0.08 + (0.12 if is_boosting else 0.05) * (0.8 + 0.2 * sin(Time.get_ticks_msec() * 0.008))
			_neon_vignette.color = Color(neon_col.r, neon_col.g, neon_col.b, alpha_pulse)
		else:
			_neon_vignette.color = _neon_vignette.color.lerp(Color(0, 0, 0, 0), 1.0 - exp(-4.0 * delta))
			
	# Screen Shake
	if _shake_amount > 0.0:
		offset = Vector2(randf_range(-_shake_amount, _shake_amount), randf_range(-_shake_amount, _shake_amount)) * 30.0
		_shake_amount = move_toward(_shake_amount, 0.0, delta * 1.5)
	else:
		offset = Vector2.ZERO
