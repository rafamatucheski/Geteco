extends Camera2D

## Câmera Dinâmica de Alta Velocidade com Efeitos de Neon e Nitro (Velozes e Furiosos Style)
## Expansão de FOV durante Boost de Nitro, Lead de Direção e Vinheta de Neon vibrante.

@export var zoom_close: float = 1.8   # Câmera próxima (Parado / baixa velocidade)
@export var zoom_far: float = 1.22    # Câmera distante (Velocidade de cruzeiro)
@export var zoom_nitro: float = 1.02  # Câmera hiper-afastada durante Nitro NOS
@export var max_speed: float = 600.0
@export var transition_speed: float = 4.2
@export var lead_distance: float = 52.0

var _shake_amount: float = 0.0
var _neon_overlay: CanvasLayer
var _neon_vignette: ColorRect

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

func apply_shake(amount: float) -> void:
	_shake_amount = maxf(_shake_amount, amount)

func _process(delta: float) -> void:
	var parent = get_parent()
	var current_speed: float = 0.0
	var is_boosting: bool = false
	var has_neon: bool = false
	var neon_col: Color = Color.CYAN
	
	if parent is CharacterBody2D or parent is RigidBody2D:
		current_speed = parent.velocity.length()
		is_boosting = parent.get("is_boosting") == true
		has_neon = parent.get("has_neon") == true
		var n_col = parent.get("neon_color")
		neon_col = n_col if n_col is Color else Color.CYAN
	
	var speed_factor = clampf(current_speed / max_speed, 0.0, 1.0)
	var target_zoom_val = lerp(zoom_close, zoom_far, speed_factor)
	
	# Efeito Velozes e Furiosos: Nitro puxa o zoom para trás revelando o rastro de fogo!
	if is_boosting:
		target_zoom_val = zoom_nitro
		
	var target_zoom_vec = Vector2(target_zoom_val, target_zoom_val)
	zoom = zoom.lerp(target_zoom_vec, transition_speed * delta)
	
	var target_lead := Vector2.ZERO
	if current_speed > 8.0 and parent is CharacterBody2D:
		var lead_mult = 1.35 if is_boosting else 1.0
		target_lead = parent.velocity.normalized() * minf(lead_distance * lead_mult, current_speed * 0.10)
		
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
