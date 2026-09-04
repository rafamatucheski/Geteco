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
	_shake_amount = maxf(_shake_amount, amount)

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
	
	var target_zoom_val: float
	var target_lead := Vector2.ZERO
	if _is_overview_mode:
		target_zoom_val = overview_zoom
	else:
		var speed_factor = clampf(current_speed / max_speed, 0.0, 1.0)
		target_zoom_val = lerp(zoom_close, zoom_far, speed_factor)
	
	# Efeito Velozes e Furiosos: Nitro puxa o zoom para trás revelando o rastro de fogo!
	if is_boosting and not _is_overview_mode:
		target_zoom_val = zoom_nitro
		
	var target_zoom_vec = Vector2(target_zoom_val, target_zoom_val)
	zoom = zoom.lerp(target_zoom_vec, transition_speed * delta)

	if _is_overview_mode:
		if _has_overview_parent_position and parent is Node2D:
			var current_parent_pos = (parent as Node2D).global_position
			var parent_delta = current_parent_pos - _overview_parent_position
			global_position -= parent_delta
			_overview_parent_position = current_parent_pos
	else:
		if current_speed > 8.0 and parent is CharacterBody2D:
			var char_parent := parent as CharacterBody2D
			var lead_mult = 1.35 if is_boosting else 1.0
			target_lead = char_parent.velocity.normalized() * minf(lead_distance * lead_mult, current_speed * 0.10)
		
		position = position.lerp(target_lead, minf(1.0, transition_speed * delta))
		
	# Efeito de Vinheta de Neon pulsante na tela
	if _neon_vignette:
		if has_neon and (current_speed > 40.0 or is_boosting):
			var alpha_pulse = 0.08 + (0.12 if is_boosting else 0.05) * (0.8 + 0.2 * sin(Time.get_ticks_msec() * 0.008))
			_neon_vignette.color = Color(neon_col.r, neon_col.g, neon_col.b, alpha_pulse)
		else:
			_neon_vignette.color = _neon_vignette.color.lerp(Color(0, 0, 0, 0), 4.0 * delta)
			
	# Screen Shake
	if _shake_amount > 0.0:
		offset = Vector2(randf_range(-_shake_amount, _shake_amount), randf_range(-_shake_amount, _shake_amount)) * 30.0
		_shake_amount = move_toward(_shake_amount, 0.0, delta * 1.5)
	else:
		offset = Vector2.ZERO
