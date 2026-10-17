extends CanvasLayer
## Illustrated loading cover; real progress stays fixed above the cycling artwork.
const NODE_NAME := "LoadingCurtain"
const ARTWORK := preload("res://ui/LoadingArtwork.gd")
const SESSION_OPS := preload("res://runtime/SessionOperations.gd")
const LOADING_MUSIC := preload("res://ui/LoadingMusic.gd")
## Duração do fade final da cobertura (imagem e música).
const LIFT_SECONDS := 1.0
var _diagnostic_stage := 0
const DISPLAY_FONT: FontFile = preload("res://assets/fonts/barlow/BarlowSemiCondensed-SemiBold.ttf")
const BODY_FONT: FontFile = preload("res://assets/fonts/barlow/BarlowSemiCondensed-Regular.ttf")
const BACKGROUND := Color("101216")
const ACCENT := Color("eee0bd")
const TEXT := Color("eee9df")
var variant := 0
var stage_only := false
var _root: Control
var _stage: Label
var _percent: Label
var _fill: ColorRect
var _track: ColorRect
var _shown := 0.0
var _target := 0.0
var stage_message := "Carregando…"
var _lifting := false

static func variant_for(region_id: String) -> int:
	return 1 if region_id == "mountain" else 2 if region_id == "desert" else 0

static func existing(tree: SceneTree) -> CanvasLayer:
	return tree.root.get_node_or_null(NODE_NAME) as CanvasLayer

func _ready() -> void:
	name = NODE_NAME
	process_mode = Node.PROCESS_MODE_ALWAYS
	if stage_only:
		set_process(false)
		return
	layer = 120
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	LOADING_MUSIC.attach(self)
	var ink := ColorRect.new()
	ink.name = "Background"
	ink.color = BACKGROUND
	ink.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(ink)
	var art := ARTWORK.new()
	art.name = "Artwork"
	art.first_index = 3 if variant == 1 else 7 if variant == 2 else -1
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(art)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_bottom", 52)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(margin)
	var stack := VBoxContainer.new()
	stack.custom_minimum_size.x = 220
	stack.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	stack.size_flags_vertical = Control.SIZE_SHRINK_END
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)
	var brand := _label("HARBOR", 32, TEXT, DISPLAY_FONT)
	brand.name = "Brand"
	stack.add_child(brand)
	var status := HBoxContainer.new()
	stack.add_child(status)
	# Technical stage details stay available for diagnostics, outside the interface.
	_stage = _label("Carregando…", 16, TEXT, BODY_FONT)
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.add_child(_stage)
	_percent = _label("0%", 16, TEXT, BODY_FONT)
	status.add_child(_percent)
	_track = ColorRect.new()
	_track.color = Color("5a5b58")
	_track.custom_minimum_size.y = 3
	stack.add_child(_track)
	_fill = ColorRect.new()
	_fill.color = ACCENT
	_fill.size = Vector2(0, 2)
	_track.add_child(_fill)
	_track.resized.connect(_update_progress)
	set_process(false)

func _label(text: String, font_size: int, color: Color, font: Font) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, .85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label

func set_variant(index: int) -> void:
	variant = clampi(index, 0, 2)

func set_stage(value: float, message: String) -> void:
	if message != stage_message or _diagnostic_stage == 0:
		SESSION_OPS.finish(_diagnostic_stage, "advanced")
		_diagnostic_stage = SESSION_OPS.begin(self, "loading", message, {"progress":value})
	_target = maxf(_target, clampf(value, 0.0, 1.0))
	stage_message = message
	if not stage_only and _shown < _target: set_process(true)

func _update_progress() -> void:
	if _fill == null or _track == null: return
	_fill.size = Vector2(_track.size.x * _shown, _track.size.y)
	_percent.text = "%d%%" % floori(_shown * 100.0)

func _process(delta: float) -> void:
	_shown = move_toward(_shown, _target, delta * 0.9)
	_update_progress()
	if _shown >= _target: set_process(false)

func lift(settle_frames := 8) -> void:
	if _lifting: return
	_lifting = true
	set_stage(1.0, "Pronto")
	for i in settle_frames: await get_tree().process_frame
	_shown = 1.0
	_update_progress()
	# A imagem e a música saem juntas e devagar (1 s): nada corta de uma vez ao entrar no jogo.
	LOADING_MUSIC.fade_out(self, LIFT_SECONDS)
	if _root != null:
		var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_property(_root, "modulate:a", 0.0, LIFT_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await tween.finished
	queue_free()

func _exit_tree() -> void:
	SESSION_OPS.finish(_diagnostic_stage, "removed")
