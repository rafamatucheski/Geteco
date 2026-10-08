extends Control
const RULES := preload("res://activities/fishing/FishingRules.gd")
var state: Dictionary = {}
var _font: Font
var _style: StyleBoxFlat

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font
	_style = _panel()

func update_state(value: Dictionary) -> void:
	state = value
	queue_redraw()

func _draw() -> void:
	if state.is_empty() or _font == null: return
	var scale_factor := minf(size.x / 1280.0, size.y / 720.0)
	if scale_factor <= 0: return
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * scale_factor)
	var canvas := size / scale_factor
	var at := Vector2(canvas.x - 370, 108)
	draw_style_box(_style, Rect2(at, Vector2(340, 368)))
	_text(at + Vector2(18, 30), str(state.title), 21, Color("ede5c9"))
	_text(at + Vector2(18, 56), str(state.clock), 17, Color("b8ccc4"))
	var phase: String = state.phase
	var title: String = {
		"ready":"Prepare a vara", "charging":"Força do arremesso", "casting":"Arremessando...",
		"waiting":"Aguarde a boia afundar", "bite":"FISGUE AGORA!", "reeling":"Recolha e alivie a linha",
		"caught":"Peixe capturado", "missed":"O peixe escapou", "line_broke":"A linha rompeu",
	}.get(phase, "Prepare a vara")
	var title_color := Color.WHITE
	var detail_color := Color("d2ddd2")
	if phase == "bite":
		title_color = Color("f4c968")
	elif phase == "reeling":
		match str(state.get("fight_hint", "steady")):
			"run":
				title = "ARRANCADA · SOLTE A LINHA"
				title_color = Color("f0805b")
				detail_color = Color("f3ad8e")
			"recovery":
				title = "PEIXE CANSOU · RECOLHA"
				title_color = Color("a2d67c")
				detail_color = Color("c8e9a5")
			_:
				title = "CONTROLE A TENSÃO"
				title_color = Color("e6c36d")
	_text(at + Vector2(18, 91), title, 21, title_color)
	_text(at + Vector2(18, 116), str(state.detail), 16, detail_color)
	if phase in ["charging", "casting"]:
		_bar(at + Vector2(18, 133), float(state.charge), Color("77bba6"), "ARREMESSO")
	elif phase == "reeling":
		_bar(at + Vector2(18, 133), float(state.tension), Color("ed6a4c") if state.tension > .78 else Color("e6bc64"), "TENSÃO")
		_bar(at + Vector2(18, 167), float(state.progress), Color("78c7a3"), "RECOLHIMENTO")
	else:
		_text(at + Vector2(18, 155), "Maior peixe: " + RULES.kg(int(state.best)), 18, Color("f4c968"))
	var y := 212.0
	if state.tournament:
		for row in state.ranking:
			_text(at + Vector2(18, y), ("● " if row.player else "  ") + str(row.name), 15, Color("f4c968") if row.player else Color("c6d5ce"))
			_text(at + Vector2(218, y), RULES.kg(int(row.grams)), 15, Color("f4c968") if row.player else Color("c6d5ce"))
			y += 18
	else:
		_text(at + Vector2(18, y), "%d peixes nesta pescaria" % int(state.catches), 18, Color("c6d5ce"))
		_text(at + Vector2(18, y + 27), "%d / %d espécies descobertas" % [int(state.species), RULES.SPECIES.size()], 17, Color("c6d5ce"))
	_text(at + Vector2(18, 339), str(state.hint), 14, Color("d5e3d8"))
	_text(at + Vector2(18, 358), str(state.cancel), 14, Color("a3b7ad"))

func _text(at: Vector2, value: String, font_size: int, color: Color) -> void:
	draw_string(_font, at, value, HORIZONTAL_ALIGNMENT_LEFT, 310, font_size, color)

func _bar(at: Vector2, value: float, color: Color, label: String) -> void:
	_text(at, label, 11, Color("afc2b9"))
	draw_rect(Rect2(at + Vector2(0, 6), Vector2(302, 10)), Color("31483f"))
	draw_rect(Rect2(at + Vector2(0, 6), Vector2(302 * clampf(value, 0, 1), 10)), color)

func _panel() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(.025, .08, .065, .94)
	style.border_color = Color("587768")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	return style
