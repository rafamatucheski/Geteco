extends CanvasLayer
## Exterior zone changes only; camera panning and interiors never trigger titles.
var title: Label
var _current := ""
var _candidate := ""
var _stable := 0.0
var _elapsed := 0.0
var _tween: Tween

func _ready() -> void:
	layer = 12
	name = "ZoneEntryHUD"
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	title = Label.new()
	title.anchor_left = 0.2
	title.anchor_right = 0.8
	title.anchor_top = 0.18
	title.anchor_bottom = 0.18
	title.offset_bottom = 48
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_size_override("font_size",30)
	title.add_theme_color_override("font_color",Color("eee9d7"))
	title.add_theme_color_override("font_shadow_color",Color(0,0,0,0.75))
	title.add_theme_constant_override("shadow_offset_y",2)
	title.modulate.a = 0
	root.add_child(title)

static func zone_at(point: Vector2) -> String:
	if point.x >= 7300 and point.y < -2000: return "SERRA DA NEVASCA"
	if point.y < -4800 and point.x > 5300 and point.x < 7100: return "PONTE NORTE"
	if point.x >= 6760 and point.y > 700 and point.y < 2700: return "ASHBEND"
	if point.x >= 4380 and point.y < -100: return "NORTHGATE"
	if point.x >= 4380 and point.y < 2600: return "NORTHBANK"
	if point.y >= 2600: return "PORTO SUL"
	return "BREAKWATER"

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.2: return
	var step := _elapsed
	_elapsed = 0
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null: return
	if bool(player.get_meta("harbor_interior",false)) or bool(player.get_meta("mountain_interior",false)):
		_stable = 0
		return
	var actor: Node2D = player
	var travel := get_node_or_null("/root/RegionTravel")
	if travel:
		var car: Node2D = travel.controlled_car()
		if car != null: actor = car
	var next := zone_at(actor.global_position)
	if next != _candidate:
		_candidate = next
		_stable = 0
		return
	_stable += step
	if _stable < 0.6 or next == _current: return
	_current = next
	show_zone(next)

func show_zone(zone: String) -> void:
	if _tween: _tween.kill()
	if zone == "SERRA DA NEVASCA":
		title.text = ""
		title.modulate.a = 0
		return
	title.text = tr(zone)
	title.modulate.a = 0
	_tween = create_tween()
	_tween.tween_property(title,"modulate:a",1.0,0.35)
	_tween.tween_interval(2.4)
	_tween.tween_property(title,"modulate:a",0.0,0.8)
