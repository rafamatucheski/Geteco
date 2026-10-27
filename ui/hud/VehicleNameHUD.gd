extends Label
## One restrained introduction per completed boarding, attached to the minimap.
const STYLE := preload("res://ui/GameStyle.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const FADE_IN := .45
const HOLD := 2.8
const FADE_OUT := .9
var _vehicle_id := 0
var _tween: Tween

func _ready() -> void:
	name = "VehicleName"
	mouse_filter = MOUSE_FILTER_IGNORE
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	position = Vector2(0, -40)
	size = Vector2(get_parent().size.x, 26)
	add_theme_font_override("font", STYLE.STRONG)
	add_theme_color_override("font_color", STYLE.TEXT)
	add_theme_color_override("font_outline_color", Color(0.04, .05, .06, .7))
	add_theme_constant_override("outline_size", 1)
	add_theme_color_override("font_shadow_color", Color(0, 0, 0, .65))
	add_theme_constant_override("shadow_offset_y", 2)
	visibility_changed.connect(_sync_animation_visibility)
	modulate.a = 0
	hide()

func sync(driving: Node) -> void:
	if get_tree().paused: return
	if not is_instance_valid(driving) or not driving.occupied or not is_instance_valid(driving.car) or driving.is_body_transition_active():
		if _vehicle_id != 0: _clear()
		return
	var vehicle: Node = driving.car
	var identity := vehicle.get_instance_id()
	if identity == _vehicle_id: return
	_clear()
	_vehicle_id = identity
	text = str(FLEET.spec(str(vehicle.archetype)).get("label", "")).strip_edges()
	if text.is_empty(): return
	# Keep long authored names within the map width without abbreviating them.
	var font_size := 15
	while font_size > 12 and STYLE.STRONG.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > size.x:
		font_size -= 1
	add_theme_font_size_override("font_size", font_size)
	show()
	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "modulate:a", 1.0, FADE_IN)
	_tween.tween_interval(HOLD)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_OUT)
	_tween.tween_callback(hide)
	_sync_animation_visibility()

func _sync_animation_visibility() -> void:
	if _tween == null or not _tween.is_valid(): return
	if is_visible_in_tree(): _tween.play()
	else: _tween.pause()

func _clear() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	_vehicle_id = 0
	modulate.a = 0
	text = ""
	hide()
